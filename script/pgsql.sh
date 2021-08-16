#!/bin/bash

TOKEN=$1
VERSION=$2

declare -r version=${VERSION:=12.0}
declare -r workdir=$(pwd)
declare -r installdir=/opt/local/pgsql

declare -r  SUCCESS=0
declare -r  FAILURE=1

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

common_download() {
    name=$1
    url=$2
    cmd=$3

    if [[ -d "$name" ]]; then
        log_info "$name has exist !!"
        return ${SUCCESS} #1
    fi

    if [[ -f "$name.tar.gz" && -n $(file "$name.tar.gz" | grep -o 'POSIX tar archive') ]]; then
        rm -rf ${name} && mkdir ${name}
        tar -zvxf ${name}.tar.gz -C ${name} --strip-components 1
        if [[ $? -ne 0 ]]; then
            log_error "$name decopress failed"
            rm -rf ${name} && rm -rf ${name}.tar.gz
            return ${FAILURE}
        fi

        return ${SUCCESS} #2
    fi

    log_info "$name url: $url"
    log_info "begin to donwload $name ...."
    rm -rf ${name}.tar.gz
    command_exists "$cmd"
    if [[ $? -eq 0 && "$cmd" == "axel" ]]; then
        axel -n 10 --insecure --quite -o "$name.tar.gz" ${url}
    else
        curl -C - --insecure --silent ${url} -o "$name.tar.gz"
    fi

    if [[ $? -ne 0 ]]; then
        log_error "download file $name failed !!"
        rm -rf ${name}.tar.gz
        return ${FAILURE}
    fi

    log_info "success to download $name"
    rm -rf ${name} && mkdir ${name}
    tar -zxf ${name}.tar.gz -C ${name} --strip-components 1
    if [[ $? -ne 0 ]]; then
        log_error "$name decopress failed"
        rm -rf ${name} && rm -rf ${name}.tar.gz
        return ${FAILURE}
    fi

    return ${SUCCESS} #3
}

command_exists() {
	command -v "$@" > /dev/null 2>&1
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
        return ${SUCCESS}
    fi

    return ${FAILURE}
}

download_mysql() {
    url="https://ftp.postgresql.org/pub/source/v$version/postgresql-$version.tar.gz"
    common_download "pgsql" ${url} axel

    return $?
}

download_boost(){
    url="https://codeload.github.com/boostorg/boost/tar.gz/boost-1.59.0"
    #url="https://codeload.github.com/boostorg/boost/tar.gz/boost-1.61.0"
    common_download "boost" ${url} axel
    if [[ $? -eq ${SUCCESS} ]]; then
        mv "$workdir/boost" "$workdir/mysql/boost"
        return $?
    fi

    return $?
}

build() {
    # depend
    sudo apt-get update && \
    sudo apt-get install libpam-dev libsystemd-dev libssl-dev -y
    if [[ $? -ne 0 ]]; then
        log_error "install depency fail"
        return ${FAILURE}
    fi

    # remove old directory
    rm -rf ${installdir} && \
    mkdir -p ${installdir}/mysql && \
    mkdir -p ${installdir}/data && \
    mkdir -p ${installdir}/logs && \
    mkdir -p ${installdir}/tmp && \
    mkdir -p ${installdir}/conf

    # in workspace
    cd "$workdir/pgsql"

    # cmake
    ./configure \
    --prefix=${installdir} \
    --enable-debug \
    --enable-profiling \
    --with-pam \
    --with-openssl \
    --with-systemd
    if [[ $? -ne 0 ]]; then
        log_error "cmake fail, plaease check and try again.."
        return ${FAILURE}
    fi

    # make
    cpu=$(cat /proc/cpuinfo|grep 'processor'|wc -l)
    make -j ${cpu}
    if [[ $? -ne 0 ]]; then
        log_error "make fail, plaease check and try again..."
        return ${FAILURE}
    fi

    sudo make install
    if [[ $? -ne 0 ]]; then
        log_error "make install fail, plaease check and try again..."
        return ${FAILURE}
    fi

    # service script
    cp ${installdir}/mysql/support-files/mysql.server ${installdir}/conf/mysqld
    chmod a+x ${installdir}/conf/mysqld
}

service() {
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
ln -sf $installdir/conf/mysqld /etc/init.d/mysqld

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
    sudo mv debian.deb ${GITHUB_WORKSPACE}/mysql_${version}_amd64.deb
    sudo mv mysql.tar.gz ${GITHUB_WORKSPACE}/mysql_${version}_amd64.tgz
    echo "TAG=mysql_${version}" >> ${GITHUB_ENV}
    echo "DEB=mysql_${version}_amd64.deb" >> ${GITHUB_ENV}
    echo "TAR=mysql_${version}_amd64.tgz" >> ${GITHUB_ENV}
}

clean_file(){
    sudo rm -rf ${workdir}/mysql
    sudo rm -rf ${workdir}/mysql.tar.gz
    sudo rm -rf ${workdir}/boost
    sudo rm -rf ${workdir}/boost.tar.gz
}

do_install() {
    check
    if [[ $? -ne ${SUCCESS} ]]; then
        return
    fi

    download_mysql
    if [[ $? -ne ${SUCCESS} ]]; then
        exit $?
    fi

    download_boost
    if [[ $? -ne ${SUCCESS} ]]; then
        exit $?
    fi

    build
    if [[ $? -ne ${SUCCESS} ]]; then
        exit $?
    fi

    service
    if [[ $? -ne ${SUCCESS} ]]; then
        exit $?
    fi

    package
    if [[ $? -ne ${SUCCESS} ]]; then
        exit $?
    fi

    clean_file
}

do_install
