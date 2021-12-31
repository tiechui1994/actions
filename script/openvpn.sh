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
    apt-get install -y --no-install-recommends \
        build-essential sudo curl wget make gcc file tar tzdata unzip patch
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

build_openssl() {
    cd "$workdir"
    openssl_version="1.1.1m"
    url="https://www.openssl.org/source/openssl-$openssl_version.tar.gz"
    download "openssl.tar.gz" "$url" curl 1
    if [[ $? -ne ${success} ]]; then
        return ${failure}
    fi

    # /usr/local/include /usr/local/lib /usr/local/share/[doc|man]
    cd "$workdir/openssl"
    ./config --prefix="$workdir/x64" \
        LDFLAGS="-fPIC" \
        no-autoload-config
    if [[ $? -ne ${success} ]]; then
        log_error "configure openssl failed"
        return ${failure}
    fi

    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    make -j ${cpu} && sudo make install > /dev/null
    if [[ $? -ne ${success} ]]; then
        log_error "build openssl failed"
        return ${failure}
    fi
}

build_lz4() {
    cd "$workdir"
    lz4_version="1.9.3"
    url="https://codeload.github.com/lz4/lz4/tar.gz/refs/tags/v$lz4_version"
    download "lz4.tar.gz" "$url" curl 1
    if [[ $? -ne ${success} ]]; then
        return ${failure}
    fi

    cd "$workdir/lz4"
    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    make BUILD_STATIC=yes V=1 -j ${cpu} && \
    sudo make install PREFIX=${workdir}/x64 BUILD_STATIC=yes V=1
    if [[ $? -ne ${success} ]]; then
        log_error "make build lz4 failed"
        return ${failure}
    fi
}

build_lzo() {
    cd "$workdir"
    lzo_version="2.10"
    url="http://www.oberhumer.com/opensource/lzo/download/lzo-$lzo_version.tar.gz"
    download "lzo.tar.gz" "$url" curl 1
    if [[ $? -ne ${success} ]]; then
        return ${failure}
    fi

    cd "$workdir/lzo"
    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    ./configure --prefix=${workdir}/x64 --disable-shared
    if [[ $? -ne ${success} ]]; then
        log_error "configure lzo failed"
        return ${failure}
    fi

    make -j ${cpu} && sudo make install > /dev/null
    if [[ $? -ne ${success} ]]; then
        log_error "make build lzo failed"
        return ${failure}
    fi
}

build_pkcs11() {
    cd "$workdir"
    pcks11_version="1.27.0"
    pcks11_path="${pcks11_version%%\.0}"
    url="https://github.com/OpenSC/pkcs11-helper/releases/download/pkcs11-helper-${pcks11_path}/pkcs11-helper-${pcks11_version}.tar.bz2"
    download "pkcs11.tar.bz2" "$url" curl 1
    if [[ $? -ne ${success} ]]; then
        return ${failure}
    fi

    cd "$workdir/pkcs11"
    ./configure \
       --disable-crypto-engine-gnutls \
	   --disable-crypto-engine-nss \
	   --prefix="$workdir/x64" \
	   OPENSSL_CFLAGS="-I$workdir/x64/include" \
	   OPENSSL_LIBS="-L$workdir/x64/lib -lssl -lcrypto" \
	   CFLAGS="-I$workdir/x64/include" \
	   LIBS="-L$workdir/x64/lib -lssl -lcrypto"

    if [[ $? -ne ${success} ]]; then
        log_error "configure pkcs11 failed"
        return ${failure}
    fi

    make && sudo make install
    if [[ $? -ne ${success} ]]; then
        log_error "make build pkcs11 failed"
        return ${failure}
    fi
}

download_openvpn() {
    cd "$workdir"
    url="https://swupdate.openvpn.org/community/releases/openvpn-$version.tar.gz"
    download "openvpn.tar.gz" "$url" curl 1
}

