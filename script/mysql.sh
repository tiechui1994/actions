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
    url="https://cdn.mysql.com/archives/mysql-${version:0:3}/mysql-$version.tar.gz"
    download "mysql.tar.gz" ${url} axel 1
}

download_boost(){
    url="https://udomain.dl.sourceforge.net/project/boost/boost/1.61.0/boost_1_61_0.tar.gz"
    url="https://udomain.dl.sourceforge.net/project/boost/boost/1.59.0/boost_1_59_0.tar.gz"
    url="https://cdn.mysql.com/archives/mysql-${version:0:3}/mysql-boost-$version.tar.gz"
    download "boost.tar.gz" ${url} axel 1
    if [[ $? -eq ${success} ]]; then
        mv "$workdir/boost" "$workdir/mysql/boost"
        return ${success}
    fi

    return ${failure}
}

build() {
    # depend
    sudo apt-get update && \
    sudo apt-get install cmake build-essential libncurses5-dev bison libssl-dev pkg-config -y
    if [[ $? -ne 0 ]]; then
        log_error "install depency fail"
        return ${failure}
    fi

    # remove old directory
    rm -rf ${installdir}

    # in workspace
    cd "$workdir/mysql"

    # cmake
    # DWITH_EMBEDDED_SHARED_LIBRARY 是否构建共享的libmysqld 嵌入式服务器库
    # DWITH_EMBEDDED_SERVER 是否构建libmysqld嵌入式服务器库
    # DWITH_UNIT_TESTS 是否使用单元测试编译 MySQL
    cmake . \
    -DCMAKE_INSTALL_PREFIX=${installdir}/mysql \
    -DSYSCONFDIR=${installdir}/conf \
    -DDOWNLOAD_BOOST=1 \
    -DWITH_BOOST=${workdir}/mysql/boost \
    -DDEFAULT_CHARSET=utf8 \
    -DDEFAULT_COLLATION=utf8_general_ci \
    -DWITH_INNOBASE_STORAGE_ENGINE=1 \
    -DWITH_PARTITION_STORAGE_ENGINE=1 \
    -DWITH_FEDERATED_STORAGE_ENGINE=1 \
    -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
    -DWITH_MYISAM_STORAGE_ENGINE=1 \
    -DENABLED_LOCAL_INFILE=1 \
    -DWITH_EMBEDDED_SHARED_LIBRARY=0 \
    -DWITH_EMBEDDED_SERVER=0 \
    -DWITH_DEBUG=0 \
    -DENABLE_DTRACE=0 \
    -DWITH_UNIT_TESTS=0
    if [[ $? -ne 0 ]]; then
        log_error "cmake fail, plaease check and try again.."
        return ${failure}
    fi

    # make
    cpu=$(cat /proc/cpuinfo|grep 'processor'|wc -l)
    make -j ${cpu} --quiet
    if [[ $? -ne 0 ]]; then
        log_error "make fail, plaease check and try again..."
        return ${failure}
    fi

    sudo make install
    if [[ $? -ne 0 ]]; then
        log_error "make install fail, plaease check and try again..."
        return ${failure}
    fi

    log_info "build mysql success"
    log_info "mysqld info:$(ldd ${installdir}/mysql/bin/mysqld)"
    log_info "mysql info:$(ldd ${installdir}/mysql/bin/mysql)"
    log_info "mysqldump ingo: $(ldd ${installdir}/mysql/bin/mysqldump)"
}

config() {
    mkdir -p ${installdir}/data && \
    mkdir -p ${installdir}/logs && \
    mkdir -p ${installdir}/tmp && \
    mkdir -p ${installdir}/conf

    read -r -d '' conf <<- 'EOF'
[client]
    port=3306

[mysqld]
    port=3306
    user=mysql
    pid-file=@installdir/logs/mysql.pid
    basedir=@installdir/mysql  # 安装目录
    datadir=@installdir/data   # 数据目录
    tmpdir=@installdir/tmp     # 临时目录

    default_storage_engine=InnoDB
    innodb_file_per_table=ON
    innodb_flush_log_at_trx_commit=1

    innodb_lock_wait_timeout=60
    wait_timeout=28800
    interactive_timeout=28800

    log_error=@installdir/logs/mysql.err

    sync_binlog=1
    log_bin=@installdir/logs/binlog

    general_log=1
    general_log_file=@installdir/logs/general_log

    slow_query_log=ON
    long_query_time=5
    slow_query_log_file=@installdir/logs/query_log
    log_queries_not_using_indexes=ON

    bulk_insert_buffer_size=64M
    binlog_rows_query_log_events=ON

    sort_buffer_size=64M #默认是128K
    binlog_format=row # 默认是mixed
    join_buffer_size=128M # 默认是256K
    max_allowed_packet=512M # 默认是16M

EOF

    # create config file my.cnf
    printf "%s" "${conf//'@installdir'/$installdir}" > ${installdir}/conf/my.cnf
}

