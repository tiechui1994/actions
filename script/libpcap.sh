#!/usr/bin/env bash

# gcc download
wget http://releases.linaro.org/components/toolchain/binaries/7.5-2019.12/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz \
-O gcc-aarch64-linux-gnu.tar.xz

rm -rf gcc && mkdir gcc 
tar xvf gcc-aarch64-linux-gnu.tar.xz -C gcc --strip-components 1

# libpcap download
wget https://www.tcpdump.org/release/libpcap-1.9.1.tar.gz \
-O libpcap.tar.gz 

rm -rf libpcap && mkdir libpcap 
tar xvf libpcap.tar.gz -C libpcap --strip-components 1


# install depend
sudo apt-get install flex bison -y

# env
export CC=${PWD}/gcc/bin/aarch64-linux-gnu-gcc
export CXX=${PWD}/gcc/bin/aarch64-linux-gnu-g++

# build
rm -rf pcap && mkdir pcap
target=${PWD}/pcap

cd libpcap

./configure --host=aarch64-linux \
--prefix=${target} \
--with-pcap=linux 

make && make install
