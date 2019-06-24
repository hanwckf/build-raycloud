#!/bin/sh

resize2fs /dev/mmcblk2p1 && echo "resize done, please reboot" || echo "resize failed!"
