#!/bin/bash
# Copyright 2012 The Go Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# This script rebuilds the time zone files using files
# downloaded from the ICANN/IANA distribution.
# Consult https://www.iana.org/time-zones for the latest versions.

# Versions to use.
VER=2021e

set -e

rm -rf work && mkdir work
cd work && mkdir source

# download file
curl -L -O https://www.iana.org/time-zones/repository/releases/tzcode$VER.tar.gz
curl -L -O https://www.iana.org/time-zones/repository/releases/tzdata$VER.tar.gz
tar xzf "tzcode$VER.tar.gz" -C source
tar xzf "tzdata$VER.tar.gz" -C source

# build
chmod -Rf a+rX,u+w,g-w,o-w source

make VERSION="$VER" "tzdata$VER-rearguard.tar.gz"


cd zoneinfo
rm -f ../../zoneinfo.zip
zip -0 -r ../../zoneinfo.zip *
cd ../..

#go generate time/tzdata

echo
if [ "$1" = "-work" ]; then
	echo Left workspace behind in work/.
else
	rm -rf work
fi
echo New time zone files in zoneinfo.zip.