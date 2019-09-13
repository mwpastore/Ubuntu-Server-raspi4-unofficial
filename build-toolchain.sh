#!/bin/bash
set -euo pipefail
IFS=$'\t\n'

if [[ -z ${1:-} || -n ${2:-} ]] ; then
  echo "usage: $0 {arm64,..}" >&2
  exit 1
fi

ARCH=$1

source bootstrap.sh

mkdir -p "$TOOLCHAIN/src"

pushd "$TOOLCHAIN/src"

mkdir -p binutils-${BINUTILS_VER}-build
pushd binutils-${BINUTILS_VER}-build
$COMMON/src/binutils-${BINUTILS_VER}/configure \
  --prefix="$TOOLCHAIN" \
  --target=$TARGET \
  --disable-nls
make -j4
make install
popd

mkdir -p gcc-${GCC_VER}-build
pushd gcc-${GCC_VER}-build
$COMMON/src/gcc-${GCC_VER}/configure \
  --prefix="$TOOLCHAIN" \
  --target=$TARGET \
  --with-newlib \
  --without-headers \
  --disable-nls \
  --disable-shared \
  --disable-threads \
  --disable-libssp \
  --disable-decimal-float \
  --disable-libquadmath \
  --disable-libvtv \
  --disable-libgomp \
  --disable-libatomic \
  --enable-languages=c
make -j4 all-gcc
make install-gcc
popd

# leaving toolchain/src
popd

exit
