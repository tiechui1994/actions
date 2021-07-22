#!/bin/bash

TOKEN=$1
VERSION=$2

declare -r version=${VERSION:=5.0.0}
declare -r workdir=$(pwd)
declare -r installdir=/opt/local/redis

declare -r SUCCESS=0
declare -r FAILURE=1

# log
log_error(){
    red="\033[97;41m"
    reset="\033[0m"
    msg="[E] $@"
    echo -e "$red$msg$reset"
}
log_warn(){
    yellow="\033[90;43m"
    reset="\033[0m"
    msg="[W] $@"
    echo -e "$yellow$msg$reset"
}
log_info() {
    green="\033[97;42m"
    reset="\033[0m"
    msg="[I] $@"
    echo -e "$green$msg$reset"
}

common_download() {
    name=$1
    url=$2
    cmd=$3

    if [[ -d "$name" ]]; then
        log_info "$name has exist !!"
        return ${SUCCESS} #1
    fi

    if [[ -f "$name.tar.gz" && -n $(file "$name.tar.gz" | grep -o 'POSIX tar archive') ]]; then
        rm -rf ${name} && mkdir ${name}
        tar -zvxf ${name}.tar.gz -C ${name} --strip-components 1
        if [[ $? -ne 0 ]]; then
            log_error "$name decopress failed"
            rm -rf ${name} && rm -rf ${name}.tar.gz
            return ${FAILURE}
        fi

        return ${SUCCESS} #2
    fi

    log_info "$name url: $url"
    log_info "begin to donwload $name ...."
    rm -rf ${name}.tar.gz
    command_exists "$cmd"
    if [[ $? -eq 0 && "$cmd" == "axel" ]]; then
        axel -n 10 --insecure --quite -o "$name.tar.gz" ${url}
    else
        curl -C - --insecure --silent ${url} -o "$name.tar.gz"
    fi

    if [[ $? -ne 0 ]]; then
        log_error "download file $name failed !!"
        rm -rf ${name}.tar.gz
        return ${FAILURE}
    fi

    log_info "success to download $name"
    rm -rf ${name} && mkdir ${name}
    tar -zxf ${name}.tar.gz -C ${name} --strip-components 1
    if [[ $? -ne 0 ]]; then
        log_error "$name decopress failed"
        rm -rf ${name} && rm -rf ${name}.tar.gz
        return ${FAILURE}
    fi
}

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

check() {
    sudo apt-get update && \
    sudo apt-get install jq -y
    url=https://api.github.com/repos/tiechui1994/jobs/releases/tags/redis_${version}
    result=$(curl -H "Accept: application/vnd.github.v3+json" \
                  -H "Authorization: token ${TOKEN}" ${url})
    echo "result: ${result}"
    message=$(echo ${result} | jq .message)
    echo "message: ${message}"
    if [[ ${message} = '"Not Found"' ]]; then
        return ${SUCCESS}
    fi

    return ${FAILURE}
}

download_redis() {
    url="https://codeload.github.com/redis/redis/tar.gz/$version"
    common_download "redis" ${url}
    return $?
}

build() {
    rm -rf ${installdir} && mkdir -p ${installdir}

    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    cd ${workdir}/redis && make -j ${cpu}
    if [[ $? -ne 0 ]]; then
        log_error "build fail"
        return ${FAILURE}
    fi

    make PREFIX=${installdir} install
    if [[ $? -ne 0 ]]; then
        log_error "install failed"
        return ${FAILURE}
    fi
}

