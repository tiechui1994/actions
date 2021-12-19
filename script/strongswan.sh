#!/usr/bin/env bash


VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=5.9.0}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/strongswan}

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

download_strongswan() {
    url="https://download.strongswan.org/strongswan-$version.tar.gz"
    download "strongswan.tar.gz" "$url" curl 1
    return $?
}

build() {
    sudo apt-get update && \
    sudo apt-get install build-essential \
        libpam0g-dev libssl-dev -y

    # create strongswan dir
    rm -rf ${installdir} && \
    mkdir -p ${installdir} && \
    mkdir -p ${installdir}/systemd && \

    # build and install
    cd ${workdir}/strongswan

    ./configure \
    --prefix=${installdir} \
    --enable-eap-identity \
    --enable-eap-md5 \
    --enable-eap-mschapv2 \
    --enable-eap-tls \
    --enable-eap-ttls \
    --enable-eap-peap  \
    --enable-eap-tnc \
    --enable-eap-dynamic \
    --enable-eap-radius \
    --enable-xauth-eap  \
    --enable-xauth-pam  \
    --enable-dhcp  \
    --enable-openssl  \
    --enable-addrblock \
    --enable-unity  \
    --enable-certexpire \
    --enable-radattr \
    --enable-swanctl \
    --enable-openssl \
    --disable-gmp

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

    log_info "build strongswan success"
    log_info "swanctl info: $(ldd ${installdir}/sbin/swanctl)"
    log_info "ipsec info: $(ldd ${installdir}/sbin/ipsec)"
}

service() {
    # service
    read -r -d '' conf <<- 'EOF'
[Unit]
Description=strongSwan IPsec IKEv1/IKEv2 daemon using ipsec.conf
After=network-online.target

[Service]
ExecStart=$installdir/sbin/ipsec start --nofork --conf $installdir/etc/ipsec.conf
ExecReload=$installdir/sbin/ipsec reload
StandardOutput=syslog
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

    regex='$installdir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > ${installdir}/systemd/strongswan.service
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    # control
    cat > debian/DEBIAN/control <<- EOF
Package: strongswan
Version: ${version}
Description: strongswan server deb package
Section: utils
Priority: standard
Essential: no
Architecture: amd64
Depends:
Maintainer: tiechui1994 <2904951429@qq.com>
Provides: github

EOF

    # postinst
    cat > debian/DEBIAN/postinst <<- EOF
#!/bin/bash

# lib
echo "${installdir}/lib" > /etc/ld.so.conf.d/strongswan.conf
ldconfig

# copy file
cp ${installdir}/systemd/strongswan.service /etc/systemd/system/strongswan.service

# start
systemctl daemon-reload && \
systemctl start strongswan.service
if [[ $? -ne 0 ]]; then
    echo "systemctl start strongswan.service failed"
fi

# test pid
if [[ $(pgrep ${installdir}/lib/ipsec/starter) ]]; then
    echo "strongswan install successfully !"
fi
EOF

    # prerm
    cat > debian/DEBIAN/prerm <<- EOF
#!/bin/bash

systemctl stop strongswan.service
EOF

    # postrm
    cat > debian/DEBIAN/postrm <<- EOF
#!/bin/bash

rm -rf /etc/systemd/system/strongswan.service
rm -rf /etc/ld.so.conf.d/strongswan.conf
rm -rf ${installdir}
ldconfig
EOF

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
        NAME=strongswan_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
}

clean() {
    sudo rm -rf ${workdir}/strongswan
    sudo rm -rf ${workdir}/strongswan.tar.gz
}

do_install(){
     if [[ ${INIT} ]]; then
        init
     fi

     download_strongswan
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
