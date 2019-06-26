#!/bin/sh

export PATH=/usr/sbin:/usr/bin:/bin:/sbin

# remove kernel packages
pacman -Rn --noconfirm linux-aarch64 linux-firmware

systemctl set-default multi-user.target

# set securetty
[ -z "`grep ttyS0 ./etc/securetty`" ] && echo "ttyS0" >> ./etc/securetty

# set /etc/fstab
[ -z "`grep mmcblk2p1 ./etc/fstab`" ] && echo "/dev/mmcblk2p1 / ext4 defaults,noatime,nodiratime,errors=remount-ro 0 1" >> ./etc/fstab

# set ntp server
sed -i '/^#NTP/cNTP=time1.aliyun.com 2001:470:0:50::2' ./etc/systemd/timesyncd.conf

# set sshd_config to allow root login
sed -i '/^#PermitRootLogin/cPermitRootLogin yes' ./etc/ssh/sshd_config

# set locale
echo 'en_US.UTF8 UTF-8' > ./etc/locale.gen
locale-gen
echo 'LANG=en_US.utf8' > ./etc/locale.conf
echo 'KEYMAP=us' > ./etc/vconsole.conf
ln -sf ../usr/share/zoneinfo/Asia/Shanghai ./etc/localtime

# change mirrors
echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo' > ./etc/pacman.d/mirrorlist

echo "blacklist 8822bs" > ./etc/modprobe.d/disable-8822bs.conf

echo "root:admin" |chpasswd

# clean
pacman -Sc --noconfirm
