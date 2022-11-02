#!/bin/bash -ex
# Download & build breakpad on the local machine
# works on Linux, OS X and Windows
# leaves output in /tmp/prebuilts/google-breakpad/$OS-x86
build_and_install_MSVC()
{
	solution=$1
	project=$2
	if [ x"$project" == x ]; then
		project_switch=""
	else
		project_switch="/Project $project"
	fi
        $RD/gyp/gyp --no-circular-check --no-duplicate-basename-check $solution.gyp
        (
                export CL="/DBPLOG_MINIMUM_SEVERITY=SEVERITY_ERROR \"$VS120COMNTOOLS\\..\\..\\DIA SDK\\include\""
                _CL_="/MDd /WX-" devenv $solution.sln /Build Debug $project_switch
                _CL_="/MD /WX-" devenv $solution.sln /Build Release $project_switch
        )
        for build in Debug Release; do
                find $build -name '*.exe' -exec cp -va -t $INSTALL/$build {} +
                find $build -name '*.lib' -exec cp -va -t $INSTALL/$build {} +
        done
}
build_and_install_configure()
{
        mkdir $RD/build
        cd $RD/build
        local defines="-DBPLOG_MINIMUM_SEVERITY=SEVERITY_ERROR"
        export CFLAGS="$CFLAGS $defines"
        export CXXFLAGS="$CXXFLAGS $defines"
        ../sources/configure --prefix=/
        make -j$CORES
        make install-strip DESTDIR=$INSTALL
}
install_headers()
{
	mkdir -p $INSTALL/include/breakpad
	cd $RD/sources/src
	rsync -av --include '*/' --include '*.h' --exclude '*' --prune-empty-dirs . $INSTALL/include/breakpad
}

PROJ=google-breakpad
VER=335e6165
LSS_VER=e1e7b0a
GYP_VER=9ecf45e
MSVS=2013

git clone https://chromium.googlesource.com/chromium/tools/depot_tools depot_tools
export PATH=$PATH:$(pwd)/depot_tools

mkdir breakpad && cd breakpad
fetch breakpad

cd src/third_party
git clone https://chromium.googlesource.com/linux-syscall-support --no-checkout lss
cd lss
git checkout $LSS_VER
cd $RD
git clone https://chromium.googlesource.com/external/gyp --no-checkout gyp
cd gyp
git checkout $GYP_VER
cd src

case "$OS" in
	linux)
    build_and_install_configure
		# make install does not actually install all the headers. Let's finish the job
		# for him.
		# TODO: This can be removed when the upstream installation patch lands
		install_headers
	;;
	darwin)
    build_and_install_configure
    install_headers
	;;
	windows)
		mkdir $INSTALL/Release $INSTALL/Debug
		cd $RD/sources/src/client/windows/handler
		build_and_install_MSVC exception_handler exception_handler
		cd $RD/sources/src/client/windows/crash_generation
		build_and_install_MSVC crash_generation crash_generation_client
		cd $RD/sources/src/common/windows
		build_and_install_MSVC common_windows common_windows_lib
		cd $RD/sources/src/tools/windows/dump_syms
		build_and_install_MSVC dump_syms dump_syms
		cd $RD/sources/src/tools/windows/symupload
		build_and_install_MSVC symupload symupload
                cd $RD/sources/src/processor
                build_and_install_MSVC processor minidump_stackwalk
                install_headers
	;;
esac