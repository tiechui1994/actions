#!/usr/bin/env bash

colab_ngrok_args() {
    local authtoken region log file OPTIND
    authtoken=
    region="us"
    log="/var/log/ngrok.log"

    OPTIND=1
    while getopts a:r:l:f: opt ; do
        case "$opt" in
            a)
                authtoken="$OPTARG" ;;
            r)
                region="$OPTARG" ;;
            l)
                log="$OPTARG" ;;
            t)
                file="$OPTARG"
        esac
    done
    shift $(($OPTIND - 1))


    echo "authtoken: $authtoken region: $region log: $log type, ${!type[@]}"
}

colab_init() {
    apt-get --quiet update && \
    apt-get --quiet install  --yes openssh-server net-tools iputils-ping iproute2 iptables openssl vim

    if [[ $# -gt 0 ]]; then
        for i in $@; do
            apt-get --quiet install --yes "$i"
        done
    fi

    if [[ ! -x "/usr/local/bin/ngrok" ]]; then
        wget --quiet https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.tgz -O ngrok.tgz
        tar xf ngrok.tgz && mv ngrok /usr/local/bin/ngrok && rm -rf ngrok.tgz
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

colab_ngrok_service() {
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
PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="$DESC"
NAME="$NAME"
DAEMON=$DAEMON
DAEMON_ARGS="$ARGS"
PIDFILE=/var/run/${NAME}.pid
SCRIPTNAME=/etc/init.d/${NAME}

[ -x "$DAEMON" ] || exit 0

. /lib/init/vars.sh
. /lib/lsb/init-functions

do_start() {
        # Return
        #   0 if daemon has been started
        #   1 if daemon was already running
        #   2 if daemon could not be started
        start-stop-daemon --start --quiet --pidfile ${PIDFILE} --exec ${DAEMON} --test > /dev/null \
                || return 1
        start-stop-daemon --start --quiet --pidfile ${PIDFILE} --exec ${DAEMON} --background -- \
                ${DAEMON_ARGS} \
                || return 2
        # Add code here, if necessary, that waits for the process to be ready
        # to handle requests from services started subsequently which depend
        # on this one.  As a last resort, sleep for some time.
}

do_stop() {
        # Return
        #   0 if daemon has been stopped
        #   1 if daemon was already stopped
        #   2 if daemon could not be stopped
        #   other if a failure occurred
        start-stop-daemon --stop --quiet --retry=TERM/10/KILL/5 --pidfile ${PIDFILE} --name ${NAME}
        RETVAL="$?"
        [ "$RETVAL" = 2 ] && return 2
        # Wait for children to finish too if this is a daemon that forks
        # and if the daemon is only ever run from this initscript.
        # If the above conditions are not satisfied then add some other code
        # that waits for the process to drop all resources that could be
        # needed by services started subsequently.  A last resort is to
        # sleep for some time.
        start-stop-daemon --stop --quiet --oknodo --retry=0/10/KILL/5 --exec ${DAEMON}
        [ "$?" = 2 ] && return 2
        # Many daemons don't delete their pidfiles when they exit.
        rm -f ${PIDFILE}
        return "$RETVAL"
}

VERBOSE="yes"

case "$1" in
  start)
        [ "$VERBOSE" != no ] && log_daemon_msg "Starting ${DESC}" "${NAME}"
        do_start
        case "$?" in
                0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
                2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
  stop)
        [ "$VERBOSE" != no ] && log_daemon_msg "Stopping ${DESC}" "${NAME}"
        do_stop
        case "$?" in
                0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
                2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
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
        #echo "Usage: $SCRIPTNAME {start|stop|restart|reload|force-reload}" >&2
        echo "Usage: ${SCRIPTNAME} {start|stop|status|restart}" >&2
        exit 3
        ;;
esac
EOF

    ngrok=${conf}
    ngrok=${ngrok//'$NAME'/'ngrok'}
    ngrok=${ngrok//'$DESC'/'ngrok'}
    ngrok=${ngrok//'$DAEMON'/'/usr/local/bin/ngrok'}
    ngrok=${ngrok//'$ARGS'/'start --config=/etc/ngrok.yml --all'}
    printf "%s" "$ngrok" > /etc/init.d/ngrok
    chmod a+x /etc/init.d/ngrok
}

colab_ngrok_config() {
    local file OPTIND

    OPTIND=1
    while getopts f: opt ; do
        case "$opt" in
            f) file="$OPTARG" ;;
        esac
    done
    shift $(($OPTIND - 1))

    if [[ -f "$file" ]]; then
        echo "(-f file) must be set and exist"
        exit 1
    fi

    read -d '' -r conf <<-'EOF'
authtoken: $authtoken
# regions: us, jp, in, ap
region: $region
log: $log
log_level: info
log_format: json
update: false
update_channel: stable
tunnels:
  ssh:
    addr: 22
    proto: tcp
  tcp:
    addr: 5432
    proto: tcp
  http:
    addr: 80
    proto: http
EOF
    conf=${conf//'$authtoken'/$authtoken}
    conf=${conf//'$region'/$region}
    conf=${conf//'$log'/$log}
    printf "%s" "$conf" > /etc/ngrok.yml

   read -d '' -r conf <<-'EOF'
import json
import requests
import re

keys = {}

def handle(data):
    log = json.JSONDecoder().decode(data)
    if 'url' in log and 'obj' in log and log['obj'] == 'tunnels':
        keys[log['name']] = log['url']
        if log['name'] == 'ssh':
            matched = re.findall('tcp://([^:]+?):([0-9]+)', log['url'])
            keys[log['name']] = 'ssh root@%s -p %s' % (matched[0][0], matched[0][1])
        body = {
            'ttl': 28800,
            'value': keys
        }
        url = 'https://jobs.tiechui1994.tk/api/mongo?key=ngrok'
        r = requests.request("POST", url, json=body, verify=True)
        print('result:', str(r.content, 'utf-8'))


def read(file):
    with open(file, mode='r', buffering=4096) as fifo:
        temp = ''
        while True:
            data = fifo.read()
            if len(data) == 0:
                break

            data = str(data)
            n = len(data)
            begin, end = 0, len(data)
            nums = str(data).count('}', begin, end)
            last = data[n - 1] == '}'
            for i in range(0, nums):
                length = data[begin:end].index('}')
                if i == 0 and data[0] != '{':
                    handle(temp + data[begin:begin + length + 1])
                    temp = ''
                    begin += length + 1
                    continue

                handle(data[begin:begin + length + 1])
                begin += length + 1

            if not last:
                temp = data[begin:end]

try:
    read('$log')
except Exception as e:
    print(e)
EOF
   conf=${conf//'$log'/$log}
   printf "%s" "$conf" > /usr/local/bin/upload.py
}

colab_start_service() {
    service $@ restart && sleep 5 && service $@ status
}

colab_ngrok_log() {
    python3 /usr/local/bin/upload.py
}

