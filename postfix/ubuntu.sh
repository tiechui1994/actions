#!/bin/bash

groupadd -g 2525 postfix
useradd -g postfix -u 2525 -s /sbin/nologin -M postfix
groupadd -g 2526 postdrop
useradd -g postdrop -u 2526 -s /sbin/nologin -M postdrop

# basic
apt-get update
apt-get install gcc make m4 curl -y

curl -o postfix.tar.gz http://cdn.postfix.johnriley.me/mirrors/postfix-release/experimental/postfix-3.7-20210424.tar.gz
rm -rf postfix && mkdir postfix
tar xf postfix.tar.gz -C postfix --strip-components 1

curl -o openssl.tar.gz https://codeload.github.com/openssl/openssl/tar.gz/OpenSSL_1_1_1g
rm -rf openssl && mkdir openssl
tar xf openssl.tar.gz -C openssl --strip-components 1

# build openssl
cd openssl
./config --prefix=/usr/local/openssl shared zlib && make -j4 && make install
cd ..

# db, utf8
apt-get install libdb-dev libicu-dev -y

# sqlit3, /usr/include, /lib64
apt-get install sqlite3 libsqlite3-dev -y

# sasl, /usr/include/sasl, /usr/lib64/sasl2
apt-get install libsasl2-dev -y

cd postfix
make -f Makefile.init makefiles \
    'CCARGS=-fPIE -DHAS_SQLITE -DUSE_SASL_AUTH -DUSE_CYRUS_SASL -DUSE_TLS -I/usr/include/sasl -I/usr/local/openssl/include -DDEF_COMMAND_DIR=\"/opt/postfix/sbin\" -DDEF_CONFIG_DIR=\"/opt/postfix/config\" -DDEF_DAEMON_DIR=\"/opt/postfix/libexec\" -DDEF_DATA_DIR=\"/opt/postfix/data\" -DDEF_MAILQ_PATH=\"/opt/postfix/bin/mailq\" -DDEF_SENDMAIL_PATH=\"/opt/postfix/sbin/sendmail\" -DDEF_MANPAGE_DIR=\"/opt/postfix/man\" -DDEF_NEWALIAS_PATH=\"/opt/postfix/newaliases\" -DDEF_QUEUE_DIR=\"/opt/postfix/spool\"' \
    'AUXLIBS_SQLITE=-L/lib64 -lsqlite3 -lpthread -lz -lrt -lm -L/usr/lib64/sasl2 -lsasl2 -L/usr/local/openssl/lib -lssl -lcrypto'
make -j4 && make install
cd ..