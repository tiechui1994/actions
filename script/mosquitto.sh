#!/usr/bin/env bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=1.15.8}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/mqtt}

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

download_mosquitto() {
    url="https://codeload.github.com/eclipse/mosquitto/tar.gz/refs/tags/v2.0.14"
    download "mosquitto.tar.gz" "$url" curl 1
    return $?
}

download_openssl() {
    prefix="https://ftp.openssl.org/source/old"
    openssl="$(openssl version |cut -d " " -f2)"
    openssl="1.1.1"
    if [[ ${openssl} =~ ^1\.[0-1]\.[0-2]$ ]]; then
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl} ${openssl})
    else
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl:0:${#openssl}-1} ${openssl})
    fi
    download "openssl.tar.gz" "$url" curl 1
    return $?
}

download_cjson() {
    url="https://codeload.github.com/DaveGamble/cJSON/tar.gz/refs/tags/v1.7.15"
    download "cjson.tar.gz" "$url" curl 1
    return $?
}

download_uthash() {
    url="https://codeload.github.com/troydhanson/uthash/tar.gz/refs/tags/v2.3.0"
    download "uthash.tar.gz" "$url" curl 1
    return $?
}

build_denpend() {
     # /usr/local/include /usr/local/lib /usr/local/share/[doc|man]
     cd "$workdir/openssl"
     ./config '-fPIC' && make && sudo make install
     if [[ $? -ne ${success} ]]; then
        return $?
     fi

     # /usr/local/include /usr/local/lib
     cd "$workdir/cjson"
     make && sudo make install &&
     sudo cp libcjson.a /usr/local/lib &&
     sudo cp libcjson_utils.a /usr/local/lib
     if [[ $? -ne ${success} ]]; then
        return $?
     fi

     sudo apt-get update &&
     sudo apt-get install xsltproc docbook-xsl
}

build() {
    cd ${workdir}/mosquitto

    make clean &&
    make WITH_STATIC_LIBRARIES=yes WITH_SHARED_LIBRARIES=no \
        LDFLAGS="-Wl,--static -lssl -lcrypto -lcjson -Wl,-Bdynamic -ldl"
    if [[ $? -ne 0 ]]; then
        log_error "make fail, plaease check and try again..."
        return ${failure}
    fi

    sudo make DESTDIR=/tmp/mqtt WITH_STATIC_LIBRARIES=yes WITH_SHARED_LIBRARIES=no \
        LDFLAGS="-Wl,--static -lssl -lcrypto -lcjson -Wl,-Bdynamic -ldl" \
        install
    if [[ $? -ne 0 ]]; then
        log_error "make install fail, plaease check and try again..."
        return ${failure}
    fi

    log_info "build mqtt success"
}

clean(){
    sudo rm -rf ${workdir}/openssl
    sudo rm -rf ${workdir}/openssl.tar.gz
    sudo rm -rf ${workdir}/cjson
    sudo rm -rf ${workdir}/cjson.tar.gz
    sudo rm -rf ${workdir}/uthash
    sudo rm -rf ${workdir}/uthash.tar.gz
}

do_install() {
    if [[ ${INIT} ]]; then
        init
    fi

    download_mosquitto && download_openssl && download_cjson && download_uthash
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    build_denpend
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