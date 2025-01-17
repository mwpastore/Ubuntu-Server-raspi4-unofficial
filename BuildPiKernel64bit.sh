
sudo apt-get install build-essential libgmp-dev libmpfr-dev libmpc-dev libssl-dev bison flex

# TOOLCHAIN

cd ~
mkdir -p toolchains/aarch64
cd toolchains/aarch64

export TOOLCHAIN=`pwd`

cd "$TOOLCHAIN"
wget https://ftp.gnu.org/gnu/binutils/binutils-2.32.tar.bz2
tar -xf binutils-2.32.tar.bz2
mkdir binutils-2.32-build
cd binutils-2.32-build
../binutils-2.32/configure --prefix="$TOOLCHAIN" --target=aarch64-linux-gnu --disable-nls
make -j4
make install

cd "$TOOLCHAIN"
wget https://ftp.gnu.org/gnu/gcc/gcc-9.2.0/gcc-9.2.0.tar.gz
tar -xf gcc-9.2.0.tar.gz
mkdir gcc-9.2.0-build
cd gcc-9.2.0-build
../gcc-9.2.0/configure --prefix="$TOOLCHAIN" --target=aarch64-linux-gnu --with-newlib --without-headers --disable-nls --disable-shared --disable-threads --disable-libssp --disable-decimal-float --disable-libquadmath --disable-libvtv --disable-libgomp --disable-libatomic --enable-languages=c
make all-gcc -j4
make install-gcc


# BUILD RPI TOOLS FOR ARMSTUB8

cd ~
git clone https://github.com/raspberrypi/tools.git rpi-tools
cd rpi-tools/armstubs
git checkout 7f4a937e1bacbc111a22552169bc890b4bb26a94
PATH=$PATH:$TOOLCHAIN/bin make armstub8-gic.bin


# GET FIRMWARE NON-FREE

cd ~
sudo rm -rf firmware-nonfree
git clone https://github.com/RPi-Distro/firmware-nonfree firmware-nonfree
cd firmware-nonfree
git pull

# BUILD KERNEL

# % Check out the 4.19.y kernel branch -- if building and future versions are available you can update which branch is checked out here
cd ~
git clone https://github.com/raspberrypi/linux.git rpi-linux --single-branch --branch rpi-4.19.y
cd rpi-linux
git checkout origin/rpi-4.19.y

# % Simple check to make sure we are sudod, gives a chance to catch and Ctrl+C or enter sudo password before continuing
sudo echo "hello"
sudo fstrim -av
cd ~/toolchains/aarch64
export TOOLCHAIN=`pwd`
cd ~

# % This is just a convenience stub to let you export the KERNEL_VERSION quickly if you have already built the kernel and are manually running later steps, otherwise it does nothing
cd ~/rpi-linux
export KERNEL_VERSION=`cat ./kernel-build/include/generated/utsrelease.h | sed -e 's/.*"\(.*\)".*/\1/'`
cd ~

# CONFIGURE / MAKE

cd ~/rpi-linux
PATH=$PATH:$TOOLCHAIN/bin make O=./kernel-build/ ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-  bcm2711_defconfig
cd kernel-build
# % Get conform_config.sh from sakaki-'s prebuilt 64 bit Raspberry Pi kernel modifications - https://github.com/sakaki-/bcm2711-kernel-bis
rm -f conform_config.sh
wget https://raw.githubusercontent.com/sakaki-/bcm2711-kernel-bis/master/conform_config.sh
chmod +x conform_config.sh
./conform_config.sh
rm conform_config.sh
cd ~/rpi-linux
# % If you want to change options, use the line below to enter the menuconfig kernel utility and configure your own kernel config flags
#PATH=$PATH:$TOOLCHAIN/bin make O=./kernel-build/ ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-  menuconfig
# % The line below starts the kernel build
PATH=$PATH:$TOOLCHAIN/bin make -j4 O=./kernel-build/ ARCH=arm64 DTC_FLAGS="-@ -H epapr" CROSS_COMPILE=aarch64-linux-gnu-
export KERNEL_VERSION=`cat ./kernel-build/include/generated/utsrelease.h | sed -e 's/.*"\(.*\)".*/\1/'`
# Creates /lib/modules/${KERNEL_VERSION} that we will install into our Ubuntu image so our custom kernel has all the modules needed available
make -j4 O=./kernel-build/ DEPMOD=echo MODLIB=./kernel-install/lib/modules/${KERNEL_VERSION} INSTALL_FW_PATH=./kernel-install/lib/firmware modules_install
depmod --basedir ./kernel-build/kernel-install "${KERNEL_VERSION}"
export KERNEL_BUILD_DIR=`realpath ./kernel-build`
cd ~

