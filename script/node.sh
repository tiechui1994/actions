#!/bin/bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=18.10.0}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/node}

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

download_node() {
    sudo apt-get update && \
    sudo apt-get install build-essential \
         openssl libssl-dev -y

    url="wget https://nodejs.org/dist/v$version/node-v$version.tar.gz"
    cd ${workdir} && download "node.tar.gz" "$url" curl 1
}


build() {
    cd ${workdir}/node

    ./configure \
    --prefix=${installdir}

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

    find . | grep node

    url="https://nodejs.org/dist/v$version/node-v$version-linux-x64.tar.gz"
    download "node-v$version-linux-x64.tar.gz" "$url" curl

    tar xf "node-v$version-linux-x64.tar.gz"
    mv out "node-v$version-linux-x64"
    tar cfz "node-v$version-linux-x64" "node-v$version-linux-x64.tar.gz"

    mv node-v$version-linux-x64.tar.gz" ${workdir}/$NAME
}


clean() {
    sudo rm -rf ${workdir}/node
    sudo rm -rf ${workdir}/node.tar.gz
}

do_install(){
     if [[ ${INIT} ]]; then
        init
     fi

     download_nginx && download_openssl && download_zlib && download_pcre && download_proxy_connect
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi


     build
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     clean
}

do_install
