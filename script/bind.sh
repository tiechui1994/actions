#!/bin/bash

VERSION=$1
INSTALL=$2
INIT=$3
NAME=$4

declare -r version=${VERSION:=9.18.9}
declare -r workdir=$(pwd)
declare -r installdir=${INSTALL:=/opt/local/bind}

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

download_bind() {
    sudo apt-get update && \
    sudo apt-get install build-essential \
        zlib1g-dev openssl libssl-dev libuv1.dev libnghttp2-dev -y

    url=" https://downloads.isc.org/isc/bind9/$version/bind-$version.tar.xz"
    cd ${workdir} && download "bind.tar.xz" "$url" curl 1
}

download_openssl() {
    prefix="https://ftp.openssl.org/source/old"
    openssl="$(openssl version |cut -d " " -f2)"
    if [[ ${openssl} =~ ^1\.[0-1]\.[0-2]$ ]]; then
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl} ${openssl})
    else
        url=$(printf "%s/%s/openssl-%s.tar.gz" ${prefix} ${openssl:0:${#openssl}-1} ${openssl})
    fi
    cd ${workdir} && download "openssl.tar.gz" "$url" curl 1
}

download_zlib() {
    url="http://www.zlib.net/fossils/zlib-1.2.11.tar.gz"
    url="https://codeload.github.com/madler/zlib/tar.gz/refs/tags/v1.2.11"
    cd ${workdir} && download "zlib.tar.gz" "$url" curl 1
}


build() {
    rm -rf ${installdir} && mkdir -p ${installdir}

    cd ${workdir}/bind

    ./configure \
    --prefix=${installdir} \
    --disable-linux-caps \
    --with-zlib \
    --with-openssl=${workdir}/openssl
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

    sudo make install > ${workdir}/log 2>&1
    if [[ $? -ne 0 ]]; then
        log_error "install failed"
        tail -100 ${workdir}/log
        return ${failure}
    fi

    log_info "build bind9 success"
}

service() {
    # named.conf
    read -r -d '' conf <<-'EOF'

options {
        version "@version";

        // all relative paths use this directory as a base
        directory "@installdir";
        dump-file "data/named_dump.db";           // _PATH_DUMPFILE
        pid-file "data/named.pid";                // _PATH_PIDFILE
        lock-file "data/named.lock";
        session-keyfile "data/session.key";
        statistics-file "data/named.stats";       // _PATH_STATS
        memstatistics-file "data/named.memstats"; // _PATH_MEMSTATS
        managed-keys-directory "data";

        // send NOTIFY messages.  You can set notify on a zone-by-zone
        // basis in the "zone" statement see (below)
        notify yes;

        recursion yes;
        dnssec-validation no;

        listen-on port 53 {
            127.0.0.1;
        };

        // The "forward" option is only meaningful if you've defined forwarders.
        // "first" gives the normal BIND forwarding behavior, i.e. ask the forwarders first,
        // and if that doesn't work then do the full lookup.
        // You can also say "forward only;" which is what used to be specified with "slave" or "options forward-only".
        // "only" will never attempt a full lookup; only the forwarders will be used.

        forward only;
        forwarders {
            8.8.8.8;
        };

        allow-query { any; };
        allow-recursion { any; };
};

zone "." {
  type hint;
  file "data/named.root";
};

logging {
        /*
         * All log output goes to one or more "channels"; you can make as
         * many of them as you want.
         */

        // this channel will send errors or or worse to syslog (user facility)
        channel file_log {
            file    "data/named.log" versions 3 size 20M;
            severity debug 3;
            print-time yes;
            print-category yes;
            print-severity yes;
        };

        /*
         * You can also define category "default"; it gets used when no
         * "category" statement has been given for a category.
         */

        category resolver {
            file_log;
        };
        category cname {
            file_log;
        };
        category dnssec {
            file_log;
        };
        category queries {
            file_log;
        };
        category default {
            file_log;
        };
};
EOF
    conf=${conf//'@installdir'/$installdir}
    conf=${conf//'@version'/$version}
    printf "%s" "$conf" > ${installdir}/etc/named.conf

    # service
    sudo mkdir -p ${installdir}/init.d
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

### BEGIN INIT INFO
# Provides:          named
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Default-Start:     2
# Default-Stop:      0 1 3 4 5 6
# Description:       named service daemon
### END INIT INFO

DAEMON=@installdir/sbin/named
PID=@installdir/data/named.pid
CONF=@installdir/etc/named.conf
NAME=named

test -x ${DAEMON} || exit 0

# Try to extract named pidfile
directory=$(cat h.conf |grep -E '^\s+[a-z]+.*'|awk '{ if ($1 ~ /^\s*directory/) { gsub(/[";]/, "", $2); print $2 }')
pidfile=$(cat h.conf |grep -E '^\s+[a-z]+.*'|awk '{ if ($1 ~ /^\s*pid-file/) { gsub(/[";]/, "", $2); print $2 }')
if [[ -n ${directory} && -n ${pidfile} ]]; then
  PID="${directory}/${pidfile}"
fi

. /lib/init/vars.sh
. /lib/lsb/init-functions

#
# Function that starts the daemon/service
#
do_start()
{
    # Return
    #   0 if daemon has been started
    #   1 if daemon was already running
    #   2 if daemon could not be started
    start-stop-daemon --start --pidfile ${PID} --make-pidfile --exec ${DAEMON} -- \
        -f -c ${CONF} 2>/dev/null \
        || return 2
}

#
# Function that stops the daemon/service
#
do_stop()
{
    # Return
    #   0 if daemon has been stopped
    #   1 if daemon was already stopped
    #   2 if daemon could not be stopped
    #   other if a failure occurred
    start-stop-daemon --stop --retry=TERM/30/KILL/5 --pidfile ${PID} --name ${NAME}
    RETVAL="$?"

    sleep 1
    return "${RETVAL}"
}

case "$1" in
    start)
        log_daemon_msg "Starting ${NAME}"
        do_start
        case "$?" in
            0|1) log_end_msg 0 ;;
            2) log_end_msg 1 ;;
        esac
        ;;
    stop)
        log_daemon_msg "Stopping ${NAME}"
        do_stop
        case "$?" in
            0|1) log_end_msg 0 ;;
            2) log_end_msg 1 ;;
        esac
        ;;
    restart)
        log_daemon_msg "Restarting ${NAME}"

        do_stop
        case "$?" in
            0|1)
                do_start
                case "$?" in
                    0) log_end_msg 0 ;;
                    1) log_end_msg 1 ;; # Old process is still running
                    *) log_end_msg 1 ;; # Failed to start
                esac
                ;;
            *)
                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;
    status)
        status_of_proc -p ${PID} "${DAEMON}" "${NAME}" && exit 0 || exit $?
        ;;
    *)
        log_failure_msg "Please use start or stop as first argument"
        ;;
