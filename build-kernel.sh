#!/bin/bash
set -euo pipefail
IFS=$'\t\n'

if [[ -z ${3:-} || -n ${4:-} ]] ; then
  echo "usage: $0 {raspi4,..} {arm64,..} <build key>" >&2
  exit 1
fi

MODEL=$1
ARCH=$2
KEY=$3

source bootstrap.sh

pushd "work/$KEY/src"

# BUILD RPI TOOLS FOR ARMSTUB8

[[ -d rpi-tools ]] ||
  git clone --shared --no-checkout $COMMON/src/rpi-tools

pushd rpi-tools
git fetch --prune origin
git checkout $RPI_TOOLS_COMMITISH
pushd armstubs
PATH="$TOOLCHAIN/bin:$PATH" make armstub8-gic.bin
popd
popd

# GET FIRMWARE NON FREE

[[ -d rpi-firmware ]] ||
  git clone --shared --branch=master $COMMON/src/rpi-firmware

git -C rpi-firmware pull --rebase --autostash

# BUILD KERNEL

[[ -d rpi-kernel ]] ||
  git clone --shared --branch=rpi-$KERNEL_SRC_VER $COMMON/src/rpi-kernel-$KERNEL_SRC_VER rpi-kernel

pushd rpi-kernel

git pull --rebase --autostash

# CONFIGURE / MAKE

function kmake {
  PATH="$TOOLCHAIN/bin:$PATH" make O="$KERNEL_BUILD_DIR" ARCH=$ARCH CROSS_COMPILE=${TARGET}- "$@"
}

kmake ${SOC}_defconfig

pushd "$KERNEL_BUILD_DIR"
if [[ $ARCH = "arm64" ]] ; then
  # % Get conform_config.sh from sakaki-'s prebuilt 64-bit Raspberry Pi kernel modifications
  bash < <(curl -qfsS -o- https://raw.githubusercontent.com/sakaki-/${SOC}-kernel-bis/master/conform_config.sh)
fi
popd

# % If you want to change options, uncomment the lines below to enter the menuconfig kernel utility and configure your own kernel config flags
#PATH="$TOOLCHAIN/bin:$PATH" make O="$KERNEL_BUILD_DIR" \
#  ARCH=$ARCH \
#  CROSS_COMPILE=${TARGET}- \
#  menuconfig

# % The line below starts the kernel build
kmake -j4 DTC_FLAGS="-@ -H epapr" Image modules dtbs

kmake INSTALL_MOD_PATH="$KERNEL_MODULES_DIR" modules_install
kmake INSTALL_HDR_PATH="$KERNEL_HEADERS_DIR" headers_install

# leaving rpi-kernel
popd

# leaving work/KEY/src
popd

exit
