#!/usr/bin/env bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=2.0.14}
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
    apt-get install -y build-essential g++ sudo curl make gcc file tar patch tzdata rsync
}

download_mosquitto() {
    url="https://codeload.github.com/eclipse/mosquitto/tar.gz/refs/tags/v$version"
    download "mosquitto.tar.gz" "$url" curl 1
}

download_openssl() {
    prefix="https://ftp.openssl.org/source/old"
    openssl="$(openssl version |cut -d " " -f2)"
    if [[ ${openssl} < "1.1.1" ]]; then
        openssl="1.1.1"
    fi
    if [[ ${openssl} =~ ^1\.[0-1]\.[0-2]$ ]]; then
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl} ${openssl})
    else
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl:0:${#openssl}-1} ${openssl})
    fi
    download "openssl.tar.gz" "$url" curl 1
}

download_cjson() {
    url="https://codeload.github.com/DaveGamble/cJSON/tar.gz/refs/tags/v1.7.15"
    download "cjson.tar.gz" "$url" curl 1
}

download_uthash() {
    url="https://codeload.github.com/troydhanson/uthash/tar.gz/refs/tags/v2.3.0"
    download "uthash.tar.gz" "$url" curl 1
}

build_denpend() {
     cpu=$(cat /proc/cpuinfo | grep 'processor' | wc -l)

     # /usr/local/include /usr/local/lib /usr/local/share/[doc|man]
     cd "$workdir/openssl"
     ./config '-fPIC' && make -j${cpu} && sudo make install
     if [[ $? -ne ${success} ]]; then
        return ${failure}
     fi

     # /usr/local/include /usr/local/lib
     cd "$workdir/cjson"
     make -j${cpu} && sudo make install &&
     sudo cp libcjson.a /usr/local/lib &&
     sudo cp libcjson_utils.a /usr/local/lib
     if [[ $? -ne ${success} ]]; then
        return ${failure}
     fi

     sudo apt-get update &&
     sudo apt-get install xsltproc docbook-xsl -y
}

build() {
    cd ${workdir}/mosquitto

    make clean &&
    make WITH_STATIC_LIBRARIES=yes WITH_SHARED_LIBRARIES=no
    if [[ $? -ne 0 ]]; then
        log_error "make fail, plaease check and try again..."
        return ${failure}
    fi

    path="/tmp/mosquitto"
    sudo rm -rf "$path" && \
    sudo make DESTDIR="$path" WITH_STATIC_LIBRARIES=yes WITH_SHARED_LIBRARIES=no \
        install
    if [[ $? -ne 0 ]]; then
        log_error "make install fail, plaease check and try again..."
        return ${failure}
    fi

    log_info "build mqtt success"
}

copylib() {
    target=$1

    declare -A uniqueso=()
    path="/tmp/mosquitto"
    files=$(find "$path" -type f -executable -exec file -i '{}' \;|grep 'charset=binary'|cut -d ':' -f1)
    for file in ${files}; do
        # not found lib
        sofiles=$(ldd "$file"|sed -n -r '/not found$/ s|\s||gp'|grep -E -o '^lib[^=]+')
        for so in ${sofiles}; do
            uniqueso["$so"]=""
        done
        # /usr/local lib
        sofiles=$(ldd "$file"|sed -n -r '/\/usr\/local/ s|\s||gp'|grep -E -o '^lib[^=]+')
        for so in ${sofiles}; do
            uniqueso["$so"]=""
        done
    done

    path="/usr/local/lib"
    for key in ${!uniqueso[@]}; do
        file=$(find "$path" -name "$key")
        log_info "so: $key, file: $file"
        rsync --copy-links ${file} ${target}
    done
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    # control
    cat > debian/DEBIAN/control <<- EOF
Package: mosquitto
Version: ${version}
Description: MQTT server deb package
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

# load lib
ldconfig

# start mqtt server
systemctl daemon-reload && systemctl mosquitto.service start
if [[ $? -ne 0 ]]; then
    echo "service start mosquitto failed"
fi
EOF

    printf "%s" "${conf//'$installdir'/$installdir}" > debian/DEBIAN/postinst

    # prerm
    cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

systemctl mosquitto.service stop
EOF

    # postrm
    cat > debian/DEBIAN/postrm <<- EOF
#!/bin/bash

rm -rf /etc/systemd/system/mosquitto.service
rm -rf /etc/ld.so.conf.d/mosquitto.conf
rm -rf ${installdir}
ldconfig
EOF

    # chmod
    sudo chmod a+x debian/DEBIAN/postinst
    sudo chmod a+x debian/DEBIAN/postrm
    sudo chmod a+x debian/DEBIAN/prerm

    # copy files
    path="/tmp/mosquitto"
    mkdir -p debian/${installdir}/data
    sudo cp -r ${path}/usr/local/* debian/${installdir}
    sudo cp -r ${path}/etc/mosquitto debian/${installdir}/conf

    copylib debian/${installdir}/lib
    if [[ $? -ne ${success} ]]; then
        return ${failure}
    fi

    mkdir -p debian/etc/ld.so.conf.d
    cat > debian/etc/ld.so.conf.d/mosquitto.conf <<- EOF
${installdir}/lib
EOF

    # service
    cat > debian/${installdir}/conf/mosquitto.conf <<-EOF
allow_anonymous true

persistence true
persistence_location ${installdir}/data

listener 1883
socket_domain ipv4
EOF

    mkdir -p debian/etc/systemd/system
    read -r -d '' conf <<- 'EOF'
[Unit]
Description=MQTT server
After=network.target auditd.service

[Service]
Type=forking
ExecStart=$installdir/sbin/mosquitto -c $installdir/conf/mosquitto.conf
ExecStop=/bin/kill -s QUIT $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=900000


[Install]
WantedBy=multi-user.target

EOF

    printf "%s" "${conf//'$installdir'/$installdir}" > debian/etc/systemd/system/mosquitto.service


    # deb
    sudo dpkg-deb --build debian
    if [[ -z ${NAME} ]]; then
        NAME=mqtt_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
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

    package
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    clean
}


do_install
