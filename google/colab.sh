#!/usr/bin/env bash


init() {
    apt-get update && \
    apt-get install -y openssh-server net-tools iputils-ping iproute2 iptables \
        openssl vim perl5.2

    wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.tgz -O ngrok.tgz
    tar xvf ngrok.tgz && mv ngrok /usr/local/bin/ngrok && rm -rf ngrok.tgz
}

update_passwd() {
    if [[ "$(grep -E '^root' /etc/shadow|cut -d : -f2)" = "*" ]]; then
        passwd=$(echo $@ |openssl passwd -6 -stdin);
        sed -i -E "/^root/ s|root:([^:]+?):(.*)|root:$passwd:\2|" /etc/shadow;
    fi
}

update_ssh() {
    if [[ -z "$(grep -E '^PermitRootLogin' /etc/ssh/sshd_config)" ]]; then
        sed -i -E "/^#PermitRootLogin/ s|#PermitRootLogin.*|PermitRootLogin yes|" /etc/ssh/sshd_config;
        service ssh start
    fi
}

add_common_service() {
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

# Exit if the package is not installed
[ -x "$DAEMON" ] || exit 0

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.2-14) to ensure that this file is present
# and status_of_proc is working.
. /lib/lsb/init-functions

#
# Function that starts the daemon/service
#
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

#
# Function that stops the daemon/service
#
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

add_ngrok_config() {
    local authtoken region log OPTIND
    authtoken=
    region="us"
    log="/var/log/ngrok.log"

    OPTIND=1
    while getopts a:rl opt ; do
        case "$opt" in
            a)  authtoken="$OPTARG" ;;
            r)  region="$OPTARG" ;;
            l)  log="$OPTARG" ;;
        esac
    done
    shift $(($OPTIND - 1))

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

start_service() {
    service $@ restart && sleep 5 && service $@ status
}

upload_log() {
    python3 /usr/local/bin/upload.py
}

openvpn_init() {
    PATH_SERVER="/etc/openvpn/server"
    ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}')
    port=5432
    protocol="tcp"
    client="client"

    # 获取 easy-rsa.
    easy_rsa_url='https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.8/EasyRSA-3.0.8.tgz'
    mkdir -p ${PATH_SERVER}/easy-rsa/
    curl -sL "$easy_rsa_url" | tar xz -C ${PATH_SERVER}/easy-rsa/ --strip-components 1
    chown -R root:root ${PATH_SERVER}/easy-rsa

    # 创建 PKI, 生成 CA, Server, Client 证书
    cd ${PATH_SERVER}/easy-rsa
    ./easyrsa init-pki
    ./easyrsa --batch build-ca nopass  # ca.crt
    EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-server-full server nopass # server.crt
    EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass # client.crt
    EASYRSA_CRL_DAYS=3650    ./easyrsa gen-crl

    # 将生成的 server 相关的信息复制
    cp pki/ca.crt \
        pki/private/ca.key \
        pki/issued/server.crt \
        pki/private/server.key \
        pki/crl.pem \
        ${PATH_SERVER}

    # 文件目录权限
    chown "nobody:nogroup" ${PATH_SERVER}/crl.pem
    chmod o+x ${PATH_SERVER}

    # 生成 tls-crypt key
    openvpn --genkey --secret ${PATH_SERVER}/tc.key

    # 生成 DH 参数(2048位)
    openssl dhparam -2 -out ${PATH_SERVER}/dh.pem

        # 生成 server.conf
    cat > ${PATH_SERVER}/server.conf <<-EOF
local ${ip}
port ${port}
proto ${protocol}
dev tun
topology subnet
server 10.8.0.0 255.255.255.0

push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

keepalive 10 120
auth SHA512
cipher AES-256-CBC
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-crypt tc.key
crl-verify crl.pem
tls-server
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256
user nobody
group nogroup
persist-key
persist-tun
verb 3
EOF

    # 脚本
    read -r -d '' conf <<-'EOF'
#!/bin/sh

### BEGIN INIT INFO
# Provides:          iptablesvpn
# Required-Start:    $syslog
# Required-Stop:     $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: iptablesvpn script
### END INIT INFO

ip=$ip
port=$port
protocol=UDP

DESC="iptablesvpn"
NAME="iptablesvpn"
SCRIPT=/etc/init.d/$NAME

. /lib/init/vars.sh
. /lib/lsb/init-functions

do_start() {
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to ${ip}
    iptables -I INPUT -p ${protocol} --dport ${port} -j ACCEPT
    iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
    iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
}

do_stop() {
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to ${ip}
    iptables -D INPUT -p ${protocol} --dport ${port} -j ACCEPT
    iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT
    iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    return "$RETVAL"
}

VERBOSE="yes"

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
  restart)
        log_daemon_msg "Restarting ${DESC}" "${NAME}"
        do_stop
        case "$?" in
          0|1)
                do_start
                case "$?" in
                        0) log_end_msg 0 ;;
                        1) log_end_msg 1 ;;
                        *) log_end_msg 1 ;;
                esac
                ;;
          *)
                log_end_msg 1
                ;;
        esac
        ;;
  *)
        echo "Usage: ${SCRIPT} {start|stop|status|restart}" >&2
        exit 3
        ;;
esac
EOF

    conf=${conf//'$ip'/$ip}
    conf=${conf//'$port'/$port}
    printf "%s" "$ngrok" > /etc/init.d/iptablesvpn
    chmod a+x /etc/init.d/iptablesvpn

    # 生成客户端 common 文件, 在生成 client.ovpn 的时候使用
    cat > ${PATH_SERVER}/client-common.txt <<-EOF
client
dev tun
proto ${protocol}
remote ${ip} ${port}
pull
nobind
persist-key
persist-tun
connect-retry 5 5
resolv-retry infinite
ignore-unknown-option block-outside-dns
block-outside-dns
remote-cert-tls server
cipher AES-256-CBC
auth SHA512
tls-client
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256
verb 3
EOF

    /usr/sbin/openvpn --status /run/status-server.log --status-version 2 --suppress-timestamps --config /etc/openvpn/server/server.conf

    common=$(cat ${PATH_SERVER}/client-common.txt)
    ca=$(cat ${PATH_SERVER}/easy-rsa/pki/ca.crt)
    cert=$(cat "${PATH_SERVER}/easy-rsa/pki/issued/$client.crt" | grep -v CERTIFICATE)
    key=$(cat "${PATH_SERVER}/easy-rsa/pki/private/$client.key" | grep -v OpenVPN)
    tc=$(cat ${PATH_SERVER}/tc.key)

    # 生成 client.ovpn
    cat > "~/$client.ovpn" <<-EOF
${common}
<ca>
${ca}
</ca>
<cert>
${cert}
</cert>
<key>
${key}
</key>
<tls-crypt>
${tc}
</tls-crypt>
EOF

}

