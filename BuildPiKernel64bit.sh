#!/bin/bash
set -euo pipefail
IFS=$'\t\n'

MODEL=raspi4
ARCH=arm64
KEY=default

sudo ./install-prerequisites.sh
./gather-sources.sh $ARCH
./build-toolchain.sh $ARCH
./build-kernel.sh $MODEL $ARCH $KEY

# shiny happy filesystem
sudo fstrim -v . || true


# kernel, etc. for /boot
# armstub, overlays, kernel, etc. for /boot/firmware
# firmware non-free for /lib/firmware
# /lib/modules/$KERNEL_VERSION
# /var/lib/initramfs-tools/$KERNEL_VERSION w/ sha1sum

# % Copy bootfiles folder -- to create the bootfiles folder just copy the files from /boot from the precompiled image right into bootfiles -- they are mostly static
cp -rvf bootfiles/* /mnt/boot/firmware

# % Copy newly compiled kernel, stubs, overlays, etc to Ubuntu image
mkdir /mnt/boot/firmware/overlays
cp -vf $KERNEL_BUILD_DIR/arch/$ARCH/boot/dts/broadcom/*.dtb /mnt/boot/firmware
cp -vf $KERNEL_BUILD_DIR/arch/$ARCH/boot/dts/overlays/*.dtb* /mnt/boot/firmware/overlays
cp -vf $KERNEL_BUILD_DIR/arch/$ARCH/boot/Image /mnt/boot/firmware/kernel8.img
cp -vf rpi-tools/armstubs/armstub8-gic.bin /mnt/boot/firmware/armstub8-gic.bin
cp -vf $KERNEL_BUILD_DIR/vmlinux /mnt/boot/vmlinuz-"${KERNEL_VERSION}"
cp -vf $KERNEL_BUILD_DIR/arch/$ARCH/boot/Image /mnt/boot/initrd.img-"${KERNEL_VERSION}"
cp -vf $KERNEL_BUILD_DIR/System.map /mnt/boot/System.map-"${KERNEL_VERSION}"
cp -vf $KERNEL_BUILD_DIR/.config /mnt/boot/config-"${KERNEL_VERSION}"
# % Create symlinks to our custom kernel -- this allows initramfs to find our kernel and update modules successfully
ln -s /mnt/boot/vmlinuz-"${KERNEL_VERSION}" /mnt/boot/vmlinuz
ln -s /mnt/boot/initrd.img-"${KERNEL_VERSION}" /mnt/boot/initrd.img

# % Remove initramfs actions for invalid existing kernels, then create a new link to our new custom kernel
sha1sum=$(sha1sum  /mnt/boot/initrd.img-${KERNEL_VERSION})
echo "$sha1sum  /boot/vmlinuz-${KERNEL_VERSION}" | tee -a /mnt/var/lib/initramfs-tools/"${KERNEL_VERSION}" >/dev/null;

# % Copy the new kernel modules to the Ubuntu image
mkdir /mnt/lib/modules/${KERNEL_VERSION}
cp -ravf $KERNEL_INSTALL_DIR/* /mnt

git -C rpi-firmware archive --format=tar HEAD | tar -x -C /mnt/lib/firmware


# % Copy latest firmware to Ubuntu image
rm -rf firmware-nonfree/.git
cp -ravf firmware-nonfree/* /mnt/lib/firmware

# % Copy System.map, kernel .config and Module.symvers to Ubuntu image
cp -vf $KERNEL_BUILD_DIR/System.map /mnt/boot/firmware
cp -vf $KERNEL_BUILD_DIR/Module.symvers /mnt/boot/firmware
cp -vf $KERNEL_BUILD_DIR/.config /mnt/boot/firmware/config

# QUIRKS

# % Fix WiFi
# % The Pi 4 version returns boardflags3=0x44200100
# % The Pi 3 version returns boardflags3=0x48200100cd
if [[ $MODEL = "raspi4" ]] ; then
  boardflags3=
  sed -i "s:0x48200100:0x44200100:g" /mnt/lib/firmware/brcm/brcmfmac43455-sdio.txt
fi

# Notes for other script:
# extras directory
# qemu-arm-system
