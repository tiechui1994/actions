#!/bin/bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=4.2.14}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/mongodb}

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

                log_info "success to decompress $name"
                return ${success} # success
            fi

            log_error "download file $name is invalid"
            rm -rf ${filename} && rm -rf ${name}
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
        rm -rf ${filename} && rm -rf ${name}
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
        rm -rf ${filename} && rm -rf ${name}
        return ${failure}
    fi

    return ${success} # success
}

init() {
    apt-get update
    export DEBIAN_FRONTEND=noninteractive
    export TZ=Asia/Shanghai
    apt-get install -y build-essential gcc sudo curl make file tar tzdata
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

download_mongodb() {
    cd "$workdir"
    if [[ "${version}" > "4.2" ]]; then
        source /etc/lsb-release
        os=$(echo "${DISTRIB_ID}${DISTRIB_RELEASE//'.'/''}"|awk '{print tolower($0)}')
        url="https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${os}-${version}.tgz"
        download "mongodb.tar.gz" ${url} curl 1
        if [[ $? -ne ${success} && ${os} = "ubuntu2004" ]]; then
            url="https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu1804-${version}.tgz"
            download "mongodb.tar.gz" ${url} curl 1
        fi
    else
        url="https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${version}.tgz"
        download "mongodb.tar.gz" ${url} curl 1
    fi
    if [[ $? -ne ${success} ]]; then
        return ${failure}
    fi

    mkdir -p ${installdir}
    mv ${workdir}/mongodb/* ${installdir}

    mkdir -p ${installdir}/lib
    cp -Lr "$workdir/x64/lib/libcrypto.so.1.1" "$installdir/lib"
    cp -Lr "$workdir/x64/lib/libssl.so.1.1" "$installdir/lib"

    log_info "build mongodb success"
    log_info "mongo info: $(ldd ${installdir}/bin/mongo)"
    log_info "mongod info: $(ldd ${installdir}/bin/mongod)"
    log_info "mysqldump ingo: $(ldd ${installdir}/bin/mongodump)"
}

service() {
    mkdir -p ${installdir}/data && \
    mkdir -p ${installdir}/logs && \
    mkdir -p ${installdir}/conf && \
    mkdir -p ${installdir}/init.d

    read -r -d '' conf <<- 'EOF'
# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

# Where and how to store data.
storage:
  dbPath: $installdir/data
  directoryPerDB: true
  journal:
    enabled: true
    #engine:
    #mmapv1:
    #wiredTiger:

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: $installdir/logs/mongodb.log

# network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1
  unixDomainSocket:
    enabled: true

# how the process runs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
  fork: true
  pidFilePath: $installdir/logs/mongodb.pid

#security:

#operationProfiling:

#replication:

#sharding:

## Enterprise-Only Options:

#auditLog:

#snmp:
EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > ${installdir}/conf/mongodb.cnf


    read -r -d '' conf <<-'EOF'
#!/bin/bash

### BEGIN INIT INFO
# Provides:          mongodb
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Should-Start:      $named
# Default-Start:     2
# Default-Stop:      0 1  3 4 5 6
# Description:       MongoDB scripts
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON=$installdir/bin/mongod
DESC=database

# Default defaults.  Can be overridden by the /etc/default/$NAME
NAME=mongodb
CONF=$installdir/conf/mongodb.conf
RUNDIR=$installdir/data
PIDFILE=$installdir/logs/${NAME}.pid
ENABLE_MONGODB=yes

# Handle NUMA access to CPUs (SERVER-3574)
# This verifies the existence of numactl as well as testing that the command works
NUMACTL_ARGS="--interleave=all"
if which numactl >/dev/null 2>/dev/null && numactl ${NUMACTL_ARGS} ls / >/dev/null 2>/dev/null
then
    NUMACTL="`which numactl` -- $NUMACTL_ARGS"
    DAEMON_OPTS=${DAEMON_OPTS:-"--config $CONF"}
else
    NUMACTL=""
    DAEMON_OPTS="-- "${DAEMON_OPTS:-"--config $CONF"}
fi

if test ! -x ${DAEMON}; then
    echo "Could not find $DAEMON"
    exit 0
fi

if test "x$ENABLE_MONGODB" != "xyes"; then
    exit 0
fi

. /lib/lsb/init-functions

STARTTIME=1
DIETIME=10      # Time to wait for the server to die, in seconds
                # If this value is set too low you might not
                # let some servers to die gracefully and
                # 'restart' will not work

DAEMONUSER=${DAEMONUSER:-mongodb}
DAEMON_OPTS=${DAEMON_OPTS:-"--unixSocketPrefix=$RUNDIR --config $CONF"}

set -e

running_pid() {
    # Check if a given process pid's cmdline matches a given name
    pid=$1
    name=$2
    [ -z "$pid" ] && return 1
    [ ! -d /proc/${pid} ] && return 1
    cmd=`cat /proc/${pid}/cmdline | tr "\000" "\n"|head -n 1 |cut -d : -f 1`
    # Is this the expected server
    [ "$cmd" != "$name" ] &&  return 1
    return 0
}

running() {
    # Check if the process is running looking at /proc
    # (works for all users)
    # No pidfile, probably no daemon present
    [ ! -f "$PIDFILE" ] && return 1
    pid=`cat ${PIDFILE}`
    logger "parent pid: $pid"
    running_pid ${pid} ${DAEMON} || return 1
    return 0
}

start_server() {
    test -e "$RUNDIR" || install -m 755 -o mongodb -g mongodb -d "$RUNDIR"
    logger "test status: $?"
    # Start the process using the wrapper
    logger "cmd: ${NUMACTL} ${DAEMON}, args: ${DAEMON_OPTS}"
    start-stop-daemon --background --start --pidfile ${PIDFILE} --make-pidfile \
        --exec ${NUMACTL} ${DAEMON} ${DAEMON_OPTS}
    errcode=$?
    logger "start-stop-daemon status: $errcode"
	return ${errcode}
}

stop_server() {
    # Stop the process using the wrapper
    start-stop-daemon --stop --pidfile ${PIDFILE} \
        --retry 300 \
        --user ${DAEMONUSER} \
        --exec ${DAEMON}
    errcode=$?
	return ${errcode}
}

force_stop() {
    # Force the process to die killing it manually
	[ ! -e "$PIDFILE" ] && return
	if running ; then
		kill -15 ${pid}
	    # Is it really dead?
		sleep "$DIETIME"s
		if running ; then
			kill -9 ${pid}
			sleep "$DIETIME"s
			if running ; then
				echo "Cannot kill $NAME (pid=$pid)!"
				exit 1
			fi
		fi
	fi
	rm -f ${PIDFILE}
}

case "$1" in
  start)
	    log_daemon_msg "Starting $DESC" "$NAME"
        # Check if it's running first
        if running ;  then
            logger "apparently already running"
            log_end_msg 0
            exit 0
        fi
        if start_server ; then
            logger "start_server $DESC" "$NAME"
            # NOTE: Some servers might die some time after they start,
            # this code will detect this issue if STARTTIME is set
            # to a reasonable value
            logger "sleep: $STARTTIME"
            [ -n "$STARTTIME" ] && sleep ${STARTTIME} # Wait some time
            if  running ;  then
                # It's ok, the server started and is running
                log_end_msg 0
            else
                # It is not running after we did start
                log_end_msg 1
            fi
        else
            # Either we could not start it
            log_end_msg 1
        fi
	;;
  stop)
        log_daemon_msg "Stopping $DESC" "$NAME"
        if running ; then
            # Only stop the server if we see it running
			errcode=0
            stop_server || errcode=$?
            log_end_msg ${errcode}
        else
            # If it's not running don't do anything
            log_progress_msg "apparently not running"
            log_end_msg 0
            exit 0
        fi
        ;;
  force-stop)
        # First try to stop gracefully the program
        $0 stop
        if running; then
            # If it's still running try to kill it more forcefully
            log_daemon_msg "Stopping (force) $DESC" "$NAME"
			errcode=0
            force_stop || errcode=$?
            log_end_msg ${errcode}
        fi
	;;
  restart|force-reload)
        log_daemon_msg "Restarting $DESC" "$NAME"
		errcode=0
        stop_server || errcode=$?
        # Wait some sensible amount, some server need this
        [ -n "$DIETIME" ] && sleep ${DIETIME}
        start_server || errcode=$?
        [ -n "$STARTTIME" ] && sleep ${STARTTIME}
        running || errcode=$?
        log_end_msg ${errcode}
	;;
  status)
        log_daemon_msg "Checking status of $DESC" "$NAME"
        if running ;  then
            log_progress_msg "running"
            log_end_msg 0
        else
            log_progress_msg "apparently not running"
            log_end_msg 1
            exit 1
        fi
    ;;
  reload)
       log_warning_msg "Reloading $NAME daemon: not implemented, as the daemon"
       log_warning_msg "cannot re-read the config file (use restart)."
    ;;
  *)
	N=/etc/init.d/${NAME}
	echo "Usage: $N {start|stop|force-stop|restart|force-reload|status}" >&2
	exit 1
	;;
esac

exit 0
EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > ${installdir}/init.d/mongodb
    sudo chmod a+x  ${installdir}/init.d/mongodb
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    # control
    cat > debian/DEBIAN/control <<- EOF
Package: MongoDB
Version: ${version}
Description: MongoDB server deb package
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
if [[ -z "$(cat /etc/group | grep -E '^mongodb:')" ]]; then
    groupadd -r mongodb
fi
if [[ -z "$(cat /etc/passwd | grep -E '^mongodb:')" ]]; then
    useradd -r mongodb -g mongodb
fi

# dir owner and privileges
chown -R mongodb:mongodb $installdir

# link file
ln -sf $installdir/bin/mongo /usr/local/bin/mongo
ln -sf $installdir/init.d/mongodb /etc/init.d/mongodb

# lib load
ldconfig

# clear logs and data
rm -rf $installdir/logs/* && rm -rf $installdir/data/*

# start mongodb service
update-rc.d mongodb defaults && \
systemctl daemon-reload && service mongodb start
if [[ $? -ne 0 ]]; then
    echo "mongodb service start failed, please check and trg again..."
    exit
fi
EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > debian/DEBIAN/postinst

    cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

service mongodb stop
EOF

    # postrm
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

update-rc.d mongodb remove
rm -rf /etc/ld.so.conf.d/mongodb.conf
rm -rf /usr/local/bin/mongo
rm -rf /etc/init.d/mongodb
rm -rf $installdir

if [[ -n "$(cat /etc/group | grep -E '^mongodb:')" ]]; then
    groupdel -f mongodb
fi
if [[ -n "$(cat /etc/passwd | grep -E '^mongodb:')" ]]; then
    userdel -f -r mongodb
fi

ldconfig

EOF
    printf "%s" "${conf//'$installdir'/$installdir}" > debian/DEBIAN/postrm

    # chmod
    sudo chmod a+x debian/DEBIAN/postinst
    sudo chmod a+x debian/DEBIAN/postrm
    sudo chmod a+x debian/DEBIAN/prerm

    # dir
    mkdir -p debian/etc/ld.so.conf.d
    cat > debian/etc/ld.so.conf.d/mongodb.conf <<- EOF
${installdir}/lib
EOF
    mkdir -p debian/${installdir}
    mv ${installdir}/* debian/${installdir}


    # deb
    sudo dpkg-deb --build debian
     if [[ -z ${NAME} ]]; then
        NAME=mongodb_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
}

clean(){
    sudo rm -rf ${workdir}/mongodb
    sudo rm -rf ${workdir}/mongodb.tar.gz
}

do_install() {
    if [[ ${INIT} ]]; then
        init
    fi

    build_openssl
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    download_mongodb
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
