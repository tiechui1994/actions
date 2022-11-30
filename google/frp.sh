#!/usr/bin/env bash

version=0.45.0
curl https://github.com/fatedier/frp/releases/download/v${version}/frp_${version}_linux_amd64.tar.gz \
    -L -o frp_${version}_linux_amd64.tar.gz

mkdir frp && \
tar xf frp_${version}_linux_amd64.tar.gz -C frp --strip-components=1

mkdir -p frp/init.d
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
frpc=${frpc//'@DAEMON'/'/opt/frp/init.d/frpc'}
frpc=${frpc//'@ARGS'/'--config=/opt/frp/frpc.ini'}
printf "%s" "$frpc" > frp/init.d/frpc
chmod a+x frp/init.d/frpc


mv frp /opt && \
ln -sf /opt/frp/init.d/frpc /etc/init.d/frpc && \
service frpc defaults

