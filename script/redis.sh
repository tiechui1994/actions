#!/bin/bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=5.0.0}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/redis}

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

init() {
    apt-get update
    export DEBIAN_FRONTEND=noninteractive
    export TZ=Asia/Shanghai
    apt-get install -y build-essential g++ sudo curl make gcc file tar patch openssl tzdata
}

download_redis() {
    url="https://codeload.github.com/redis/redis/tar.gz/$version"
    download "redis.tar.gz" ${url} curl 1
}

build() {
    rm -rf ${installdir}

    cd ${workdir}/redis

    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    make -j ${cpu}
    if [[ $? -ne 0 ]]; then
        log_error "build fail"
        return ${failure}
    fi

    make PREFIX=${installdir} install
    if [[ $? -ne 0 ]]; then
        log_error "install failed"
        return ${failure}
    fi

    log_info "build redis success"
    log_info "redis-server info:$(ldd ${installdir}/bin/redis-server)"
    log_info "redis-cli info:$(ldd ${installdir}/bin/redis-cli)"
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
        return ${failure}
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
EXEC=$installdir/bin/redis-server
CLIEXEC=$installdir/bin/redis-cli

PIDFILE=$installdir/logs/redis_${REDISPORT}.pid
CONF=$installdir/conf/redis.conf

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

    printf "%s" "${startup//'$installdir'/$installdir}" > ${installdir}/conf/redis.server
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

    printf "%s" "${conf//'$installdir'/$installdir}" > debian/DEBIAN/postinst

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
    if [[ -z ${NAME} ]]; then
        NAME=redis_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
}

clean(){
    sudo rm -rf ${workdir}/redis
    sudo rm -rf ${workdir}/redis.tar.gz
}

do_install() {
    if [[ ${INIT} ]]; then
       init
    fi

    download_redis
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    build
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
