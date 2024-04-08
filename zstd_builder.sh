#!/bin/bash

GITHUB_ENV="$1"
ZSTD_BRANCH="$2"
ZLIB_ENABLED="$3"
LZ4_ENABLED="$4"
XZ_ENABLED="$5"
ZLIB_BRANCH="$6"
LZ4_BRANCH="$7"
XZ_BRANCH="$8"
NDK_VER="$9"
SDK_VER="${10}"

NDK_DIR="android-ndk-$NDK_VER"
WORK_DIR="$(pwd)/zstd_workdir"
NDK="$WORK_DIR/$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"

DATA=$(date +'%y%m%d')
echo "DATA="${DATA}"" >>$GITHUB_ENV

Red='\033[1;31m'
Yellow='\033[1;33m'
Blue='\033[1;34m'
Green='\033[1;32m'

run_all() {
	create_build_workdir
	create_android_aarch64
	build_zlib_for_android
	build_lz4_for_android
	build_xz_for_android
	build_zstd_for_android
}

create_build_workdir() {
	echo -e "${Green}- Creating work directory ..."
	mkdir -p "$WORK_DIR" && cd "$_"

	echo -e "${Green}- Downloading "$NDK_DIR" ..."
	curl https://dl.google.com/android/repository/"$NDK_DIR"-linux.zip --output "$NDK_DIR"-linux.zip

	echo -e "${Yellow}- Exracting "$NDK_DIR" ..."
	unzip "$NDK_DIR"-linux.zip &>/dev/null
	rm -rf "$NDK_DIR"-linux.zip

	echo -e "${Blue}- Cloning zlib ..."
	git clone --depth=1 https://github.com/madler/zlib.git -b "$ZLIB_BRANCH"

	echo -e "${Blue}- Cloning lz4 ..."
	git clone --depth=1 https://github.com/lz4/lz4.git -b "$LZ4_BRANCH"

	echo -e "${Blue}- Cloning xz ..."
	git clone --depth=1 https://git.tukaani.org/xz.git -b "$XZ_BRANCH"

	echo -e "${Blue}- Cloning zstd ..."
	git clone --depth=1 https://github.com/facebook/zstd.git -b "$ZSTD_BRANCH"

	echo -e "${Green}- Creating output directory ..."
	mkdir -p "$WORK_DIR"/output
}

create_android_aarch64() {
	echo -e "${Green}- Creating android-aarch64 file ..."
	cat <<EOF >"android-aarch64"
[binaries]
ar = '$NDK/llvm-ar'
as = '$NDK/llvm-as'
c = ['ccache', '$NDK/aarch64-linux-android$SDK_VER-clang']
cpp = ['ccache', '$NDK/aarch64-linux-android$SDK_VER-clang++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$NDK/llvm-strip'
# Android doesn't come with a pkg-config, but we need one for Meson to be happy not
# finding all the optional deps it looks for.  Use system pkg-config pointing at a
# directory we get to populate with any .pc files we want to add for Android
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

	export PKG_CONFIG_LIBDIR="$WORK_DIR"/output/lib/pkgconfig
}

build_zlib_for_android() {
	echo -e "${Blue}- Compiling zlib for android ..."
	cd "$WORK_DIR"/zlib

	CC=$NDK/aarch64-linux-android$SDK_VER-clang \
		CXX=$NDK/aarch64-linux-android$SDK_VER-clang++ \
		AR=$NDK/llvm-ar \
		LD=lld \
		AS=$NDK/llvm-as \
		STRIP=$NDK/llvm-strip \
		./configure \
		--static \
		--prefix="$WORK_DIR"/output \
		--libdir="$WORK_DIR"/output/lib

	make
	make install
}

build_lz4_for_android() {
	echo -e "${Blue}- Compiling lz4 for android ..."
	cd "$WORK_DIR"/lz4/build/meson

	meson setup build-android-aarch64 \
		--cross-file $WORK_DIR/android-aarch64 \
		--buildtype=release \
		--prefix="$WORK_DIR"/output \
		--libdir=lib \
		-Ddefault_library=static \
		-Dprograms=true

	meson compile -C build-android-aarch64
	meson install -C build-android-aarch64
}

build_xz_for_android() {
	echo -e "${Blue}- Compiling xz for android ..."
	cd "$WORK_DIR"/xz

	sudo apt-get install autopoint -y
	./autogen.sh

	CC=$NDK/aarch64-linux-android$SDK_VER-clang \
		CXX=$NDK/aarch64-linux-android$SDK_VER-clang++ \
		AR=$NDK/llvm-ar \
		LD=lld \
		AS=$NDK/llvm-as \
		STRIP=$NDK/llvm-strip \
		./configure \
		--host=aarch64-linux-android \
		--target=aarch64-linux-android \
		--enable-static \
		--with-pic \
		--disable-xz \
		--disable-xzdec \
		--disable-lzmainfo \
		--disable-scripts \
		--disable-lzmadec \
		--disable-shared \
		--prefix="$WORK_DIR"/output \
		--libdir="$WORK_DIR"/output/lib

	make
	make install
}

build_zstd_for_android() {
	echo -e "${Blue}- Compiling zstd for android ..."
	cd "$WORK_DIR"/zstd/build/meson

	meson setup build-android-aarch64 \
		--cross-file $WORK_DIR/android-aarch64 \
		--prefix="$WORK_DIR"/output \
		--libdir=lib \
		-Ddefault_library=static \
		-Dbin_programs=true \
		-Dbin_contrib=true \
		-Dmulti_thread=enabled \
		-Dzlib="$ZLIB_ENABLED" \
		-Dlz4="$LZ4_ENABLED" \
		-Dlzma="$XZ_ENABLED"

	meson compile -C build-android-aarch64
	meson install -C build-android-aarch64
}

run_all
