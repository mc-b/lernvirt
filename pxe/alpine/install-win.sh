#!/bin/sh

echo "=== Windows ISO Flash Initramfs ==="

# ------------------------------------------------------------
# Parameter aus Kernel-Commandline lesen
# ------------------------------------------------------------

echo "[*] Kernel cmdline:"
cat /proc/cmdline

for x in $(cat /proc/cmdline); do
    case "$x" in
        iso_url=*)
            ISO_URL="${x#iso_url=}"
            ;;
        target=*)
            TARGET="${x#target=}"
            ;;
        debug=1)
            DEBUG=1
            ;;
    esac
done

# ------------------------------------------------------------
# Validierung
# ------------------------------------------------------------
if [ -z "$ISO_URL" ]; then
    echo "[ERROR] iso_url Parameter fehlt"
    exec sh
fi

# Automatische Disk-Erkennung falls kein target gesetzt
if [ -z "$TARGET" ]; then
    echo "[*] Kein target gesetzt – suche erste Disk"
    TARGET=$(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1; exit}')
fi

if [ ! -b "$TARGET" ]; then
    echo "[ERROR] Ungültiges Target: $TARGET"
    exec sh
fi

echo "[*] ISO_URL  = $ISO_URL"
echo "[*] TARGET   = $TARGET"
echo

# ------------------------------------------------------------
# ISO schreiben (Streaming)
# ------------------------------------------------------------

echo "https://dl-cdn.alpinelinux.org/alpine/v3.23/main"      >  /etc/apk/repositories
echo "https://dl-cdn.alpinelinux.org/alpine/v3.23/community" >> /etc/apk/repositories

apk update
apk add gptfdisk dosfstools util-linux wimlib sgdisk rsync ntfs-3g parted

sgdisk --zap-all /dev/nvme0n1
wipefs -a /dev/nvme0n1

# Eine GPT-Partition, Typ EFI, 11 GB 
sgdisk -n 1:1MiB:+11GiB -t 1:ef00 -c 1:"WIN11_EFI" $TARGET

partprobe /dev/nvme0n1 || blockdev --rereadpt /dev/nvme0n1

mdev -s
mkfs.vfat -F32 /dev/nvme0n1p1

# ------------------------------------------------------------
# Image holen
# ------------------------------------------------------------

wget -O win11.iso $ISO_URL

mkdir -p /mnt/iso
mount -o loop /root/win11.iso /mnt/iso

mkdir -p /mnt/usb
mount /dev/nvme0n1p1 /mnt/usb

rsync -rltD --no-perms --no-owner --no-group \
  --exclude=sources/install.wim \
  /mnt/iso/ /mnt/usb/
  
wimlib-imagex split \
  /mnt/iso/sources/install.wim \
  /mnt/usb/sources/install.swm 3800

sync
umount /mnt/iso
umount /mnt/usb

echo
echo "[*] Schreiben abgeschlossen"
echo "[*] Reboot in 5 Sekunden..."

sleep 5
#reboot -f
exec sh