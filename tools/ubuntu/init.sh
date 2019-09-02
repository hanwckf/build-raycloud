#!/bin/sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts

export DEBIAN_FRONTEND=noninteractive
apt_arg='-qq -y -o Dpkg::Progress-Fancy="0"'

cat <<EOF > ./usr/sbin/policy-rc.d
#!/bin/sh
exit 101

EOF

chmod +x ./usr/sbin/policy-rc.d

apt $apt_arg update && apt $apt_arg upgrade

if [ "$BUILD_MINIMAL" = "y" ]; then
	echo "Build minimal ubuntu"
	apt $apt_arg install ubuntu-minimal ubuntu-standard
else
	yes | unminimize
fi

apt $apt_arg install net-tools openssh-server dialog cpufrequtils haveged
apt -f $apt_arg install
apt $apt_arg purge irqbalance ureadahead unattended-upgrades && apt $apt_arg autoremove
apt clean

systemctl enable systemd-networkd
systemctl disable ondemand
systemctl set-default multi-user.target

cat <<EOF > ./etc/default/cpufrequtils
ENABLE=true
GOVERNOR=ondemand

EOF

cat <<EOF > ./etc/netplan/default.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: yes
      dhcp6: yes

EOF

cat <<EOF > ./etc/udev/rules.d/99-hdparm.rules
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sataa", RUN+="/sbin/hdparm -S 120 /dev/sataa"
ACTION=="add", SUBSYSTEM=="block", KERNEL=="satab", RUN+="/sbin/hdparm -S 120 /dev/satab"

EOF

echo "en_US.UTF-8 UTF-8" > ./etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > ./etc/default/locale
ln -sf /usr/share/zoneinfo/Asia/Shanghai ./etc/localtime
sed -i '/^#PermitRootLogin/cPermitRootLogin yes' ./etc/ssh/sshd_config
sed -i '/^#NTP/cNTP=time1.aliyun.com 2001:470:0:50::2' ./etc/systemd/timesyncd.conf
sed -i 's/ENABLED=1/ENABLED=0/' ./etc/default/motd-news
ln -sf /lib/systemd/system/getty@.service ./etc/systemd/system/getty.target.wantsgetty@ttyS0.service
echo "/dev/root / ext4 defaults,noatime,nodiratime,errors=remount-ro 0 1" >> ./etc/fstab
echo "blacklist 8822bs" > ./etc/modprobe.d/disable-8822bs.conf
echo "raycloud" > ./etc/hostname
echo "root:admin" |chpasswd

rm -rf ./var/cache
rm -rf ./var/lib/apt/*
rm -f ./usr/sbin/policy-rc.d

umount /dev/pts
umount /sys
umount /proc
