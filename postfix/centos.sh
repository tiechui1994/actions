#!/bin/bash

groupadd -g 2525 postfix
useradd -g postfix -u 2525 -s /sbin/nologin -M postfix
groupadd -g 2526 postdrop
useradd -g postdrop -u 2526 -s /sbin/nologin -M postdrop

curl -o postfix-3.7.tar.gz http://cdn.postfix.johnriley.me/mirrors/postfix-release/experimental/postfix-3.7-20210424.tar.gz

curl -o openssl.tar.gz https://codeload.github.com/openssl/openssl/tar.gz/OpenSSL_1_1_1g

# db, gcc
yum install libdb-devel gcc make m4 -y

# utf8
yum install icu libicu libicu-devel

# build openssl
yum install perl-core zlib-devel -y
./config --prefix=/usr/local/openssl shared zlib && make && make install


# sqlit3, /usr/include, /lib64
yum install sqlite-devel

# sasl, /usr/include/sasl, /usr/lib64/sasl2
yum install cyrus-sasl cyrus-sasl-devel

make -f Makefile.init makefiles \
    'CCARGS=-fPIE -DHAS_SQLITE -DUSE_SASL_AUTH -DUSE_CYRUS_SASL -DUSE_TLS -I/usr/include/sasl -I/usr/local/openssl/include -DDEF_COMMAND_DIR=\"/opt/postfix/sbin\" -DDEF_CONFIG_DIR=\"/opt/postfix/config\" -DDEF_DAEMON_DIR=\"/opt/postfix/libexec\" -DDEF_DATA_DIR=\"/opt/postfix/data\" -DDEF_MAILQ_PATH=\"/opt/postfix/bin/mailq\" -DDEF_SENDMAIL_PATH=\"/opt/postfix/sbin/sendmail\" -DDEF_MANPAGE_DIR=\"/opt/postfix/man\" -DDEF_NEWALIAS_PATH=\"/opt/postfix/newaliases\" -DDEF_QUEUE_DIR=\"/opt/postfix/spool\"' \
    'AUXLIBS_SQLITE=-L/lib64 -lsqlite3 -lpthread -lz -lrt -lm -L/usr/lib64/sasl2 -lsasl2 -L/usr/local/openssl/lib -lssl -lcrypto'