# MOUNT IMAGE

xzcat ubuntu-18.04.3-preinstalled-server-arm64+raspi3.img.xz > ubuntu-18.04.3-preinstalled-server-arm64+raspi4.img
MountXZ=$(sudo kpartx -av ubuntu-18.04.3-preinstalled-server-arm64+raspi4.img)
MountXZ=$(echo "$MountXZ" | awk 'NR==1{ print $3 }')
MountXZ="${MountXZ%p1}"
echo "Using loop $MountXZ"

# % Mount the image on /mnt (rootfs) and /mnt/boot/firmware (bootfs)
sudo mount /dev/mapper/"${MountXZ}"p2 /mnt
sudo rm -rf /mnt/boot/firmware/*
sudo mount /dev/mapper/"${MountXZ}"p1 /mnt/boot/firmware

# % Clean out old firmware, kernel and modules that don't support RPI 4
sudo rm -rf /mnt/boot/firmware/*
sudo rm -rf /mnt/usr/src/*
sudo rm -rf /mnt/lib/modules/*

sudo rm -rf /mnt/boot/initrd*
sudo rm -rf /mnt/boot/config*
sudo rm -rf /mnt/boot/vmlinuz*
sudo rm -rf /mnt/boot/System.map*

# % After we've cleaned some files off the image run a e4defrag to optimize disk img
sudo e4defrag /mnt/*

# % Copy bootfiles folder -- to create the bootfiles folder just copy the files from /boot from the precompiled image right into bootfiles -- they are mostly static
sudo cp -rvf bootfiles/* /mnt/boot/firmware

# % Copy newly compiled kernel, stubs, overlays, etc to Ubuntu image
sudo mkdir /mnt/boot/firmware/overlays
sudo cp -vf rpi-linux/kernel-build/arch/arm64/boot/dts/broadcom/*.dtb /mnt/boot/firmware
sudo cp -vf rpi-linux/kernel-build/arch/arm64/boot/dts/overlays/*.dtb* /mnt/boot/firmware/overlays
sudo cp -vf rpi-linux/kernel-build/arch/arm64/boot/Image /mnt/boot/firmware/kernel8.img
sudo cp -vf rpi-tools/armstubs/armstub8-gic.bin /mnt/boot/firmware/armstub8-gic.bin
sudo cp -vf rpi-linux/kernel-build/vmlinux /mnt/boot/vmlinuz-"${KERNEL_VERSION}"
sudo cp -vf rpi-linux/kernel-build/arch/arm64/boot/Image /mnt/boot/initrd.img-"${KERNEL_VERSION}"
sudo cp -vf rpi-linux/kernel-build/System.map /mnt/boot/System.map-"${KERNEL_VERSION}"
sudo cp -vf rpi-linux/kernel-build/.config /mnt/boot/config-"${KERNEL_VERSION}"
# % Create symlinks to our custom kernel -- this allows initramfs to find our kernel and update modules successfully
sudo ln -s /mnt/boot/vmlinuz-"${KERNEL_VERSION}" /mnt/boot/vmlinuz
sudo ln -s /mnt/boot/initrd.img-"${KERNEL_VERSION}" /mnt/boot/initrd.img

# % Remove initramfs actions for invalid existing kernels, then create a new link to our new custom kernel
sudo rm /mnt/var/lib/initramfs-tools/*
sha1sum=$(sha1sum  /mnt/boot/initrd.img-${KERNEL_VERSION})
echo "$sha1sum  /boot/vmlinuz-${KERNEL_VERSION}" | sudo -A tee -a /mnt/var/lib/initramfs-tools/"${KERNEL_VERSION}" >/dev/null;

# % Copy the new kernel modules to the Ubuntu image
sudo mkdir /mnt/lib/modules/${KERNEL_VERSION}
sudo cp -ravf rpi-linux/kernel-build/kernel-install/* /mnt

# % Copy latest firmware to Ubuntu image
sudo rm -rf firmware-nonfree/.git
sudo cp -ravf firmware-nonfree/* /mnt/lib/firmware

# % Copy System.map, kernel .config and Module.symvers to Ubuntu image
sudo cp -vf rpi-linux/kernel-build/System.map /mnt/boot/firmware
sudo cp -vf rpi-linux/kernel-build/Module.symvers /mnt/boot/firmware
sudo cp -vf rpi-linux/kernel-build/.config /mnt/boot/firmware/config

# % Perform one more defrag after installing our new modules and firmware
sudo e4defrag /mnt/*

# QUIRKS

# % Fix WiFi
# % The Pi 4 version returns boardflags3=0x44200100
# % The Pi 3 version returns boardflags3=0x48200100cd
sudo sed -i "s:0x48200100:0x44200100:g" /mnt/lib/firmware/brcm/brcmfmac43455-sdio.txt

# % Remove flash-kernel hooks to prevent firmware updater from overriding our custom firmware
sudo rm -f /mnt/etc/kernel/postinst.d/zz-flash-kernel
sudo rm -f /mnt/etc/kernel/postrm.d/zz-flash-kernel
sudo rm -f /mnt/etc/initramfs/post-update.d/flash-kernel

# % Create symlink to fix Bluetooth firmware bug
sudo ln -s /mnt/lib/firmware /mnt/etc/firmware

# % Disable ib_iser iSCSI cloud module to prevent an error during systemd-modules-load at boot
sudo sed -i "s/ib_iser/#ib_iser/g" /mnt/lib/modules-load.d/open-iscsi.conf
sudo sed -i "s/iscsi_tcp/#iscsi_tcp/g" /mnt/lib/modules-load.d/open-iscsi.conf

# % Fix update-initramfs mdadm.conf warning
grep "ARRAY devices" /mnt/etc/mdadm/mdadm.conf >/dev/null || echo "ARRAY devices=/dev/sda" | sudo -A tee -a /mnt/etc/mdadm/mdadm.conf >/dev/null;

# CHROOT

sudo cp extras/*.deb /mnt/
sudo cp -f /usr/bin/qemu-aarch64-static /mnt/usr/bin

# % Install new kernel modules

sudo mkdir -p /mnt/run/systemd/resolve
cat /run/systemd/resolve/stub-resolv.conf | sudo -A tee /mnt/run/systemd/resolve/stub-resolv.conf >/dev/null;
sudo touch /mnt/etc/modules-load.d/cups-filters.conf

# % Enter Ubuntu image chroot
sudo chroot /mnt /bin/bash

# % Run depmod from the chroot to make sure all new kernel modules get picked up
Version=$(ls /lib/modules | xargs)
echo "Kernel modules version: $Version"
depmod -a "$Version"

# % Add updated mesa repository for video driver support
add-apt-repository ppa:ubuntu-x-swat/updates -y

# % Update all software to current from Ubuntu apt repositories
apt update && apt dist-upgrade -y

# % Update initramfs
apt-mark hold flash-kernel linux-raspi2 linux-image-raspi2 linux-headers-raspi2 linux-firmware-raspi2
update-initramfs -u

# % INSTALL HAVAGED - prevents low entropy from making the Pi take a long time to start up.
dpkg -i libhavege1_1.9.1-6_arm64.deb
dpkg -i haveged_1.9.1-6_arm64.deb
rm -f *.deb

# % Remove ureadahead, does not support arm and makes our bootup unclean when checking systemd status
apt remove ureadahead libnih1 -y

# % Clean up after ourselves and clean out package cache to keep the image small
apt autoremove -y && apt clean && apt autoclean

# % Finished, exit
exit

# UNMOUNT AND SAVE CHANGES TO IMAGE

sudo umount /mnt/boot/firmware
sudo umount /mnt
sudo kpartx -dv ubuntu-18.04.3-preinstalled-server-arm64+raspi4.img
sudo losetup -d /dev/$MountXZ
