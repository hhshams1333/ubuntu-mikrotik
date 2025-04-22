#!/bin/bash

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# نصب ابزارهای لازم
sudo apt update
sudo apt install -y unzip kpartx parted coreutils

# دانلود فایل CHR
wget https://download.mikrotik.com/routeros/7.12/chr-7.12.img.zip -O chr.img.zip || {
    echo "Failed to download CHR image"
    exit 1
}

# استخراج فایل (غیرتعاملی)
unzip -o chr.img.zip || {
    echo "Failed to unzip CHR image"
    exit 1
}

# یافتن فایل استخراج‌شده
CHR_IMG=$(ls chr-*.img 2>/dev/null | head -n 1)
if [ -z "$CHR_IMG" ]; then
    echo "No CHR image file found"
    exit 1
fi

# تغییر نام به chr.img برای سازگاری
mv "$CHR_IMG" chr.img || {
    echo "Failed to rename CHR image"
    exit 1
}

# شناسایی پارتیشن‌ها با kpartx
sudo kpartx -av chr.img || {
    echo "Failed to map partitions"
    exit 1
}

# یافتن پارتیشن مناسب
PARTITION=$(ls /dev/mapper/loop*p1 2>/dev/null | head -n 1)
if [ -z "$PARTITION" ]; then
    echo "No suitable partition found"
    sudo kpartx -d chr.img
    exit 1
fi

# مانت کردن پارتیشن
sudo mkdir -p /mnt
sudo mount $PARTITION /mnt || {
    echo "Failed to mount CHR image on $PARTITION"
    sudo kpartx -d chr.img
    exit 1
}

# تنظیمات شبکه
INTERFACE=$(ip link | grep -v "lo:" | awk -F': ' '{print $2}' | head -n 1)
ADDRESS=$(ip addr show $INTERFACE | grep global | awk '{print $2}' | head -n 1)
GATEWAY=$(ip route list | grep default | awk '{print $3}')

# اعمال تنظیمات میکروتیک
echo "/ip address add address=$ADDRESS interface=[/interface ethernet find where name=ether1]
/ip route add gateway=$GATEWAY
/ip service disable telnet
/user set 0 name=root password=your_secure_password" > /mnt/rw/rc.d/rc.local

# سینک و نوشتن روی دیسک
echo u > /proc/sysrq-trigger
dd if=chr.img bs=1024 of=/dev/vda || {
    echo "Failed to write image to disk"
    exit 1
}
echo "Syncing disk"
echo s > /proc/sysrq-trigger

# تأخیر 5 ثانیه‌ای
echo "Sleep 5 seconds"
/bin/sleep 5 || ping -c 5 127.0.0.1 > /dev/null

# تمیز کردن
sudo umount /mnt
sudo kpartx -d chr.img

# ریبوت
echo "Ok, reboot"
echo b > /proc/sysrq-trigger
