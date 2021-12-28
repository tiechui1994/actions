#!/bin/bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=2.5.0}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/openvpn}

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
    apt-get install -y build-essential g++ sudo curl make gcc file tar tzdata
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

download_openvpn() {
    url="https://swupdate.openvpn.org/community/releases/openvpn-$version.tar.gz"
    download "openvpn.tar.gz" "$url" curl 1
    return $?
}

download_openssl() {
    url="https://www.openssl.org/source/openssl-1.1.1m.tar.gz"
    download "openssl.tar.gz" "$url" curl 1
    return $?
}

build_openssl() {
     cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)

     # /usr/local/include /usr/local/lib /usr/local/share/[doc|man]
     cd "$workdir/openssl"
     ./config '-fPIC' && make -j${cpu} && sudo make install
     if [[ $? -ne ${success} ]]; then
        return $?
     fi
}

build() {
    sudo apt-get update && \
    sudo apt-get install build-essential pkg-config -y
    if [[ $? -ne 0 ]]; then
        log_error "apt-get fail"
        return ${failure}
    fi

    # create openvpn dir
    rm -rf ${installdir} && mkdir -p ${installdir}

    cd ${workdir}/openvpn

    ./configure \
    --prefix=${installdir} \
    --enable-systemd \
    --enable-pkcs11 \
    --enable-iproute2

    if [[ $? -ne 0 ]]; then
        log_error "configure fail"
        return ${failure}
    fi

    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    make -j ${cpu}
    if [[ $? -ne 0 ]]; then
        log_error "build fail"
        return ${failure}
    fi

    sudo make install
    if [[ $? -ne 0 ]]; then
        log_error "install failed"
        return ${failure}
    fi

    log_info "build openvpn success"
    log_info "openvpn info:$(ldd ${installdir}/sbin/openvpn)"
}

service() {
    echo
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    # control
    cat > debian/DEBIAN/control <<- EOF
Package: openvpn
Version: ${version}
Description: openvpn server deb package
Section: utils
Priority: standard
Essential: no
Architecture: amd64
Depends:
Maintainer: tiechui1994 <2904951429@qq.com>
Provides: github

EOF

    # postinst
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

# start up
systemctl daemon-reload
if [[ $? -ne 0 ]]; then
    echo "service start openvpn failed"
fi
EOF

    regex='$installdir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > debian/DEBIAN/postinst

    # postrm
    cat > debian/DEBIAN/postrm <<- EOF
#!/bin/bash

rm -rf ${installdir}
EOF

    # chmod
    sudo chmod a+x debian/DEBIAN/postinst
    sudo chmod a+x debian/DEBIAN/postrm

    # dir
    mkdir -p debian/${installdir}
    sudo mv ${installdir}/* debian/${installdir}

    # deb
    sudo dpkg-deb --build debian
    if [[ -z ${NAME} ]]; then
        NAME=openvpn_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
}

clean() {
    sudo rm -rf ${workdir}/openvpn
    sudo rm -rf ${workdir}/openvpn.tar.gz
}

do_install(){
     if [[ ${INIT} ]]; then
        init
     fi

     download_openssl && build_openssl
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     download_openvpn && build
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