service() {
    # mkdir
    mkdir ${installdir}/data && \
    mkdir ${installdir}/logs && \
    mkdir -p ${installdir}/conf

    # copy conf
    cp redis.conf ${installdir}/conf && \
    cp sentinel.conf ${installdir}/conf

    # change redis.conf
    sed -i \
    -e "s|^daemonize.*|daemonize yes|g" \
    -e "s|^supervised.*|supervised auto|g" \
    -e "s|^pidfile.*|pidfile $installdir/logs/redis_6379.pid|g" \
    -e "s|^logfile.*|logfile $installdir/logs/redis.log|g" \
    -e "s|^dir.*|dir $installdir/data/|g" \
    ${installdir}/conf/redis.conf
    if [[ $? -ne 0 ]]; then
        log_error "update redis.conf failed"
        return ${FAILURE}
    fi

    # service
    read -r -d '' startup <<- 'EOF'
#!/bin/bash

### BEGIN INIT INFO
# Provides:          redis
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Default-Start:     2
# Default-Stop:      0 1 3 4 5 6
# Description:       redis service daemon
### END INIT INFO

REDISPORT=6379
EXEC=$dir/bin/redis-server
CLIEXEC=$dir/bin/redis-cli

PIDFILE=$dir/logs/redis_${REDISPORT}.pid
CONF=$dir/conf/redis.conf

. /lib/lsb/init-functions

case "$1" in
    start)
        if [[ -f ${PIDFILE} ]]
        then
                log_failure_msg "${PIDFILE} exists, process is already running or crashed"
        else
                log_begin_msg "Starting Redis server..."
                $EXEC ${CONF}
        fi
        ;;
    stop)
        if [[ ! -f ${PIDFILE} ]]
        then
                log_failure_msg "${PIDFILE} does not exist, process is not running"
        else
                PID=$(cat ${PIDFILE})
                log_begin_msg "Stopping ..."

                ${CLIEXEC} -p ${REDISPORT} shutdown
                if [[ -e ${PIDFILE} ]];then
                    rm -rf ${PIDFILE}
                fi

                while [[ -x /proc/${PID} ]]
                do
                    log_begin_msg "Waiting for Redis to shutdown ..."
                    sleep 1
                done
                log_success_msg "Redis stopped"
        fi
        ;;
    *)
        log_failure_msg "Please use start or stop as first argument"
        ;;
esac
EOF

    regex='$dir'
    repl="$installdir"
    printf "%s" "${startup//$regex/$repl}" > ${installdir}/conf/redis.server
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    # control
cat > debian/DEBIAN/control <<- EOF
Package: Redis
Version: ${version}
Description: Redis server deb package
Section: utils
Priority: standard
Essential: no
Architecture: amd64
Maintainer: tiechui1994 <2904951429@qq.com>
Provides: github

EOF

        # postinst
read -r -d '' conf <<- 'EOF'
#!/bin/bash

# link file
chmod a+x $installdir/conf/redis.server
ln -sf $installdir/conf/redis.server /etc/init.d/redis
ln -sf $installdir/bin/redis-cli /usr/local/bin/redis-cli
ln -sf $installdir/bin/redis-server /usr/local/bin/redis-server

# start redis service
update-rc.d redis defaults && \
systemctl daemon-reload && service redis start
if [[ $? -ne 0 ]]; then
    echo "redis service start failed, please check and trg again..."
    exit
fi
EOF

    regex='$installdir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > debian/DEBIAN/postinst

cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

service redis stop
EOF


    # postrm
cat > debian/DEBIAN/postrm <<- EOF
#!/bin/bash

update-rc.d redis remove
rm -rf /etc/init.d/redis
rm -rf ${installdir}

unlink /usr/local/bin/redis-cli
unlink /usr/local/bin/redis-server
EOF

    # chmod
    sudo chmod a+x debian/DEBIAN/postinst
    sudo chmod a+x debian/DEBIAN/postrm
    sudo chmod a+x debian/DEBIAN/prerm

    # dir
    mkdir -p debian/${installdir}
    sudo cp -r ${installdir}/* debian/${installdir}


    # deb
    sudo dpkg-deb --build debian
    sudo mv debian.deb ${GITHUB_WORKSPACE}/redis_${version}_amd64.deb
    echo "TAG=redis_${version}" >> ${GITHUB_ENV}
    echo "DEB=redis_${version}_amd64.deb" >> ${GITHUB_ENV}

    # tgz
    rm -rf binary && mkdir -p binary
    sudo cp -r ${installdir}/bin/* binary
    sudo cp -r ${installdir}/conf/*.conf binary
    tar cvf redis_${version}_amd64.tgz binary
    sudo mv redis_${version}_amd64.tgz ${GITHUB_WORKSPACE}/redis_${version}_amd64.tgz
    echo "TAR=redis_${version}.tgz"
}

clean_file(){
    sudo rm -rf ${workdir}/redis
    sudo rm -rf ${workdir}/redis.tar.gz
}

do_install() {
    check
    if [[ $? -ne ${SUCCESS} ]]; then
        return
    fi

    download_redis
    if [[ $? -ne ${SUCCESS} ]]; then
        return
    fi

    build
    if [[ $? -ne ${SUCCESS} ]]; then
        return
    fi

    service
    if [[ $? -ne ${SUCCESS} ]]; then
        return
    fi

    package
    if [[ $? -ne ${SUCCESS} ]]; then
        return
    fi

    clean_file
}

do_install
