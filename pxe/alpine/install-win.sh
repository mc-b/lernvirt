#!/bin/sh
set -e

echo "=== Windows ISO Flash Initramfs (UEFI) ==="
echo

# ------------------------------------------------------------
# Kernel-Parameter lesen
#   iso_url=...
#   target=/dev/nvme0n1   (optional)
#   debug=1               (optional)
# ------------------------------------------------------------

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

if [ -z "$ISO_URL" ]; then
    echo "[ERROR] iso_url Parameter fehlt"
    exec sh
fi

# ------------------------------------------------------------
# Interne SSD automatisch bestimmen (ohne lsblk)
# ------------------------------------------------------------

if [ -z "$TARGET" ]; then
    echo "[*] Suche interne SSD (non-removable)"

    for dev in /sys/block/*; do
        name=$(basename "$dev")

        case "$name" in
            loop*|ram*|fd*|sr*|dm-* )
                continue
                ;;
        esac

        [ -e "$dev/device" ] || continue

        # keine USB / SD (removable=1)
        if [ -f "$dev/removable" ] && [ "$(cat "$dev/removable")" = "1" ]; then
            continue
        fi

        case "$name" in
            nvme*|sd*)
                TARGET="/dev/$name"
                break
                ;;
        esac
    done
fi

if [ -z "$TARGET" ] || [ ! -b "$TARGET" ]; then
    echo "[ERROR] Keine interne SSD gefunden"
    exec sh
fi

echo "[*] ISO_URL = $ISO_URL"
echo "[*] TARGET  = $TARGET"
echo

# Partitionsname korrekt bilden
if echo "$TARGET" | grep -q "nvme"; then
    PART="${TARGET}p1"
else
    PART="${TARGET}1"
fi

# ------------------------------------------------------------
# Alpine Paketquellen setzen
# ------------------------------------------------------------

echo "https://dl-cdn.alpinelinux.org/alpine/v3.23/main"      >  /etc/apk/repositories
echo "https://dl-cdn.alpinelinux.org/alpine/v3.23/community" >> /etc/apk/repositories

apk update
apk add --no-cache gptfdisk dosfstools util-linux wimlib rsync wget

# ------------------------------------------------------------
# Disk vollständig neu initialisieren
# ------------------------------------------------------------

echo "[*] Lösche bestehende Partitionstabelle"
sgdisk --zap-all "$TARGET"
wipefs -a "$TARGET"

echo "[*] Erstelle GPT + EFI Partition (12 GiB FAT32)"
sgdisk -n 1:1MiB:+12GiB -t 1:ef00 -c 1:"WIN_EFI" "$TARGET"

partprobe "$TARGET" || true
sleep 2

mkfs.vfat -F32 "$PART"

# ------------------------------------------------------------
# ISO herunterladen
# ------------------------------------------------------------

echo "[*] Lade ISO..."
wget -O /tmp/windows.iso "$ISO_URL"

if [ ! -f /tmp/windows.iso ]; then
    echo "[ERROR] ISO Download fehlgeschlagen"
    exec sh
fi

# ------------------------------------------------------------
# Mount ISO und Zielpartition
# ------------------------------------------------------------

mkdir -p /mnt/iso
mkdir -p /mnt/usb

mount -o loop /tmp/windows.iso /mnt/iso
mount "$PART" /mnt/usb

# ------------------------------------------------------------
# Dateien kopieren (WIM Split wegen FAT32 Limit)
# ------------------------------------------------------------

echo "[*] Kopiere Installationsdateien"
rsync -rltD --no-perms --no-owner --no-group \
  --exclude=sources/install.wim \
  /mnt/iso/ /mnt/usb/

echo "[*] Splitte install.wim (FAT32 4GB Limit)"
wimlib-imagex split \
  /mnt/iso/sources/install.wim \
  /mnt/usb/sources/install.swm 3800

sync

#umount /mnt/iso
#umount /mnt/usb

echo
echo "[*] Windows Installationsmedium erstellt"
echo "[*] System wird neu gestartet..."

#sleep 5
#reboot -f