service() {
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

### BEGIN INIT INFO
# Provides: mysql
# Required-Start: $local_fs $network $remote_fs
# Should-Start: ypbind nscd ldap ntpd xntpd
# Required-Stop: $local_fs $network $remote_fs
# Default-Start:  2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: start and stop MySQL
# Description: MySQL is a very fast and reliable SQL database engine.
### END INIT INFO

basedir=
datadir=

# Default value, in seconds, afterwhich the script should timeout waiting for server start.
# Value here is overriden by value in my.cnf.
# 0 means don't wait at all
# Negative numbers mean to wait indefinitely
service_startup_timeout=900

# Lock directory for RedHat / SuSE.
lockdir='/var/log/subsys'
lock_file_path="$lockdir/mysql"

# The following variables are only set for letting mysql.server find things.

# Set some defaults
mysqld_pid_file_path=
if test -z "$basedir"; then
  basedir="@BASEDIR"
  bindir="@BINDIR"
  sbindir="@SBINDIR"
  libexecdir="@LIBEXECDIR"
  if test -z "$datadir"; then
    datadir="@DATADIR"
  fi
else
  bindir="$basedir/bin"
  sbindir="$basedir/sbin"
  libexecdir="$basedir/libexec"
  if test -z "$datadir"; then
    datadir="$basedir/data"
  fi
fi

# datadir_set is used to determine if datadir was set (and so should be
# *not* set inside of the --basedir= handler.)
datadir_set=

#
# Use LSB init script functions for printing messages, if possible
#
lsb_functions="/lib/lsb/init-functions"
if test -f ${lsb_functions} ; then
  . ${lsb_functions}
else
  log_success_msg()
  {
    echo " SUCCESS! $@"
  }
  log_failure_msg()
  {
    echo " ERROR! $@"
  }
fi

export PATH="/sbin:/usr/sbin:/bin:/usr/bin:$basedir/bin"

mode=$1    # start or stop

[[ $# -ge 1 ]] && shift

other_args="$*"   # uncommon, but needed when called from an RPM upgrade action
                  # Expected: "--skip-networking --skip-grant-tables"
                  # They are not checked here, intentionally, as it is the resposibility
                  # of the "spec" file author to give correct arguments only.

parse_server_arguments() {
  for arg do
    case "$arg" in
      --basedir=*)
        basedir=$(echo "$arg" | sed -e 's/^[^=]*=//')
        bindir="$basedir/bin"
        sbindir="$basedir/sbin"
        libexecdir="$basedir/libexec"
        if test -z "$datadir_set"; then
          datadir="$basedir/data"
        fi
        ;;
      --datadir=*)
        datadir=$(echo "$arg" | sed -e 's/^[^=]*=//')
                datadir_set=1
            ;;
      --pid-file=*)
        mysqld_pid_file_path=$(echo "$arg" | sed -e 's/^[^=]*=//')
        ;;
      --service-startup-timeout=*)
        service_startup_timeout=$(echo "$arg" | sed -e 's/^[^=]*=//')
        ;;
    esac
  done
}

wait_for_pid () {
  verb="$1"           # created | removed
  pid="$2"            # process ID of the program operating on the pid-file
  pid_file_path="$3"  # path to the PID file.

  i=0
  avoid_race_condition="by checking again"

  while test ${i} -ne ${service_startup_timeout} ; do

    case "$verb" in
      'created')
        # wait for a PID-file to pop into existence.
        test -s "$pid_file_path" && i='' && break
        ;;
      'removed')
        # wait for this PID-file to disappear
        test ! -s "$pid_file_path" && i='' && break
        ;;
      *)
        echo "wait_for_pid () usage: wait_for_pid created|removed pid pid_file_path"
        exit 1
        ;;
    esac

    # if server isn't running, then pid-file will never be updated
    if test -n "$pid"; then
      if kill -0 "$pid" 2>/dev/null; then
        :  # the server still runs
      else
        # The server may have exited between the last pid-file check and now.
        if test -n "$avoid_race_condition"; then
          avoid_race_condition=""
          continue  # Check again.
        fi

        # there's nothing that will affect the file.
        log_failure_msg "The server quit without updating PID file ($pid_file_path)."
        return 1  # not waiting any more.
      fi
    fi

    i=$(expr ${i} + 1)
    sleep 1

  done

  if test -z "$i" ; then
    log_success_msg
    return 0
  else
    log_failure_msg
    return 1
  fi
}

# Get arguments from the my.cnf file, the only group, which is read from now on is [mysqld]
if test -x "$bindir/my_print_defaults"; then
  print_defaults="$bindir/my_print_defaults"
