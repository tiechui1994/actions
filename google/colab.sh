#!/usr/bin/env bash

colab_init() {
    apt-get --quiet update && \
    apt-get --quiet install  --yes openssh-server net-tools iputils-ping iproute2 iptables openssl vim

    if [[ $# -gt 0 ]]; then
        for i in $@; do
            apt-get --quiet install --yes "$i"
        done
    fi

    if [[ ! -d "/usr/local/frp" ]]; then
        wget --quiet https://github.com/fatedier/frp/releases/download/v0.45.0/frp_0.45.0_linux_amd64.tar.gz -O frp.tgz
        rm -rf frp && mkdir frp
        tar xf frp.tgz -C frp --strip-components 1 && \
        mv frp /usr/local && rm -rf frp.tgz
    fi
}

colab_change_passwd() {
    passwd=$(echo $@ |openssl passwd -6 -stdin)
    sed -i -E "/^root/ s|root:([^:]+?):(.*)|root:$passwd:\2|" /etc/shadow
}

colab_ssh_root() {
    cat > /etc/ssh/sshd_config <<-'EOF'
Port 22
AddressFamily any
ListenAddress 0.0.0.0

PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

UsePAM yes

ClientAliveInterval 30
ClientAliveCountMax 10000

X11Forwarding yes
PrintMotd no

AcceptEnv LANG LC_*
Subsystem	sftp	/usr/lib/openssh/sftp-server
EOF

    service ssh start
}

colab_frp_service() {
    read -r -d '' conf <<-'EOF'
#!/bin/sh

### BEGIN INIT INFO
# Provides:          $NAME
# Required-Start:    $syslog
# Required-Stop:     $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: $NAME script
### END INIT INFO

# PATH should only include /usr/* if it runs after the mountnfs.sh script
DESC="@DESC"
NAME="@NAME"
DAEMON=@DAEMON
DAEMON_ARGS="@ARGS"
PIDFILE=/var/run/${NAME}.pid
SCRIPTNAME=/etc/init.d/${NAME}

[ -x "${DAEMON}" ] || exit 0

. /lib/init/vars.sh
. /lib/lsb/init-functions

do_start() {
        # Return
        #   0 if daemon has been started
        #   1 if daemon was already running
        #   2 if daemon could not be started
        start-stop-daemon --start --quiet --make-pidfile --pidfile ${PIDFILE} --exec ${DAEMON} --background -- \
                ${DAEMON_ARGS} \
                || return 2
}

do_stop() {
        # Return
        #   0 if daemon has been stopped
        #   1 if daemon was already stopped
        #   2 if daemon could not be stopped
        #   other if a failure occurred
        start-stop-daemon --stop --quiet --remove-pidfile --pidfile ${PIDFILE} --retry=TERM/10/KILL/5 --name ${NAME}
        RETVAL="$?"
        [ "$RETVAL" = 2 ] && return 2
}


case "$1" in
  start)
        log_daemon_msg "Starting ${DESC}" "${NAME}"
        do_start
        case "$?" in
                0|1) log_end_msg 0 ;;
                2)   log_end_msg 1 ;;
        esac
        ;;
  stop)
        log_daemon_msg "Stopping ${DESC}" "${NAME}"
        do_stop
        case "$?" in
                0|1) log_end_msg 0 ;;
                2)   log_end_msg 1 ;;
        esac
        ;;
  status)
        status_of_proc "${DAEMON}" "${NAME}" && exit 0 || exit $?
        ;;
  restart)
        log_daemon_msg "Restarting ${DESC}" "${NAME}"
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
  *)
        echo "Usage: ${SCRIPTNAME} {start|stop|status|restart}" >&2
        exit 3
        ;;
esac
EOF

    frpc=${conf}
    frpc=${frpc//'@NAME'/'frpc'}
    frpc=${frpc//'@DESC'/'frpc'}
    frpc=${frpc//'@DAEMON'/'/usr/local/frp/frpc'}
    frpc=${frpc//'@ARGS'/'--config=/usr/local/frp/frpc.ini'}
    printf "%s" "$frpc" > /etc/init.d/frpc
    chmod a+x /etc/init.d/frpc
}

colab_frp_config() {
    read -r -d '' conf <<-'EOF'
[common]
server_addr = frp1.freefrp.net
server_port = 7000
token = freefrp.net

[ssh_@NAME_@UID]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = 20022

EOF

    frpc=${conf}
    frpc=${frpc//'@NAME'/'google'}
    frpc=${frpc//'@UID'/$(date '+%s')}
    printf "%s" "$frpc" > /usr/local/frp/frpc.ini
}

colab_frp_upload() {
    value="ssh root@frp1.freefrp.net -p 20022"
    data='{"ttl":28800,"value":"@value"}'
    curl --request POST -sL \
         --url 'https://api.quinn.eu.org/api/mongo?key=frpc'\
         --data "${data//'@value'/$value}" > /dev/null

    echo "ssh: [ $value ]"
}

colab_start_service() {
    service $@ restart && sleep 5 && service $@ status
}

