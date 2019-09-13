#!/bin/bash
set -euo pipefail
IFS=$'\t\n'

declare -A ARCHMAP=(
  [arm64]=aarch64
)

declare -A DEFCONFIG=(
  [raspi4]=bcm2711
)

declare -A GITHUB=(
  [rpi-tools]=raspberrypi/tools
  [rpi-firmware]=RPi-Distro/firmware-nonfree
  [rpi-kernel]=raspberrypi/linux
)

declare -a GNU_KEY_IDS=("0x13FCEF89DD9E3C4F" "0xA328C3A2C3C45C06")
BINUTILS_VER=2.32
GCC_VER=9.2.0

KERNEL_SRC_VER=4.19.y
RPI_TOOLS_COMMITISH=7f4a937e1bacbc111a22552169bc890b4bb26a94

declare -a UBUNTU_KEY_IDS=("0x46181433FBB75451" "0xD94AA3F0EFE21092")
UBUNTU_VER=18.04.3
SEED_MODEL=raspi3

# Try not to change anything below this line...

function get_kernel_version {
  [[ -n ${KERNEL_BUILD_DIR:-} ]] && sed -n 's/.*"\(.*\)".*/\1/p' $KERNEL_BUILD_DIR/include/generated/utsrelease.h
}

mkdir -p work

COMMON=$(realpath work/common)

if [[ -n ${ARCH:-} ]] ; then
  TARGET=${ARCHMAP[$ARCH]}-linux-gnu
fi

if [[ -n ${TARGET:-} ]] ; then
  TOOLCHAIN=$(realpath work/$TARGET)
fi

if [[ -n ${KEY:-} ]] ; then
  mkdir -p "work/$KEY/src"

  KERNEL_BUILD_DIR=$(realpath "work/$KEY/src/kernel-build")

  KERNEL_HEADERS_DIR=$(realpath "work/$KEY/kernel-headers")
  KERNEL_MODULES_DIR=$(realpath "work/$KEY/kernel-modules")
fi

if [[ -n ${MODEL:-} ]] ; then
  SOC=${DEFCONFIG[$MODEL]}
fi

KEYRING=$(realpath work/trustedkeys.kbx)

function trust {
  gpg --no-default-keyring --armor --export $1 |
    gpg --no-default-keyring --keyring $KEYRING --import -
}

return
