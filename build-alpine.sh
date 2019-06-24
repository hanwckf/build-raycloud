#!/bin/bash

[ "$EUID" != "0" ] && echo "please run as root" && exit 1

rootfs_mount_point="/mnt/alpine_rootfs"
tmpdir="tmp"
output="output"
qemu_static="./tools/qemu/qemu-aarch64-static"
rootsize=700
cur_dir=$(pwd)
DTB=rtd-1296-raycloud-2GB.dtb

origin="minirootfs"
target="raycloud"

func_generate() {
	local rootfs=$1
	local kdir=$2

	[ ! -f "$rootfs" ] && echo "alpine rootfs file not found!" && return 1
	[ ! -d "$kdir" ] && echo "kernel dir not found!" && return 1

	# create ext4 rootfs img
	mkdir -p ${tmpdir}
	echo "create ext4 rootfs, size: ${rootsize}M"
	dd if=/dev/zero bs=1M status=none count=$rootsize of=$tmpdir/rootfs.bin
	mkfs.ext4 -q -m 2 $tmpdir/rootfs.bin

	# mount rootfs
	mkdir -p $rootfs_mount_point
	mount -o loop $tmpdir/rootfs.bin $rootfs_mount_point

	# extract alpine rootfs
	mkdir -p $rootfs_mount_point
	echo "extract alpine rootfs($rootfs) to $rootfs_mount_point"
	tar -xpf $rootfs -C $rootfs_mount_point

	# change mirrors
	if [ -z "$TRAVIS" ]; then
		sed -i 's#http://dl-cdn.alpinelinux.org#https://mirrors.tuna.tsinghua.edu.cn#' $rootfs_mount_point/etc/apk/repositories
		echo "nameserver 119.29.29.29" > $rootfs_mount_point/etc/resolv.conf
	else
		echo "nameserver 8.8.8.8" > $rootfs_mount_point/etc/resolv.conf
	fi

	# chroot to alpine rootfs
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

	cp ./tools/alpine/init.sh $rootfs_mount_point/init.sh
	echo "chroot to alpine rootfs"
	LANG=C LC_ALL=C chroot $rootfs_mount_point /init.sh

	rm -f $rootfs_mount_point/init.sh
	[ -n "$qemu" ] && rm -f $rootfs_mount_point/$qemu || rm -f $rootfs_mount_point/usr/bin/qemu-aarch64-static

	if [ -n "$TRAVIS" ]; then
		sed -i 's#http://dl-cdn.alpinelinux.org#https://mirrors.tuna.tsinghua.edu.cn#' $rootfs_mount_point/etc/apk/repositories
	fi

	# add /lib/modules
	echo "add /lib/modules"
	tar xf $kdir/modules.tar.xz --strip-components 1 -C $rootfs_mount_point/lib

	# add resize script
	cp ./tools/alpine/resizemmc.sh $rootfs_mount_point/sbin/resizemmc.sh
	cp ./tools/alpine/resizemmc $rootfs_mount_point/etc/init.d/resizemmc
	ln -sf /etc/init.d/resizemmc $rootfs_mount_point/etc/runlevels/default/resizemmc
	touch $rootfs_mount_point/root/.need_resize

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

	mkdir -p $output/alpine
	cp -f $tmpdir/install.img $output/alpine
	cp -f blob/bpi-w2/rescue.emmc.dtb $output/alpine
	cp -f blob/bpi-w2/rescue.root.emmc.cpio.gz_pad.img $output/alpine
	cp -f blob/bpi-w2/emmc.uImage $output/alpine

	rm -rf $tmpdir
	if [ -n "$TRAVIS_TAG" ]; then
		tar cvf $output/alpine/alpine.tar \
			-C $cur_dir/$output/alpine \
				install.img \
				rescue.emmc.dtb \
				rescue.root.emmc.cpio.gz_pad.img \
				emmc.uImage
		xz -v -f -T0 $output/alpine/alpine.tar
		imgname_new="`basename $rootfs | sed "s/${origin}/${target}/" | sed 's/.gz$/.xz/'`"
		mv $output/alpine/alpine.tar.xz $output/alpine/$imgname_new
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
