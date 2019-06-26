#!/bin/bash

func_generate() {
	local rootfs=$1
	local kdir=$2

	[ ! -f "$rootfs" ] && echo "${os} rootfs file not found!" && return 1
	[ ! -d "$kdir" ] && echo "kernel dir not found!" && return 1

	# create ext4 rootfs img
	mkdir -p ${tmpdir}
	echo "create ext4 rootfs, size: ${rootsize}M"
	dd if=/dev/zero bs=1M status=none count=$rootsize of=$tmpdir/rootfs.bin
	mkfs.ext4 -q -m 2 $tmpdir/rootfs.bin

	# mount rootfs
	mkdir -p $rootfs_mount_point
	mount -o loop $tmpdir/rootfs.bin $rootfs_mount_point

	# extract rootfs
	mkdir -p $rootfs_mount_point
	echo "extract ${os} rootfs($rootfs) to $rootfs_mount_point"
	if [ $os = "archlinux" ]; then
		tarbin="bsdtar"
	else
		tarbin="tar"
	fi
	$tarbin -xpf $rootfs -C $rootfs_mount_point

	# configure binfmt
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

	cp ./tools/${os}/init.sh $rootfs_mount_point/init.sh

	# prepare for chroot
	chroot_prepare

	# chroot
	echo "chroot to ${os} rootfs"
	LANG=C LC_ALL=C chroot $rootfs_mount_point /init.sh

	# clean rootfs
	rm -f $rootfs_mount_point/init.sh
	[ -n "$qemu" ] && rm -f $rootfs_mount_point/$qemu || rm -f $rootfs_mount_point/usr/bin/qemu-aarch64-static

	# add resize script
	add_resizemmc

	# add /lib/modules
	echo "add /lib/modules"
	tar xf $kdir/modules.tar.xz --strip-components 1 -C $rootfs_mount_point/lib

	# chroot post
	chroot_post

	chown -R root:root $rootfs_mount_point
	umount $rootfs_mount_point
	echo "generate ${os} rootfs done"

}

func_release() {
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

	mkdir -p $output/${os}
	cp -f $tmpdir/install.img $output/${os}
	cp -f blob/bpi-w2/rescue.emmc.dtb $output/${os}
	cp -f blob/bpi-w2/rescue.root.emmc.cpio.gz_pad.img $output/${os}
	cp -f blob/bpi-w2/emmc.uImage $output/${os}

	rm -rf $tmpdir
	if [ -n "$TRAVIS_TAG" ]; then
		tar cf $output/${os}/${os}.tar \
			-C $cur_dir/$output/${os} \
				install.img \
				rescue.emmc.dtb \
				rescue.root.emmc.cpio.gz_pad.img \
				emmc.uImage
		xz -v -f -T0 $output/${os}/${os}.tar
		mkdir -p $output/release
		mv -f $output/${os}/${os}.tar.xz $output/release/"$(gen_new_name $rootfs)"
	fi
	echo "release ${os} image done"
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
