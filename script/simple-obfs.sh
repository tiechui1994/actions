#!/bin/bash

VERSION=$1
INIT=$2
NAME=$3

declare -r workdir=$(pwd)

declare -r success=0
declare -r failure=1

init() {
    apt-get update
    export DEBIAN_FRONTEND=noninteractive
    export TZ=Asia/Shanghai
    apt-get install -y build-essential g++ sudo curl make gcc file tar patch openssl tzdata \
        git autoconf libtool libssl-dev libpcre3-dev libev-dev asciidoc xmlto automake --no-install-recommends
}


clone() {
    git clone https://github.com/shadowsocks/simple-obfs.git ${workdir}/simple-obfs && \
    cd ${workdir}/simple-obfs && \
    git submodule update --init --recursive
}

build() {
    cd ${workdir}/simple-obfs && ./autogen.sh && ./configure && make
}

package() {
    cd ${workdir}
    mkdir obfs && cp ${workdir}/simple-obfs/src/obfs-server obfs/ && \
    cp ${workdir}/simple-obfs/src/obfs-local obfs/
    cd obfs && zip ${workdir}/${NAME} -r .
}

do_install(){
     if [[ ${INIT} ]]; then
        init
     fi

     clone
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     build
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     package
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi
}

do_install