esac
EOF
    conf=${conf//'@installdir'/$installdir}
    printf "%s" "$conf" > ${installdir}/init.d/named
    sudo chmod a+x ${installdir}/init.d/named

    cp ${workdir}/bind/fuzz/isc_lex_getmastertoken.in/named.conf ${installdir}/etc/master_named.conf.sample
    cp ${workdir}/bind/fuzz/isc_lex_gettoken.in/named.conf ${installdir}/etc/slave_named.conf.sample
}

package() {
    cd ${workdir}
    sudo rm -rf debian && mkdir -p debian/DEBIAN

    arch="amd64"
    if [[ ${NAME} =~ (.*)?arm64.deb$ ]]; then
        arch="arm64"
    fi

    # control
    cat > debian/DEBIAN/control <<- EOF
Package: Bind9
Version: ${version}
Description: Bind9 server deb package
Section: utils
Priority: standard
Essential: no
Architecture: ${arch}
Depends:
Maintainer: tiechui1994 <2904951429@qq.com>
Provides: github

EOF

    # postinst
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

case "$1" in
    (configure)
        # link file
        ln -sf @installdir/init.d/named /etc/init.d/named

        # test pid
        if [[ $(pgrep named) ]]; then
            echo "named install successfully !"
        fi
    ;;
    (*)
        echo "postinst called with unknown argument \`$1'" >&2
        exit 0
    ;;
esac

EOF

    printf "%s" "${conf//'@installdir'/$installdir}" > debian/DEBIAN/postinst

    # prerm
    cat > debian/DEBIAN/prerm <<- 'EOF'
#!/bin/bash

case "$1" in
    (remove)
        service named stop
    ;;
esac

EOF

    # postrm
    read -r -d '' conf <<- 'EOF'
#!/bin/bash

case "$1" in
    (remove)
        if [[ -f /etc/init.d/named ]]; then
            update-rc.d named remove
            rm -rf /etc/init.d/named
        fi

        if [[ -d @installdir ]]; then
            rm -rf @installdir
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
        NAME=bind_${version}_ubuntu_$(lsb_release -r --short)_$(uname -m).deb
    fi
    sudo mv debian.deb ${workdir}/${NAME}
}

clean() {
    echo "clean"
}

do_install(){
     if [[ ${INIT} ]]; then
        init
     fi

     download_bind && download_openssl && download_zlib
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
