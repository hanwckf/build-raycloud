#!/bin/sh

if [ -e /root/.need_resize ]; then 
	resize2fs /dev/mmcblk2p1 && echo "resize done, please reboot" || echo "resize failed!"
	rm -f /root/.need_resize
fi
