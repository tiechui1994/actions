#!/bin/bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=5.7.34}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/mysql}

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

download_mysql() {
    # tencent, mirrorservice, mysql(https://downloads.mysql.com/archives/community)
    url="https://mirrors.cloud.tencent.com/mysql/downloads/MySQL-5.7/mysql-$version.tar.gz"
    url="https://www.mirrorservice.org/sites/ftp.mysql.com/Downloads/MySQL-5.7/mysql-$version.tar.gz"
    url="https://cdn.mysql.com/archives/mysql-5.7/mysql-$version.tar.gz"
    download "mysql.tar.gz" ${url} axel 1

    return $?
}

download_boost(){
    url="https://udomain.dl.sourceforge.net/project/boost/boost/1.61.0/boost_1_61_0.tar.gz"
    url="https://udomain.dl.sourceforge.net/project/boost/boost/1.59.0/boost_1_59_0.tar.gz"
    download "boost.tar.gz" ${url} axel 1
    if [[ $? -eq ${success} ]]; then
        mv "$workdir/boost" "$workdir/mysql/boost"
        return $?
    fi

    return $?
}

build() {
    # depend
    sudo apt-get update && \
    sudo apt-get install cmake build-essential libncurses5-dev bison libssl-dev -y
    if [[ $? -ne 0 ]]; then
        log_error "install depency fail"
        return ${failure}
    fi

    # remove old directory
    rm -rf ${installdir}

    # in workspace
    cd "$workdir/mysql"

    # cmake
    cmake . \
    -DCMAKE_INSTALL_PREFIX=${installdir}/mysql \
    -DMYSQL_DATADIR=${installdir}/data \
    -DSYSCONFDIR=${installdir}/conf \
    -DDOWNLOAD_BOOST=1 \
    -DWITH_BOOST=${workdir}/mysql/boost \
    -DWITH_INNOBASE_STORAGE_ENGINE=1 \
    -DWITH_PARTITION_STORAGE_ENGINE=1 \
    -DWITH_FEDERATED_STORAGE_ENGINE=1 \
    -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
    -DWITH_MYISAM_STORAGE_ENGINE=1 \
    -DENABLED_LOCAL_INFILE=1 \
    -DENABLE_DTRACE=0 \
    -DDEFAULT_CHARSET=utf8 \
    -DDEFAULT_COLLATION=utf8_general_ci
    if [[ $? -ne 0 ]]; then
        log_error "cmake fail, plaease check and try again.."
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
    mkdir -p ${installdir}/init.d
    cp ${installdir}/mysql/support-files/mysql.server ${installdir}/init.d/mysqld
    chmod a+x ${installdir}/init.d/mysqld


    log_info "build mysql success"
    log_info "mysqld info:$(ldd ${installdir}/mysql/bin/mysqld)"
    log_info "mysql info:$(ldd ${installdir}/mysql/bin/mysql)"
    log_info "mysqldump ingo: $(ldd ${installdir}/mysql/bin/mysqldump)"
}

service() {
    mkdir -p ${installdir}/data && \
    mkdir -p ${installdir}/logs && \
    mkdir -p ${installdir}/tmp && \
    mkdir -p ${installdir}/conf

    read -r -d '' conf <<- 'EOF'
[client]
    port=3306
    socket=$dir/data/mysql.sock
    default-character-set=utf8

[mysqld]
    port=3306
    user=mysql
    socket=$dir/data/mysql.sock
    pid-file=$dir/data/mysql.pid
    basedir=$dir/mysql  # 安装目录
    datadir=$dir/data   # 数据目录
    tmpdir=$dir/tmp     # 临时目录
    character-set-server=utf8
    log_error=$dir/logs/mysql.err

    server-id=2
    log_bin=$dir/logs/binlog

    general_log_file=$dir/logs/general_log
    general_log=1

    slow_query_log=ON
    long_query_time=2
    slow_query_log_file=$dir/logs/query_log
    log_queries_not_using_indexes=ON

    bulk_insert_buffer_size=64M
    binlog_rows_query_log_events=ON

    sort_buffer_size=64M #默认是128K
    binlog_format=row #默认是mixed
    join_buffer_size=128M #默认是256K
    max_allowed_packet=512M #默认是16M
EOF

    # create config file my.cnf
    regex='$dir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > ${installdir}/conf/my.cnf
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    # control
cat > debian/DEBIAN/control <<- EOF
Package: MySQL
Version: ${version}
Description: MySQL server deb package
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

# user and group
if [[ -z "$(cat /etc/group | grep -E '^mysql:')" ]]; then
    groupadd -r mysql
fi
if [[ -z "$(cat /etc/passwd | grep -E '^mysql:')" ]]; then
    useradd -r mysql -g mysql
fi

# dir owner and privileges
chmod -R 755 $installdir
chown -R mysql:mysql $installdir

# link file
mkdir -p /usr/local/share/man/man1
mkdir -p /usr/local/share/man/man8
ln -sf $installdir/mysql/mysql/man/man1/* /usr/local/share/man/man1
ln -sf $installdir/mysql/mysql/man/man8/* /usr/local/share/man/man8
ln -sf $installdir/init.d/mysqld /etc/init.d/mysqld

# clear logs and data
rm -rf $installdir/logs/* && rm -rf $installdir/data/*

# init database
$installdir/mysql/bin/mysqld \
--initialize \
--user=mysql \
--basedir=$installdir/mysql \
--datadir=$installdir/data
if [[ $? -ne 0 ]]; then
    echo "mysqld initialize failed"
    exit
fi

# check logs/mysql.err.
error=$(grep -E -i -o '\[error\].*' "$installdir/logs/mysql.err")
if [[ -n ${error} ]]; then
    echo "mysql database init failed"
    echo "error message:"
    echo "$error"
    echo "the detail message in file $installdir/logs/mysql.err"
    exit
fi

# start mysqld service
update-rc.d mysqld defaults && \
systemctl daemon-reload && service mysqld start
if [[ $? -ne 0 ]]; then
    echo "mysqld service start failed, please check and trg again..."
    exit
fi

# check password
password="$(grep 'temporary password' "$installdir/logs/mysql.err"|cut -d ' ' -f11)"
echo "current password is: $password"
echo "please use follow command and sql login and update your password:"
echo "mysql -u root --password='$password'"
echo "SET PASSWORD = PASSWORD('your new password');"
echo "ALTER user 'root'@'localhost' PASSWORD EXPIRE NEVER;"
echo "FLUSH PRIVILEGES;"
echo "mysql install successfully"
EOF

    regex='$installdir'
    repl="$installdir"
    printf "%s" "${conf//$regex/$repl}" > debian/DEBIAN/postinst

    cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

service mysqld stop
EOF


    # postrm
    cat > debian/DEBIAN/postrm <<- EOF
#!/bin/bash

update-rc.d mysqld remove
rm -rf /etc/init.d/mysqld
rm -rf ${installdir}

groupdel -f mysql
userdel -f -r mysql
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
        NAME=mysql_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
}

clean(){
    sudo rm -rf ${workdir}/mysql
    sudo rm -rf ${workdir}/mysql.tar.gz
    sudo rm -rf ${workdir}/boost
    sudo rm -rf ${workdir}/boost.tar.gz
}

do_install() {
    if [[ ${INIT} ]]; then
        init
     fi

    download_mysql
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    download_boost
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