build() {
    sudo apt-get update && \
    sudo apt-get install build-essential gcc libc6-dev \
         net-tools libpam0g-dev pkg-config -y
    if [[ $? -ne 0 ]]; then
        log_error "apt-get fail"
        return ${failure}
    fi

    # create openvpn dir
    rm -rf ${installdir}

    LIBPATH="${installdir}/lib"

    cd ${workdir}/openvpn

    ./configure \
    --prefix=${installdir} \
    --enable-pkcs11 \
    --enable-static \
    --enable-iproute2 \
    --enable-x509-alt-username \
    --enable-async-push \
    OPENSSL_CRYPTO_CFLAGS="-I${workdir}/x64/include" \
    OPENSSL_CRYPTO_LIBS="-L${workdir}/x64/lib -lcrypto" \
    OPENSSL_CFLAGS="-I${workdir}/x64/include" \
    OPENSSL_LIBS="-L${workdir}/x64/lib -lssl -lcrypto" \
    LZO_CFLAGS="-I${workdir}/x64/include" \
    LZO_LIBS="-L${workdir}/x64/lib -llzo2" \
    LZ4_CFLAGS="-I${workdir}/x64/include" \
    LZ4_LIBS="-L${workdir}/x64/lib -llz4" \
    PKCS11_HELPER_CFLAGS="-I${workdir}/x64/include" \
    PKCS11_HELPER_LIBS="-L${workdir}/x64/lib -lpkcs11-helper" \
    CFLAGS="-I$workdir/x64/include" \
    LDFLAGS="-Wl,-rpath,$LIBPATH" \
	LIBS="-L$workdir/x64/lib -lssl -lcrypto -llzo2 -llz4 -lpkcs11-helper" \
	IPROUTE="/usr/bin/ip" \
	ROUTE="/sbin/route"

    if [[ $? -ne 0 ]]; then
        log_error "configure fail"
        log_error "$(cat config.log)"
        return ${failure}
    fi

    cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
    make -j ${cpu}
    if [[ $? -ne 0 ]]; then
        log_error "build fail"
        return ${failure}
    fi

    sudo make install > /dev/null
    if [[ $? -ne 0 ]]; then
        log_error "install failed"
        return ${failure}
    fi

    cp -Lr "$workdir/x64/lib/libcrypto.so.1.1" "$LIBPATH"
    cp -Lr "$workdir/x64/lib/libssl.so.1.1" "$LIBPATH"
    cp -Lr "$workdir/x64/lib/liblz4.so.1" "$LIBPATH"
    cp -Lr "$workdir/x64/lib/libpkcs11-helper.so.1" "$LIBPATH"

    cp -Lr "$workdir/x64/lib/libcrypto.a" "$LIBPATH"
    cp -Lr "$workdir/x64/lib/libssl.a" "$LIBPATH"
    cp -Lr "$workdir/x64/lib/liblz4.a" "$LIBPATH"
    cp -Lr "$workdir/x64/lib/liblzo2.a" "$LIBPATH"
    cp -Lr "$workdir/x64/lib/libpkcs11-helper.a" "$LIBPATH"

    log_info "build openvpn success"
    log_info "openvpn info:$(ldd ${installdir}/sbin/openvpn)"
    log_info "openvpn: $(find ${installdir})"
}

