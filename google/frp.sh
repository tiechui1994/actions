#!/usr/bin/env bash

version=0.42.0
curl https://github.com/fatedier/frp/releases/download/v${version}/frp_${version}_linux_amd64.tar.gz \
    -L -o frp_${version}_linux_amd64.tar.gz

mkdir frp && \
tar xf frp_${version}_linux_amd64.tar.gz -C frp --strip-components=1

mkdir -p frp/init.d
cat > frp/init.d/frpc <<-'EOF'
#!/bin/bash

### BEGIN INIT INFO
# Provides:          frp
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Default-Start:     2
# Default-Stop:      0 1 3 4 5 6
# Description:       frp service daemon
### END INIT INFO

EXEC=/opt/frp/frpc
CONF=/opt/frp/frpc.ini
PIDFILE=/opt/frp/frp.pid

. /lib/lsb/init-functions

case "$1" in
    start)
        if [[ -f ${PIDFILE} ]]; then
            log_failure_msg "${PIDFILE} exists, process is already running or crashed"
        else
            log_begin_msg "Starting frp client..."
            start-stop-daemon --start --quiet --make-pidfile --pidfile "${PIDFILE}" --exec "${EXEC}" \
                --background -- -c ${CONF}
        fi
        ;;
    stop)
        if [[ ! -f ${PIDFILE} ]]; then
            log_failure_msg "${PIDFILE} does not exist, process is not running"
        else
            log_begin_msg "Stopping ..."
            PID=$(cat ${PIDFILE})
            start-stop-daemon --stop --quiet --remove-pidfile --retry=TERM/10/KILL/5 \
                --pidfile "${PIDFILE}"
            if [[ $? -ne 0 ]]; then
                kill -9 ${PID}
            fi

            if [[ -e ${PIDFILE} ]];then
                rm -rf ${PIDFILE}
            fi

            while [[ -x /proc/${PID} ]]
            do
                log_begin_msg "Waiting for frpc to shutdown ..."
                sleep 1
            done
            log_success_msg "Frpc stopped"
        fi
        ;;
    reload)
        if [[ ! -f ${PIDFILE} ]]; then
            log_failure_msg "${PIDFILE} does not exist, process is not running"
        else
            log_begin_msg "Reload frp client..."
            ${EXEC} reload -c ${CONF}
        fi
        ;;
    *)
        log_failure_msg "Please use start or stop as first argument"
        ;;
esac
EOF

chmod a+x frp/init.d/frpc
mv frp /opt && \
ln -sf /opt/frp/init.d/frpc /etc/init.d/frpc && \
service frpc defaults

