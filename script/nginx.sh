#!/bin/bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=1.15.8}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/nginx}

declare -r success=0
declare -r failure=1

# log
log_error(){
    red="\033[31;1m"
    reset="\033[0m"
    msg="[E] $@"
    echo -e "$red$msg$reset"
}
log_warn(){
    yellow="\033[33;1m"
    reset="\033[0m"
    msg="[W] $@"
    echo -e "$yellow$msg$reset"
}
log_info() {
    green="\033[32;1m"
    reset="\033[0m"
    msg="[I] $@"
    echo -e "$green$msg$reset"
}

init() {
    apt-get update
    export DEBIAN_FRONTEND=noninteractive
    export TZ=Asia/Shanghai
    apt-get install -y build-essential g++ sudo curl make gcc file tar patch openssl tzdata
}

download() {
    name=$1
    url=$2
    cmd=$3
    decompress=$4

    declare -A extends=(
        ["tar"]="application/x-tar"
        ["tgz"]="application/gzip"
        ["tar.gz"]="application/gzip"
        ["tar.bz2"]="application/x-bzip2"
        ["tar.xz"]="application/x-xz"
    )

    extend="${name##*.}"
    filename="${name%%.*}"
    temp=${name%.*}
    if [[ ${temp##*.} = "tar" ]]; then
         extend="${temp##*.}.${extend}"
         filename="${temp%%.*}"
    fi

    # decompress file
    if [[ -f "$name" ]]; then
        if [[ ${decompress} && ${extends[$extend]} ]]; then
            if [[ $(file -i "$name") =~ ${extends[$extend]} ]]; then
                rm -rf ${filename} && mkdir ${filename}
                tar -xf ${name} -C ${filename} --strip-components 1
                if [[ $? -ne 0 ]]; then
                    log_error "$name decopress failed"
                    rm -rf ${filename} && rm -rf ${name}
                    return ${failure}
                fi

                return ${success} # success
            fi

            log_error "download file $name is invalid"
            return ${failure}
        fi

        return ${success} # success
    fi

    # download
    log_info "$name url: $url"
    log_info "begin to donwload $name ...."
    rm -rf ${name}

    command -v "$cmd" > /dev/null 2>&1
    if [[ $? -eq 0 && "$cmd" == "axel" ]]; then
        axel -n 10 --insecure --quite -o ${name} ${url}
    else
        curl -C - --insecure  --silent --location -o ${name} ${url}
    fi
    if [[ $? -ne 0 ]]; then
        log_error "download file $name failed !!"
        rm -rf ${name}
        return ${failure}
    fi

    log_info "success to download $name"

    # uncompress file
    if [[ ${decompress} && ${extends[$extend]} ]]; then
        if [[ $(file -i "$name") =~ ${extends[$extend]} ]]; then
            rm -rf ${filename} && mkdir ${filename}
            tar -xf ${name} -C ${filename} --strip-components 1
            if [[ $? -ne 0 ]]; then
                log_error "$name decopress failed"
                rm -rf ${filename} && rm -rf ${name}
                return ${failure}
             fi

            log_info "success to decompress $name"
            return ${success} # success
        fi

        log_error "download file $name is invalid"
        return ${failure}
    fi

    return ${success} # success
}

download_nginx() {
    sudo apt-get update && \
    sudo apt-get install build-essential \
        zlib1g-dev openssl libssl-dev libpcre3 libpcre3-dev libxml2 libxml2-dev libxslt-dev -y

    url="http://nginx.org/download/nginx-$version.tar.gz"
    cd ${workdir} && download "nginx.tar.gz" "$url" curl 1
}

download_openssl() {
    prefix="https://ftp.openssl.org/source/old"
    openssl="$(openssl version |cut -d " " -f2)"
    if [[ ${openssl} =~ ^1\.[0-1]\.[0-2]$ ]]; then
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl} ${openssl})
    else
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl:0:${#openssl}-1} ${openssl})
    fi
    cd ${workdir} && download "openssl.tar.gz" "$url" curl 1
}

download_pcre() {
    url="https://ftp.pcre.org/pub/pcre/pcre-8.44.tar.gz"
    url="https://nchc.dl.sourceforge.net/project/pcre/pcre/8.44/pcre-8.44.tar.gz"
    url="https://udomain.dl.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.bz2"
    cd ${workdir} && download "pcre.tar.bz2" "$url" curl 1
}

download_zlib() {
    url="http://www.zlib.net/fossils/zlib-1.2.11.tar.gz"
    url="https://codeload.github.com/madler/zlib/tar.gz/refs/tags/v1.2.11"
    cd ${workdir} && download "zlib.tar.gz" "$url" curl 1
}

# https proxy
# doc: https://github.com/chobits/ngx_http_proxy_connect_module
download_proxy_connect() {
    url="https://codeload.github.com/chobits/ngx_http_proxy_connect_module/tar.gz/v0.0.4"
    cd ${workdir} && download "ngx_http_proxy_connect_module.tar.gz" "$url" curl 1
    if [[ $? -ne ${success} ]]; then
        return $?
    fi

    cd ${workdir}/nginx
    # proxy_connect
    if [[ "$version" =~ 1.13.* || "$version" =~ 1.14.* ]]; then
        log_info "patch proxy_connect_rewrite_1014"
        patch -p1 < ${workdir}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_1014.patch
    elif [[ "$version" = "1.15.2"  ]]; then
        log_info "patch proxy_connect_rewrite_1015"
        patch -p1 < ${workdir}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_1015.patch
    elif [[ "$version" =~ 1.15.* || "$version" =~ 1.16.* ]]; then
        log_info "patch proxy_connect_rewrite_101504"
        patch -p1 < ${workdir}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_101504.patch
    elif [[ "$version" =~ 1.17.* || "$version" =~ 1.18.* ]]; then
        log_info "patch proxy_connect_rewrite_1018"
        patch -p1 < ${workdir}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_1018.patch
    elif [[ "$version" =~ 1.19.* || "$version" = 1.21.0 ]]; then
        log_info "patch proxy_connect_rewrite_1018"
        patch -p1 < ${workdir}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_1018.patch
    elif [[ "$version" =~ 1.21.1 || "$version" =~ 1.22.* ]]; then
        log_info "patch proxy_connect_rewrite_102101"
        patch -p1 < ${workdir}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch
    else
        log_info "patch proxy_connect_rewrite_102101"
        patch -p1 < ${workdir}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch
    fi
}

build_luajit() {
    cd ${workdir}/luajit && make
    if [[ $? -ne 0 ]]; then
        log_error "make luajit fail"
        return ${failure}
    fi

    sudo make install PREFIX=/tmp/luajit
    if [[ $? -ne 0 ]]; then
        log_error "make install luajit fail"
        rm -rf /tmp/luajit
        return ${failure}
    fi
}

# nginx lua
# doc: https://github.com/openresty/lua-nginx-module#installation
build_nginx_lua() {
    luajit="https://codeload.github.com/openresty/luajit2/tar.gz/refs/tags/v2.1-20211210"
    cd ${workdir} && download "luajit.tar.gz" "$luajit" curl 1
    if [[ $? -ne ${success} ]]; then
        return $?
    fi

    build_luajit
    if [[ $? -ne ${success} ]]; then
        return $?
    fi

    ngx_devel_kit="https://codeload.github.com/vision5/ngx_devel_kit/tar.gz/v0.3.1"
    cd ${workdir} && download "ngx_devel_kit.tar.gz" "$ngx_devel_kit" curl 1
    if [[ $? -ne ${success} ]]; then
        return ${failure}
    fi

    ngx_lua="https://codeload.github.com/openresty/lua-nginx-module/tar.gz/v0.10.20"
    if [[ "$version" =~ 1.15.* || "$version" =~ 1.16.* ||  "$version" =~ 1.18.* || "$version" =~ 1.20.* ]]; then
        ngx_lua="https://codeload.github.com/openresty/lua-nginx-module/tar.gz/v0.10.14"
    fi
    cd ${workdir} && download "lua-nginx-module.tar.gz" "$ngx_lua" curl 1
    if [[ $? -ne ${success} ]]; then
        return $?
    fi

    cd ${workdir}/nginx
    sudo mv /tmp/luajit ${installdir}/third/
    export LUAJIT_LIB="${installdir}/third/luajit/lib"
    export LUAJIT_INC="${installdir}/third/luajit/include/luajit-2.1"

    ./configure \
    --with-compat \
    --with-zlib=${workdir}/zlib \
    --with-pcre=${workdir}/pcre \
    --with-openssl=${workdir}/openssl \
    --add-dynamic-module=${workdir}/ngx_devel_kit \
    --add-dynamic-module=${workdir}/lua-nginx-module \
    --with-ld-opt="-lpcre -Wl,-rpath,$LUAJIT_LIB"
    if [[ $? -ne 0 ]]; then
        log_error "configure lua fail"
        return ${failure}
    fi

    make modules 1> ${workdir}/log 2>&1
    if [[ $? -ne 0 ]]; then
        log_error "build lua fail"
        tail -100 ${workdir}/log
        return ${failure}
    fi

    log_info "$(ls objs|grep -E '*.so$')"
    log_info "ngx_devel_kit info: $(ldd objs/ndk_http_module.so)"
    log_info "lua-nginx-module info: $(ldd objs/ngx_http_lua_module.so)"

    sudo cp objs/ndk_http_module.so ${workdir}/modules
    sudo cp objs/ngx_http_lua_module.so ${workdir}/modules

    cat > ${workdir}/modules-available/10-mod-http-ndk.conf <<-EOF
load_module share/modules/ndk_http_module.so;
EOF

    cat > ${workdir}/modules-available/50-mod-http-lua.conf <<-EOF
load_module share/modules/ngx_http_lua_module.so;
EOF
}

# nginx rtmp, 实时流推送
download_rtmp() {
    url="https://codeload.github.com/arut/nginx-rtmp-module/tar.gz/v1.2.2"
    cd ${workdir} && download "nginx-rtmp-module.tar.gz" "$url" curl 1
}

# nginx flv, http flv 格式实时流, 该模块是在 nginx-rtmp-module 基础上修改的.
download_flv() {
    cd ${workdir}
    url="https://codeload.github.com/winshining/nginx-http-flv-module/tar.gz/v1.2.9"
    cd ${workdir} && download "nginx-http-flv-module.tar.gz" "$url" curl 1
}

# other module
# doc: https://openresty.org/en/download.html
build() {
    # create nginx dir
    rm -rf ${installdir} && \
    mkdir -p ${installdir} && \
    mkdir -p ${installdir}/third && \
    mkdir -p ${installdir}/init.d && \
    mkdir -p ${installdir}/tmp/client && \
    mkdir -p ${installdir}/tmp/proxy && \
    mkdir -p ${installdir}/tmp/fcgi && \
    mkdir -p ${installdir}/tmp/uwsgi && \
    mkdir -p ${installdir}/tmp/scgi

    # create user
    if [[ -z "$(cat /etc/group | grep -E '^www:')" ]]; then
        sudo groupadd -r www
    fi

    if [[ -z "$(cat /etc/passwd | grep -E '^www:')" ]]; then
        sudo useradd -r www -g www
    fi

    ##
    # nginx配置模块解析:
    #   ngx_http_ssl_module  为HTTPS提供必要的支持, 需要OpenSSL库
    #   ngx_http_v2_module   提供了HTTP2协议的支持, 并取代ngx_http_spdy_module模块
    #   ngx_http_realip_module 用于改变客户端地址和可选端口在发送的头字段
    #   ngx_http_addition_module  在响应之前和之后添加文件内容
    #   ngx_http_xslt_module  过滤转换XML请求
    #   ngx_http_image_filter_module 实现图片裁剪, 缩放, 旋转功能, 支持jpg, gif, png格式, 需要gd库.
    #   ngx_http_geoip_module  可以用于IP访问限制
    #   ngx_http_sub_module  允许用一些其他文本替换nginx响应中的一些文本
    #   ngx_http_dav_module  增加PUT,DELETE,MKCOL(创建集合),COPY和MOVE方法
    #   ngx_http_flv_module  flv(流媒体点播)
    #   ngx_http_mp4_module  mp4(流媒体点播)
    #   ngx_http_gunzip_module
    #   ngx_http_gzip_static_module  在线实时压缩输出数据流
    #   ngx_http_auth_request_module 第三方auth支持
    #   ngx_http_random_index_module 从目录中随机挑选一个目录索引
    #   ngx_http_secure_link_module  计算和检查要求所需的安全链接网址
    #   ngx_http_degradation_module 许在内存不足的情况下返回204或444码
    #   ngx_http_slice_module  将一个请求分解成多个子请求, 每个子请求返回响应内容的一个片段，让大文件的缓存更有效
    #   ngx_http_stub_status_module 获取nginx自上次启动以来的工作状态
    #
    #   ngx_mail_ssl_module
    #
    #   ngx_stream_ssl_module
    #   ngx_stream_realip_module 真实ip
    #   ngx_stream_geoip_module  ip限制
    #   ngx_stream_ssl_preread_module
    #
    #   ngx_google_perftools_module
    #   ngx_cpp_test_module
    #
    ##
    # build and install
    cd ${workdir}/nginx

    ./configure \
    --user=www  \
    --group=www \
    --prefix=${installdir} \
    --modules-path=${installdir}/share/modules \
    --with-poll_module \
    --with-threads \
    --with-file-aio \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_auth_request_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_random_index_module \
    --with-http_stub_status_module  \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-debug \
    --with-compat \
    --with-zlib=${workdir}/zlib \
    --with-pcre=${workdir}/pcre \
    --with-openssl=${workdir}/openssl \
    --add-module=${workdir}/ngx_http_proxy_connect_module \
    --add-module=${workdir}/nginx-http-flv-module \
    --http-client-body-temp-path=${installdir}/tmp/client \
    --http-proxy-temp-path=${installdir}/tmp/proxy \
    --http-fastcgi-temp-path=${installdir}/tmp/fcgi \
    --http-uwsgi-temp-path=${installdir}/tmp/uwsgi \
    --http-scgi-temp-path=${installdir}/tmp/scgi
    if [[ $? -ne 0 ]]; then
        log_error "configure fail"
        return ${failure}
    fi

    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    openssl="$(openssl version |cut -d " " -f2)"
    if [[ ${openssl} > "1.1.0" ]]; then
        cpu=1
    fi

    make -j ${cpu}
    if [[ $? -ne 0 ]]; then
        log_error "build fail"
        return ${failure}
    fi

    sudo make install > ${workdir}/log 2>&1
    if [[ $? -ne 0 ]]; then
        log_error "install failed"
        tail -100 ${workdir}/log
        return ${failure}
    fi

    log_info "build nginx success"
    log_info "nginx info:$(ldd ${installdir}/sbin/nginx)"
}

service() {
    mkdir -p ${installdir}/share
    mv ${workdir}/modules ${installdir}/share
    mv ${workdir}/modules-available ${installdir}/share

    # conf template and add deafult conf file
    read -r -d '' conf <<- 'EOF'
user  www;
worker_processes 1;
include @installdir/share/modules-available/*.conf;

error_log  @installdir/logs/error.log  notice;
pid        @installdir/logs/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format    main  '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';

    access_log   @installdir/logs/access.log  main;
    sendfile     on;
    tcp_nopush   on;
    keepalive_timeout  65;
    gzip  on;

    #
    # other server config
    #
    include conf.d/*.conf;

    #
    # HTTP server
    #
    server {
        listen 80;
        server_name  localhost;
        location / {
            root   html;
            index  index.html index.htm;
        }

        error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }

        # proxy the PHP scripts to Apache listening on 127.0.0.1:80
        #
        #location ~ \.php$ {
        #    proxy_pass   http://127.0.0.1;
        #}

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
        #
        #location ~ \.php$ {
        #    root           html;
        #    fastcgi_pass   127.0.0.1:9000;
        #    fastcgi_index  index.php;
        #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
        #    include        fastcgi_params;
        #}

        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\.ht {
        #    deny  all;
        #}
    }

    #
    # HTTPS server
    #
    #server {
    #    listen       443 ssl;
    #    server_name  localhost;
    #
    #    ssl_certificate      cert.pem;
    #    ssl_certificate_key  cert.key;
    #
    #    ssl_session_cache    shared:SSL:1m;
    #    ssl_session_timeout  5m;
    #
    #    ssl_ciphers  HIGH:!aNULL:!MD5;
    #    ssl_prefer_server_ciphers  on;
    #
    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}
}
EOF
    printf "%s" "${conf//'@installdir'/$installdir}" > /tmp/nginx.conf
    sudo mv /tmp/nginx.conf ${installdir}/conf/nginx.conf

    if [[ ! -d ${installdir}/conf/conf.d ]]; then
        sudo mkdir -p ${installdir}/conf/conf.d
    fi

    # start up template file and instace
    read -r -d '' startup <<- 'EOF'
#!/bin/bash

### BEGIN INIT INFO
# Provides:   nginx
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Default-Start:     2
# Default-Stop:      0 1 3 4 5 6
# Description:       starts nginx using start-stop-daemon
### END INIT INFO

DAEMON=@installdir/sbin/nginx
CONF=@installdir/conf/nginx.conf
PID=@installdir/logs/nginx.pid
NAME=nginx
DESC=nginx

# Include nginx defaults if available
if [ -r /etc/default/nginx ]; then
    . /etc/default/nginx
fi

test -x ${DAEMON} || exit 0

. /lib/init/vars.sh
. /lib/lsb/init-functions

# Try to extract nginx pidfile
PID=$(cat ${CONF} | grep -Ev '^\s*#' | awk 'BEGIN { RS="[;{}]" } { if ($1 == "pid") print $2 }' | head -n1)

# Check if the ULIMIT is set in /etc/default/nginx
if [ -n "${ULIMIT}" ]; then
    # Set the ulimits
    ulimit ${ULIMIT}
fi

#
# Function that starts the daemon/service
#
do_start()
{
    # Return
    #   0 if daemon has been started
    #   1 if daemon was already running
    #   2 if daemon could not be started
    start-stop-daemon --start --pidfile ${PID} --make-pidfile --exec ${DAEMON} --test > /dev/null \
        || return 1
    start-stop-daemon --start --pidfile ${PID} --make-pidfile --exec ${DAEMON} -- \
        ${DAEMON_OPTS} 2>/dev/null \
        || return 2
}

test_nginx_config() {
    ${DAEMON} -t ${DAEMON_OPTS} >/dev/null 2>&1
}

#
# Function that stops the daemon/service
#
do_stop()
{
    # Return
    #   0 if daemon has been stopped
    #   1 if daemon was already stopped
    #   2 if daemon could not be stopped
    #   other if a failure occurred
    start-stop-daemon --stop --retry=TERM/30/KILL/5 --pidfile ${PID} --name ${NAME}
    RETVAL="$?"

    sleep 1
    return "${RETVAL}"
}

#
# Function that sends a SIGHUP to the daemon/service
#
do_reload() {
    start-stop-daemon --stop --signal HUP --pidfile ${PID} --name ${NAME}
    return 0
}

#
# Rotate log files
#
do_rotate() {
    start-stop-daemon --stop --signal USR1 --pidfile ${PID} --name ${NAME}
    return 0
}

#
# Online upgrade nginx executable
#
# "Upgrading Executable on the Fly"
# http://nginx.org/en/docs/control.html
#
do_upgrade() {
    # Return
    #   0 if nginx has been successfully upgraded
    #   1 if nginx is not running
    #   2 if the pid files were not created on time
    #   3 if the old master could not be killed
    if start-stop-daemon --stop --signal USR2 --quiet --pidfile ${PID} --name ${NAME}; then
        # Wait for both old and new master to write their pid file
        while [ ! -s "${PID}.oldbin" ] || [ ! -s "${PID}" ]; do
            cnt=`expr ${cnt} + 1`
            if [ ${cnt} -gt 10 ]; then
                return 2
            fi
            sleep 1
        done
        # Everything is ready, gracefully stop the old master
        if start-stop-daemon --stop --signal QUIT --quiet --pidfile "${PID}.oldbin" --name ${NAME}; then
            return 0
        else
            return 3
        fi
    else
        return 1
    fi
}

case "$1" in
    start)
        log_daemon_msg "Starting ${DESC}" "${NAME}"
        do_start
        case "$?" in
            0|1) log_end_msg 0 ;;
            2)   log_end_msg 1 ;;
        esac
        ;;
    stop)
        log_daemon_msg "Stopping ${DESC}" "${NAME}"
        do_stop
        case "$?" in
            0|1) log_end_msg 0 ;;
            2)   log_end_msg 1 ;;
        esac
        ;;
    restart)
        log_daemon_msg "Restarting ${DESC}" "${NAME}"

        # Check configuration before stopping nginx
        if ! test_nginx_config; then
            log_end_msg 1 # Configuration error
            exit 0
        fi

        do_stop
        case "$?" in
            0|1)
                do_start
                case "$?" in
                    0) log_end_msg 0 ;;
                    1) log_end_msg 1 ;; # Old process is still running
                    *) log_end_msg 1 ;; # Failed to start
                esac
                ;;
            *)
                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;
    reload|force-reload)
        log_daemon_msg "Reloading ${DESC} configuration" "${NAME}"

        # Check configuration before reload nginx
        #
        # This is not entirely correct since the on-disk nginx binary
        # may differ from the in-memory one, but that's not common.
        # We prefer to check the configuration and return an error
        # to the administrator.
        if ! test_nginx_config; then
            log_end_msg 1 # Configuration error
            exit 0
        fi

        do_reload
        log_end_msg $?
        ;;
    configtest|testconfig)
        log_daemon_msg "Testing ${DESC} configuration"
        test_nginx_config
        log_end_msg $?
        ;;
    status)
        status_of_proc -p ${PID} "${DAEMON}" "${NAME}" && exit 0 || exit $?
        ;;
    upgrade)
        log_daemon_msg "Upgrading binary" "${NAME}"
        do_upgrade
        log_end_msg 0
        ;;
    rotate)
        log_daemon_msg "Re-opening ${DESC} log files" "${NAME}"
        do_rotate
        log_end_msg $?
        ;;
    *)
        echo "Usage: ${NAME} {start|stop|restart|reload|force-reload|status|configtest|rotate|upgrade}" >&2
        exit 3
        ;;
esac
EOF

    printf "%s" "${startup//'@installdir'/$installdir}" > /tmp/nginx
    chmod a+x /tmp/nginx
    sudo mv /tmp/nginx ${installdir}/init.d/nginx
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    arch="amd64"
    if [[ ${NAME} =~ (.*)?arm64.deb$ ]]; then
        arch="arm64"
    fi

    # control
    cat > debian/DEBIAN/control <<- EOF
Package: Nginx
Version: ${version}
Description: Nginx server deb package
Section: utils
Priority: standard
Essential: no
Architecture: ${arch}
Depends:
Maintainer: tiechui1994 <2904951429@qq.com>
Provides: github

EOF
        # postinst
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

case "$1" in
    (configure)
        # user and group
        if [[ -z "$(cat /etc/group | grep -E '^www:')" ]]; then
            groupadd -r www
        fi
        if [[ -z "$(cat /etc/passwd | grep -E '^www:')" ]]; then
            useradd -r www -g www
        fi

        # dir owner
        chown -R www:www @installdir

        # link file
        ln -sf @installdir/init.d/nginx /etc/init.d/nginx

        # start up
        update-rc.d nginx defaults && \
        service nginx start
        if [[ $? -ne 0 ]]; then
            echo "service start nginx failed"
        fi

        # test pid
        if [[ $(pgrep nginx) ]]; then
            echo "nginx install successfully !"
        fi
    ;;
    (*)
        echo "postinst called with unknown argument \`$1'" >&2
        exit 0
    ;;
esac

EOF

    printf "%s" "${conf//'@installdir'/$installdir}" > debian/DEBIAN/postinst

    # prerm
    cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

case "$1" in
    (remove)
        service nginx status > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            service nginx stop
        fi
    ;;
esac

EOF

    # postrm
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

case "$1" in
    (remove)
        if [[ -f /etc/init.d/nginx ]]; then
            update-rc.d nginx remove
            rm -rf /etc/init.d/nginx
        fi

        if [[ -d @installdir ]]; then
            rm -rf @installdir
        fi

        if [[ -n "$(cat /etc/group | grep -E '^www:')" ]]; then
            groupdel -f www
        fi
        if [[ -n "$(cat /etc/passwd | grep -E '^www:')" ]]; then
            userdel -f www
        fi
    ;;
esac

EOF
    printf "%s" "${conf//'@installdir'/$installdir}" > debian/DEBIAN/postrm

    # chmod
    sudo chmod a+x debian/DEBIAN/postinst
    sudo chmod a+x debian/DEBIAN/postrm
    sudo chmod a+x debian/DEBIAN/prerm

    # dir
    mkdir -p debian/${installdir}
    sudo mv ${installdir}/* debian/${installdir}

    # deb
    sudo dpkg-deb --build debian
    if [[ -z ${NAME} ]]; then
        NAME=nginx_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
}

clean() {
    sudo rm -rf ${workdir}/nginx
    sudo rm -rf ${workdir}/nginx.tar.gz
    sudo rm -rf ${workdir}/openssl*
    sudo rm -rf ${workdir}/pcre*
    sudo rm -rf ${workdir}/zlib*
    sudo rm -rf ${workdir}/luajit*
    sudo rm -rf ${workdir}/lua-nginx-module*
    sudo rm -rf ${workdir}/ngx_devel_kit*
    sudo rm -rf ${workdir}/ngx_http_proxy_connect_module*
    sudo rm -rf ${workdir}/nginx-http-flv-module*
    sudo rm -rf ${workdir}/nginx-rtmp-module*
}

do_install(){
     if [[ ${INIT} ]]; then
        init
     fi

     download_nginx && download_openssl && download_zlib && download_pcre && download_proxy_connect && download_flv
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     mkdir -p ${workdir}/modules
     mkdir -p ${workdir}/modules-available

     build
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     build_nginx_lua
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     service
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     package
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     clean
}

do_install
