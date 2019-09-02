#!/bin/sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# remove kernel packages
pacman -Rn --noconfirm linux-aarch64 linux-firmware

systemctl set-default multi-user.target

# set securetty
echo "ttyS0" >> ./etc/securetty

# set /etc/fstab
echo "/dev/root / ext4 defaults,noatime,nodiratime,errors=remount-ro 0 1" >> ./etc/fstab

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
echo "blacklist 8822bs" > ./etc/modprobe.d/disable-8822bs.conf
echo "root:admin" |chpasswd

pacman-key --init
pacman-key --populate archlinuxarm

sed -i 's/CheckSpace/#CheckSpace/' ./etc/pacman.conf
pacman -Sy --noconfirm hdparm
sed -i 's/#CheckSpace/CheckSpace/' ./etc/pacman.conf

cat <<EOF > ./etc/udev/rules.d/99-hdparm.rules
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sataa", RUN+="/usr/bin/hdparm -S 120 /dev/sataa"
ACTION=="add", SUBSYSTEM=="block", KERNEL=="satab", RUN+="/usr/bin/hdparm -S 120 /dev/satab"

EOF

# clean
pacman -Sc --noconfirm
rm -rf ./etc/pacman.d/gnupg
killall -9 gpg-agent

umount /dev
umount /sys
umount /proc
