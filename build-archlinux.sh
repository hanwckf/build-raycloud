#!/bin/bash

# run following command to init pacman keyring:
# pacman-key --init
# pacman-key --populate archlinuxarm

[ "$EUID" != "0" ] && echo "please run as root" && exit 1

rootfs_mount_point="/mnt/arch_rootfs"
tmpdir="tmp"
output="output"
qemu_static="./tools/qemu/qemu-aarch64-static"
rootsize=1500
cur_dir=$(pwd)
DTB=rtd-1296-raycloud-2GB.dtb

origin="latest"
target="raycloud-$(date +%Y-%m-%d)"

func_generate() {
	local rootfs=$1
	local kdir=$2

	[ ! -f "$rootfs" ] && echo "archlinux rootfs file not found!" && return 1
	[ ! -d "$kdir" ] && echo "kernel dir not found!" && return 1
	# create ext4 rootfs img
	mkdir -p ${tmpdir}
	echo "create ext4 rootfs, size: ${rootsize}M"
	dd if=/dev/zero bs=1M status=none count=$rootsize of=$tmpdir/rootfs.bin
	mkfs.ext4 -q -m 2 $tmpdir/rootfs.bin

	# mount rootfs
	mkdir -p $rootfs_mount_point
	mount -o loop $tmpdir/rootfs.bin $rootfs_mount_point

	# extract archlinux rootfs
	mkdir -p $rootfs_mount_point
	echo "extract archlinux rootfs($rootfs) to $rootfs_mount_point"
	bsdtar -xpf $rootfs -C $rootfs_mount_point

	# chroot to archlinux rootfs
	echo "configure binfmt to chroot"
	modprobe binfmt_misc
	if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
		qemu="`grep 'interpreter' /proc/sys/fs/binfmt_misc/qemu-aarch64 |cut -d ' ' -f2`"
		echo "copy $qemu to $rootfs_mount_point/$qemu"
		cp $qemu $rootfs_mount_point/$qemu
	elif [ -e /proc/sys/fs/binfmt_misc/register ]; then
		echo -1 > /proc/sys/fs/binfmt_misc/status
		echo ":arm64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OC" > /proc/sys/fs/binfmt_misc/register
		echo "copy $qemu_static to $rootfs_mount_point/usr/bin/"
		cp $qemu_static $rootfs_mount_point/usr/bin/qemu-aarch64-static
	else
		echo "Could not configure binfmt for qemu!" && exit 1
	fi

	cp ./tools/archlinux/init.sh $rootfs_mount_point/init.sh
	echo "chroot to archlinux rootfs"
	LANG=C LC_ALL=C chroot $rootfs_mount_point /init.sh

	rm -f $rootfs_mount_point/init.sh
	[ -n "$qemu" ] && rm -f $rootfs_mount_point/$qemu || rm -f $rootfs_mount_point/usr/bin/qemu-aarch64-static

	# add resize script
	echo "add resize mmc script"
	cp ./tools/archlinux/resizemmc.service $rootfs_mount_point/lib/systemd/system/
	cp ./tools/archlinux/resizemmc.sh $rootfs_mount_point/sbin/
	mkdir -p $rootfs_mount_point/etc/systemd/system/basic.target.wants
	ln -sf /lib/systemd/system/resizemmc.service $rootfs_mount_point/etc/systemd/system/basic.target.wants/resizemmc.service
	touch $rootfs_mount_point/root/.need_resize

	# add /lib/modules
	echo "add /lib/modules"
	tar xf $kdir/modules.tar.xz --strip-components 1 -C $rootfs_mount_point/lib

	chown -R root:root $rootfs_mount_point
	umount $rootfs_mount_point

}

func_release(){
	local rootfs=$1
	local kdir=$2

	func_generate $rootfs $kdir

	tar cf $tmpdir/install.img \
		-C $cur_dir/blob/bpi-w2 \
			install_a \
		-C $cur_dir/config \
			config.txt \
		-C $cur_dir/$kdir \
			$DTB \
			Image \
		-C $cur_dir/$tmpdir \
			rootfs.bin

	mkdir -p $output/archlinux
	cp -f $tmpdir/install.img $output/archlinux
	cp -f blob/bpi-w2/rescue.emmc.dtb $output/archlinux
	cp -f blob/bpi-w2/rescue.root.emmc.cpio.gz_pad.img $output/archlinux
	cp -f blob/bpi-w2/emmc.uImage $output/archlinux

	rm -rf $tmpdir
	if [ -n "$TRAVIS_TAG" ]; then
		tar cvf $output/archlinux/archlinux.tar \
			-C $cur_dir/$output/archlinux \
				install.img \
				rescue.emmc.dtb \
				rescue.root.emmc.cpio.gz_pad.img \
				emmc.uImage
		xz -v -f -T0 $output/archlinux/archlinux.tar
		imgname_new="`basename $rootfs | sed "s/${origin}/${target}/" | sed 's/.gz$/.xz/'`"
		mv $output/archlinux/archlinux.tar.xz $output/archlinux/$imgname_new
	fi
}

case "$1" in
generate)
	func_generate "$2" "$3"
	;;
release)
	func_release "$2" "$3"
	;;
*)
	echo "Usage: $0 { generate [rootfs] [KDIR] | release [rootfs] [KDIR] }"
	exit 1
	;;
esac
