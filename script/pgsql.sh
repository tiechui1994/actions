#!/bin/bash

TOKEN=$1
VERSION=$2

declare -r version=${VERSION:=12.0}
declare -r workdir=$(pwd)
declare -r installdir=/opt/local/pgsql

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

check() {
    sudo apt-get update && \
    sudo apt-get install jq -y
    url=https://api.github.com/repos/tiechui1994/jobs/releases/tags/pgsql_${version}
    result=$(curl -H "Accept: application/vnd.github.v3+json" \
                  -H "Authorization: token ${TOKEN}" ${url})
    log_info "result: $(echo ${result} | jq .)"
    message=$(echo ${result} | jq .message)
    log_info "message: ${message}"
    if [[ ${message} = '"Not Found"' ]]; then
        return ${success}
    fi

    return ${failure}
}

download_pgsql() {
    url="https://ftp.postgresql.org/pub/source/v$version/postgresql-$version.tar.gz"
    download "pgsql.tar.gz" ${url} curl 1

    return $?
}

download_openssl() {
    prefix="https://ftp.openssl.org/source/old"
    openssl="$(openssl version |cut -d " " -f2)"
    if [[ ${openssl} =~ ^1\.[0-1]\.[0-2]$ ]]; then
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl} ${openssl})
    else
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl:0:${#openssl}-1} ${openssl})
    fi
    download "openssl.tar.gz" "$url" curl 1
    return $?
}

build_denpend() {
     cd "$workdir/openssl"
     ./config --prefix=/tmp/openssl '-fPIC' && make && make install
}

build() {
    # depend
    sudo apt-get update && \
    sudo apt-get install libreadline-dev libpam-dev libsystemd-dev -y
    if [[ $? -ne 0 ]]; then
        log_error "install depency fail"
        return ${failure}
    fi

    # remove old directory
    rm -rf ${installdir}

    # in workspace
    cd "$workdir/pgsql"

    # cmake
    ./configure \
    --prefix=${installdir} \
    --enable-debug \
    --with-pam \
    --with-openssl \
    --with-systemd \
    CFLAGS="-I/tmp/openssl/include" \
    LDFLAGS="-Bstatic -lssl -lpam -lcrypto -L/tmp/openssl/lib"
    if [[ $? -ne 0 ]]; then
        log_error "configure fail, plaease check and try again.."
        return ${failure}
    fi

    # make
    cpu=$(cat /proc/cpuinfo|grep 'processor'|wc -l)
    make -j ${cpu}
    if [[ $? -ne 0 ]]; then
        log_error "make fail, plaease check and try again..."
        return ${failure}
    fi

    sudo make install
    if [[ $? -ne 0 ]]; then
        log_error "make install fail, plaease check and try again..."
        return ${failure}
    fi

    # service script
    for x in $(ls /opt/local/pgsql/bin);
    do
        log_info "/opt/local/pgsql/bin/$x"
        ldd "/opt/local/pgsql/bin/$x"
        log_info
    done
}

service() {
    mkdir -p ${installdir}/conf

    read -r -d '' conf <<- 'EOF'
[Unit]
Description=PostgreSQL database server

[Service]
Type=notify
User=postgres
ExecStart=$dir/bin/postgres -D $dir/data
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF
    regex='$dir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > ${installdir}/conf/pgsql.service
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    # control
    cat > debian/DEBIAN/control <<- EOF
Package: PgSQL
Version: ${version}
Description: PgSQL server deb package
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

if [[ -d ${installdir} ]]; then
    rm -rf ${installdir}
fi
EOF

    regex='$installdir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > debian/DEBIAN/preinst

    # postinst
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

# user and group
if [[ -z "$(cat /etc/group | grep -E '^postgres:')" ]]; then
    groupadd -r postgres
fi
if [[ -z "$(cat /etc/passwd | grep -E '^postgres:')" ]]; then
    useradd -r postgres -g postgres
fi

# data
rm -rf $installdir/data && mkdir -p $installdir/data
chmod -R 775 $installdir
chown -R postgres:postgres $installdir

# init db
sudo -u postgres $installdir/bin/initdb --pgdata=$installdir/data \
     --encoding=UTF8 \
     --locale=en_US.UTF-8 \
     --username=postgres \
     --pwprompt

# start pgsql service
cp $installdir/conf/pgsql.service /etc/systemd/system
systemctl daemon-reload && systemctl start pgsql.service
if [[ $? -ne 0 ]]; then
    echo "pgsql service start failed, please check and trg again..."
    exit
fi
EOF

    regex='$installdir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > debian/DEBIAN/postinst

    cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

systemctl stop pgsql.service
EOF


    # postrm
    cat > debian/DEBIAN/postrm <<- EOF
#!/bin/bash

if [[ -d ${installdir} ]]; then
    rm -rf ${installdir}
fi
EOF

    # chmod
    sudo chmod a+x debian/DEBIAN/preinst
    sudo chmod a+x debian/DEBIAN/postinst
    sudo chmod a+x debian/DEBIAN/postrm
    sudo chmod a+x debian/DEBIAN/prerm

    # dir
    mkdir -p debian/${installdir}
    sudo mv ${installdir}/* debian/${installdir}


    # deb
    sudo dpkg-deb --build debian
    sudo mv debian.deb ${GITHUB_WORKSPACE}/pgsql_${version}_amd64.deb
    sudo mv pgsql.tar.gz ${GITHUB_WORKSPACE}/pgsql_${version}_amd64.tgz
    echo "TAG=pgsql_${version}" >> ${GITHUB_ENV}
    echo "DEB=pgsql_${version}_amd64.deb" >> ${GITHUB_ENV}
    echo "TAR=pgsql_${version}_amd64.tgz" >> ${GITHUB_ENV}
}

clean_file(){
    sudo rm -rf ${workdir}/pgsql
    sudo rm -rf ${workdir}/pgsql.tar.gz
}

do_install() {
    check
    if [[ $? -ne ${success} ]]; then
        return
    fi

    download_pgsql
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    download_openssl
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

    service
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    package
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    clean_file
}

do_install