service() {
    mkdir -p ${installdir}/etc && \
    mkdir -p ${installdir}/etc/client && \
    mkdir -p ${installdir}/etc/server && \
    mkdir -p ${installdir}/systemd

    read -d '' -r conf <<-'EOF'
[Unit]
Description=OpenVPN service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecReload=/bin/true
WorkingDirectory=$installdir/etc

[Install]
WantedBy=multi-user.target
EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > ${installdir}/systemd/openvpn.service


    read -d '' -r conf <<-'EOF'
[Unit]
Description=OpenVPN connection to %i
PartOf=openvpn.service
ReloadPropagatedFrom=openvpn.service
Before=systemd-user-sessions.service
After=network-online.target
Wants=network-online.target
Documentation=https://community.openvpn.net/openvpn/wiki/Openvpn24ManPage
Documentation=https://community.openvpn.net/openvpn/wiki/HOWTO

[Service]
Type=simple
PrivateTmp=true
WorkingDirectory=$installdir/etc
ExecStart=$installdir/sbin/openvpn --daemon ovpn-%i --status /run/openvpn/%i.status 10 --cd $installdir/etc --config $installdir/etc/%i.conf --writepid /run/openvpn/%i.pid
PIDFile=/run/openvpn/%i.pid
KillMode=process
ExecReload=/bin/kill -HUP $MAINPID
CapabilityBoundingSet=CAP_IPC_LOCK CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE CAP_AUDIT_WRITE
LimitNPROC=100
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
ProtectSystem=true
ProtectHome=true
RestartSec=5s
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > ${installdir}/systemd/openvpn@.service


    read -d '' -r conf <<-'EOF'
[Unit]
Description=OpenVPN tunnel for %I
After=network-online.target
Wants=network-online.target
Documentation=https://community.openvpn.net/openvpn/wiki/Openvpn24ManPage
Documentation=https://community.openvpn.net/openvpn/wiki/HOWTO

[Service]
Type=simple
PrivateTmp=true
WorkingDirectory=$installdir/etc/client
ExecStart=$installdir/sbin/openvpn --suppress-timestamps --nobind --config %i.conf
CapabilityBoundingSet=CAP_IPC_LOCK CAP_NET_ADMIN CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
ProtectSystem=true
ProtectHome=true
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > ${installdir}/systemd/openvpn-client@.service


    read -d '' -r conf <<-'EOF'
[Unit]
Description=OpenVPN service for %I
After=network-online.target
Wants=network-online.target
Documentation=https://community.openvpn.net/openvpn/wiki/Openvpn24ManPage
Documentation=https://community.openvpn.net/openvpn/wiki/HOWTO

[Service]
Type=simple
PrivateTmp=true
WorkingDirectory=$installdir/etc/server
ExecStart=$installdir/sbin/openvpn --status %t/openvpn-server/status-%i.log --status-version 2 --suppress-timestamps --config %i.conf
CapabilityBoundingSet=CAP_IPC_LOCK CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE CAP_AUDIT_WRITE
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
ProtectSystem=true
ProtectHome=true
KillMode=process
RestartSec=5s
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > ${installdir}/systemd/openvpn-server@.service
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

# copy file
cp $installdir/systemd/openvpn.service /lib/systemd/system
cp $installdir/systemd/openvpn@.service /lib/systemd/system
cp $installdir/systemd/openvpn-client@.service /lib/systemd/system
cp $installdir/systemd/openvpn-server@.service /lib/systemd/system

# start up
systemctl daemon-reload
if [[ $? -ne 0 ]]; then
    echo "service start openvpn failed"
fi
EOF

    printf "%s" "${conf//'$installdir'/$installdir}" > debian/DEBIAN/postinst

    # postrm
    cat > debian/DEBIAN/postrm <<- EOF
#!/bin/bash

rm -rf /lib/systemd/system/openvpn.service
rm -rf /lib/systemd/system/openvpn@.service
rm -rf /lib/systemd/system/openvpn-client@.service
rm -rf /lib/systemd/system/openvpn-server@.service
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

    log_info "openvpn: $(ls -lh ${workdir}/${NAME})"
}

clean() {
    sudo rm -rf ${workdir}/openvpn
    sudo rm -rf ${workdir}/openvpn.tar.gz
    sudo rm -rf ${workdir}/openssl
    sudo rm -rf ${workdir}/openssl.tar.gz
    sudo rm -rf ${workdir}/lz4
    sudo rm -rf ${workdir}/lz4.tar.gz
    sudo rm -rf ${workdir}/lzo
    sudo rm -rf ${workdir}/lzo.tar.gz
    sudo rm -rf ${workdir}/pkcs11
    sudo rm -rf ${workdir}/pkcs11.tar.bz2
}

do_install(){
     if [[ ${INIT} ]]; then
        init
     fi

     build_openssl
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     build_lz4
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     build_lzo
     if [[ $? -ne ${success} ]]; then
        exit $?
     fi

     build_pkcs11
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
