#!/bin/bash
set -euo pipefail
IFS=$'\t\n'

if [[ -z ${1:-} || -n ${2:-} ]] ; then
  echo "usage: $0 {arm64,..}" >&2
  exit 1
fi

ARCH=$1

source bootstrap.sh

gpg --refresh-keys

for key_id in ${GNU_KEY_IDS[@]} ; do
  gpg --list-keys $key_id >/dev/null 2>&1 ||
    gpg --keyserver hkp://keys.gnupg.net --receive-keys $key_id

  trust $key_id
done

for key_id in ${UBUNTU_KEY_IDS[@]} ; do
  gpg --list-keys $key_id >/dev/null 2>&1 ||
    gpg --keyserver hkp://keyserver.ubuntu.com --receive-keys $key_id

  trust $key_id
done

mkdir -p work/common/src

pushd work/common/src

if [[ ! -d binutils-$BINUTILS_VER ]] ; then
  echo " *** Fetching and extracting binutils..."
  curl -qfsS -O https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz.sig
  curl -qfsS -O http://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz
  gpgv binutils-${BINUTILS_VER}.tar.xz{.sig,}
  tar -xf binutils-${BINUTILS_VER}.tar.xz
  rm -f binutils-${BINUTILS_VER}.tar.xz{,.sig}
fi

if [[ ! -d gcc-$GCC_VER ]] ; then
  echo " *** Fetching and extracting gcc..."
  curl -qfsS -O https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-${GCC_VER}.tar.xz.sig
  curl -qfsS -O http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-${GCC_VER}.tar.xz
  gpgv --keyring $KEYRING gcc-${GCC_VER}.tar.xz{.sig,}
  tar -xf gcc-${GCC_VER}.tar.xz
  rm -f gcc-${GCC_VER}.tar.xz{,.sig}
fi

if [[ ! -d rpi-kernel-$KERNEL_SRC_VER ]] ; then
  git clone --bare --branch=rpi-$KERNEL_SRC_VER --depth=1 --no-tags \
    https://github.com/${GITHUB[rpi-kernel]}.git rpi-kernel-$KERNEL_SRC_VER
else
  echo " *** Updating kernel source..."
  git -C rpi-kernel-$KERNEL_SRC_VER fetch --depth=1 --no-tags \
    https://github.com/${GITHUB[rpi-kernel]}.git
fi

if [[ ! -d rpi-firmware ]] ; then
  git clone --bare --branch=master --depth=1 --no-tags \
    https://github.com/${GITHUB[rpi-firmware]}.git rpi-firmware
else
  echo " *** Updating firmware..."
  git -C rpi-firmware fetch --depth=1 --no-tags \
    https://github.com/${GITHUB[rpi-firmware]}.git
fi

if [[ ! -d rpi-tools ]] ; then
  git clone --bare --no-tags \
    https://github.com/${GITHUB[rpi-tools]}.git rpi-tools
else
  echo " *** Updating tools..."
  git -C rpi-tools fetch --no-tags \
    https://github.com/${GITHUB[rpi-tools]}.git
fi

popd

mkdir -p work/ubuntu

pushd work/ubuntu

# TODO: It is so dumb that Ubuntu does't let us download the .gpg over HTTPS.
curl -qfsS -OO http://cdimage.ubuntu.com/releases/$UBUNTU_VER/release/SHA256SUMS{,.gpg}
gpgv --keyring $KEYRING SHA256SUMS{.gpg,}

img=ubuntu-${UBUNTU_VER}-preinstalled-server-${ARCH}+${SEED_MODEL}.img

function checksum {
  sha256sum --check --status <(grep "$1" SHA256SUMS)
}

if ! checksum ${img}.xz ; then
  zsync http://cdimage.ubuntu.com/releases/$UBUNTU_VER/release/${img}.xz.zsync
  checksum ${img}.xz
  unxz -fk ${img}.xz
fi

rm -f ${img}.xz.zs-old SHA256SUMS{,.gpg}

popd

exit