else
  # Try to find basedir in /etc/my.cnf
  conf=/etc/my.cnf
  print_defaults=
  if test -r ${conf}; then
    subpat='^[^=]*basedir[^=]*=\(.*\)$'
    dirs=$(sed -e "/$subpat/!d" -e 's//\1/' ${conf})
    for d in ${dirs}; do
      d=$(echo ${d} | sed -e 's/[ 	]//g')
      if test -x "$d/bin/my_print_defaults"; then
        print_defaults="$d/bin/my_print_defaults"
        break
      fi
    done
  fi

  # Hope it's in the PATH ... but I doubt it
  test -z "$print_defaults" && print_defaults="my_print_defaults"
fi

#
# Read defaults file from 'basedir'.   If there is no defaults file there
# check if it's in the old (depricated) place (datadir) and read it from there
#
extra_args=""
if test -r "$basedir/my.cnf"; then
  extra_args="-e $basedir/my.cnf"
fi

parse_server_arguments $("$print_defaults" "$extra_args" mysqld server mysql_server mysql.server)

#
# Set pid file if not given
#
if test -z "$mysqld_pid_file_path"; then
  mysqld_pid_file_path=${datadir}/$(hostname).pid
else
  case "$mysqld_pid_file_path" in
    /* )
        ;;
    * )
        mysqld_pid_file_path="$datadir/$mysqld_pid_file_path"
        ;;
  esac
fi

case "$mode" in
  'start')
    # Start daemon
    # Safeguard (relative paths, core dumps..)
    cd ${basedir}

    echo "Starting MySQL"
    if test -x ${bindir}/mysqld_safe; then
      # Give extra arguments to mysqld with the my.cnf file. This script
      # may be overwritten at next upgrade.
      ${bindir}/mysqld_safe --datadir="$datadir" --pid-file="$mysqld_pid_file_path" ${other_args} >/dev/null &
      wait_for_pid created "$!" "$mysqld_pid_file_path"; return_value=$?

      # Make lock for RedHat / SuSE
      if test -w "$lockdir"; then
        touch "$lock_file_path"
      fi

      exit ${return_value}
    else
      log_failure_msg "Couldn't find MySQL server ($bindir/mysqld_safe)"
    fi
    ;;

  'stop')
    # Stop daemon. We use a signal here to avoid having to know the
    # root password.

    if test -s "$mysqld_pid_file_path"; then
      # signal mysqld_safe that it needs to stop
      touch "$mysqld_pid_file_path.shutdown"

      mysqld_pid=$(cat "$mysqld_pid_file_path")

      if (kill -0 ${mysqld_pid} 2>/dev/null); then
        echo "Shutting down MySQL"
        kill ${mysqld_pid}
        # mysqld should remove the pid file when it exits, so wait for it.
        wait_for_pid removed "$mysqld_pid" "$mysqld_pid_file_path"
        return_value=$?
      else
        log_failure_msg "MySQL server process #$mysqld_pid is not running!"
        rm "$mysqld_pid_file_path"
      fi

      # Delete lock for RedHat / SuSE
      if test -f "$lock_file_path"; then
        rm -f "$lock_file_path"
      fi
      exit ${return_value}
    else
      log_failure_msg "MySQL server PID file could not be found!"
    fi
    ;;

  'restart')
    # Stop the service and regardless of whether it was
    # running or not, start it again.
    if $0 stop  ${mysqld_pid}; then
      $0 start ${mysqld_pid}
    else
      log_failure_msg "Failed to stop running server, so refusing to try to start."
      exit 1
    fi
    ;;

  'reload'|'force-reload')
    if test -s "$mysqld_pid_file_path" ; then
      read mysqld_pid <  "$mysqld_pid_file_path"
      kill -HUP ${mysqld_pid} && log_success_msg "Reloading service MySQL"
      touch "$mysqld_pid_file_path"
    else
      log_failure_msg "MySQL PID file could not be found!"
      exit 1
    fi
    ;;
  'status')
    # First, check to see if pid file exists
    if test -s "$mysqld_pid_file_path" ; then
      read mysqld_pid < "$mysqld_pid_file_path"
      if kill -0 ${mysqld_pid} 2>/dev/null ; then
        log_success_msg "MySQL running ($mysqld_pid)"
        exit 0
      else
        log_failure_msg "MySQL is not running, but PID file exists"
        exit 1
      fi
    else
      # Try to find appropriate mysqld process
      mysqld_pid=$(pidof ${libexecdir}/mysqld)

      # test if multiple pids exist
      pid_count=$(echo ${mysqld_pid} | wc -w)
      if test ${pid_count} -gt 1 ; then
        log_failure_msg "Multiple MySQL running but PID file could not be found ($mysqld_pid)"
        exit 5
      elif test -z ${mysqld_pid} ; then
        if test -f "$lock_file_path" ; then
          log_failure_msg "MySQL is not running, but lock file ($lock_file_path) exists"
          exit 2
        fi
        log_failure_msg "MySQL is not running"
        exit 3
      else
        log_failure_msg "MySQL is running but PID file could not be found"
        exit 4
      fi
    fi
    ;;
    *)
      # usage
      basename=$(basename "$0")
      echo "Usage: $basename  {start|stop|restart|reload|force-reload|status}  [ MySQL server options ]"
      exit 1
    ;;
esac

exit 0
EOF
    conf=${conf//'@BASEDIR'/"$installdir/mysql"}
    conf=${conf//'@BINDIR'/"$installdir/mysql/bin"}
    conf=${conf//'@SBINDIR'/"$installdir/mysql/bin"}
    conf=${conf//'@LIBEXECDIR'/"$installdir/mysql/bin"}
    conf=${conf//'@DATADIR'/"$installdir/data"}

    # service script
    mkdir -p ${installdir}/init.d
    printf "%s" "$conf" > ${installdir}/init.d/mysqld
    chmod a+x ${installdir}/init.d/mysqld
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

case "$1" in
    (configure)
        # user and group
        if [[ -z "$(cat /etc/group | grep -E '^mysql:')" ]]; then
            groupadd -r mysql
        fi
        if [[ -z "$(cat /etc/passwd | grep -E '^mysql:')" ]]; then
            useradd -r mysql -g mysql
        fi

        # dir owner and privileges
        chown -R mysql:mysql @installdir

        # link file
        ln -sf @installdir/mysql/bin/mysql /usr/local/bin/mysql
        ln -sf @installdir/mysql/bin/mysqldump /usr/local/bin/mysqldump
        ln -sf @installdir/mysql/bin/mysqlbinlog /usr/local/bin/mysqlbinlog

        ln -sf @installdir/init.d/mysqld /etc/init.d/mysqld

        # clear logs and data
        rm -rf @installdir/logs/* && rm -rf @installdir/data/*

        # init database
        @installdir/mysql/bin/mysqld \
        --initialize \
        --user=mysql \
        --basedir=@installdir/mysql \
        --datadir=@installdir/data
        if [[ $? -ne 0 ]]; then
            echo "mysqld initialize failed"
            exit
        fi

        # check logs/mysql.err.
        error=$(grep -E -i -o '\[error\].*' "@installdir/logs/mysql.err")
        if [[ -n ${error} ]]; then
            echo "mysql database init failed"
            echo "error message:"
            echo "$error"
            echo "the detail message in file @installdir/logs/mysql.err"
            exit
        fi

        # start mysqld service
        update-rc.d mysqld defaults && \
        service mysqld start
        if [[ $? -ne 0 ]]; then
            echo "mysqld service start failed, please check and trg again..."
            exit
        fi

        # check password
        password="$(grep 'temporary password' "@installdir/logs/mysql.err"|cut -d ' ' -f11)"
        echo "current password is: $password"
        echo "please use follow command and sql login and update your password:"
        echo "mysql -u root --password='$password'"
        echo "SET PASSWORD = PASSWORD('your new password');"
        echo "ALTER user 'root'@'localhost' PASSWORD EXPIRE NEVER;"
        echo "FLUSH PRIVILEGES;"
        echo "mysql install successfully"
    ;;
    (*)
        echo "postinst called with unknown argument \`$1'" >&2
        exit 0
    ;;
esac

EOF

    printf "%s" "${conf//'@installdir'/$installdir}" > debian/DEBIAN/postinst

    cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

case "$1" in
    (remove)
        service mysqld status > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            service mysqld stop
        fi
    ;;
esac

EOF


    # postrm
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

case "$1" in
    (remove)
        if [[ -f /etc/init.d/mysqld ]]; then
            update-rc.d mysqld remove
            rm -rf /etc/init.d/mysqld
        fi

        if [[ -d @installdir ]]; then
            rm -rf /etc/init.d/mysqld
            rm -rf @installdir
        fi

        rm -rf /usr/local/bin/mysql
        rm -rf /usr/local/bin/mysqldump
        rm -rf /usr/local/bin/mysqlbinlog

        if [[ -n "$(cat /etc/group | grep -E '^mysql:')" ]]; then
            groupdel -f mysql
        fi
        if [[ -n "$(cat /etc/passwd | grep -E '^mysql:')" ]]; then
            userdel -f mysql
        fi
    ;;
esac

EOF
    printf "%s" "${conf//'@installdir'/$installdir}" > debian/DEBIAN/postrm

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

    config && service
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
