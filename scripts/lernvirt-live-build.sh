#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# lernvirt-live-build.sh
#
# Baut aus einem installierten Ubuntu-System
# eine bootfähige Live-ISO auf Basis eines
# bestehenden Ubuntu Server Live ISO.
#
# Ablauf:
# 1. Original-ISO extrahieren
# 2. Root-FS in temporäres Verzeichnis rsyncen
# 3. Root-FS bereinigen
# 4. squashfs erzeugen
# 5. grub.cfg für Live-Boot schreiben
# 6. ISO mit originaler Bootstruktur neu bauen
#
# Optional:
# - NoCloud-Daten einbetten
# - eigener ISO-Name
########################################

### Konfiguration via Umgebungsvariablen oder Defaults
SOURCE_ISO="/var/www/html/linux/ubuntu/noble/amd64/ubuntu-24.04.4-live-server-amd64.iso"
WORKDIR="${WORKDIR:-$HOME/ws/lernvirt-live}"
OUT_ISO="${OUT_ISO:-$PWD/lernvirt-live.iso}"
ISO_LABEL="${ISO_LABEL:-LERNVIRT_LIVE}"
HOSTNAME_DEFAULT="${HOSTNAME_DEFAULT:-lernvirt-live}"
NOCLOUD_DIR="${NOCLOUD_DIR:-}"      # optional, Pfad zu user-data/meta-data
ENABLE_NOCLOUD="${ENABLE_NOCLOUD:-1}"  # 1 = nocloud einbetten
CLEAN_LOGS="${CLEAN_LOGS:-1}"
RESET_MACHINE_ID="${RESET_MACHINE_ID:-1}"
COMP="${COMP:-xz}"                  # xz, zstd, gzip, lz4, lzo...
MKSQUASHFS_OPTS="${MKSQUASHFS_OPTS:--b 1M -Xdict-size 100%}"

### interne Pfade
MNT="$WORKDIR/mnt"
EXTRACT="$WORKDIR/extract"
ROOTFS="$WORKDIR/rootfs"
TMP="$WORKDIR/tmp"

### Checks
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Fehlt: $1" >&2
    exit 1
  }
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Bitte als root ausführen." >&2
    exit 1
  fi
}

cleanup() {
  set +e
  mountpoint -q "$ROOTFS/dev" && umount -lf "$ROOTFS/dev"
  mountpoint -q "$ROOTFS/proc" && umount -lf "$ROOTFS/proc"
  mountpoint -q "$ROOTFS/sys" && umount -lf "$ROOTFS/sys"
  mountpoint -q "$MNT" && umount -lf "$MNT"
}
trap cleanup EXIT

require_root
require_cmd rsync
require_cmd xorriso
require_cmd mksquashfs
require_cmd mount
require_cmd umount
require_cmd chroot
require_cmd find
require_cmd sed
require_cmd awk
require_cmd cp
require_cmd grub-mkpasswd-pbkdf2 || true

if [[ ! -f "$SOURCE_ISO" ]]; then
  echo "SOURCE_ISO nicht gefunden: $SOURCE_ISO" >&2
  exit 1
fi

if [[ "$ENABLE_NOCLOUD" == "1" && -z "$NOCLOUD_DIR" ]]; then
  echo "ENABLE_NOCLOUD=1, aber NOCLOUD_DIR ist leer." >&2
  exit 1
fi

if [[ "$ENABLE_NOCLOUD" == "1" ]]; then
  if [[ ! -f "$NOCLOUD_DIR/user-data" || ! -f "$NOCLOUD_DIR/meta-data" ]]; then
    echo "In NOCLOUD_DIR fehlen user-data und/oder meta-data: $NOCLOUD_DIR" >&2
    exit 1
  fi
fi

echo "==> Arbeitsverzeichnis vorbereiten"
rm -rf "$WORKDIR"
mkdir -p "$MNT" "$EXTRACT" "$ROOTFS" "$TMP"

echo "==> Benötigte Pakete prüfen/installieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  xorriso \
  squashfs-tools \
  rsync \
  casper \
  discover \
  laptop-detect \
  os-prober \
  cloud-init \
  curl

echo "==> Original-ISO mounten und extrahieren"
mount -o loop "$SOURCE_ISO" "$MNT"
rsync -aHAX --delete "$MNT"/ "$EXTRACT"/
umount "$MNT"

echo "==> Root-Dateisystem kopieren"
rsync -aHAX \
  --exclude=/proc/* \
  --exclude=/sys/* \
  --exclude=/dev/* \
  --exclude=/run/* \
  --exclude=/tmp/* \
  --exclude=/mnt/* \
  --exclude=/media/* \
  --exclude=/var/www/* \
  --exclude=/home/ubuntu/.* \
  --exclude=/lost+found \
  --exclude=/srv/* \
  --exclude="$WORKDIR/*" \
  / "$ROOTFS"/

echo "==> Root-Dateisystem bereinigen"

# Hostname setzen
echo "$HOSTNAME_DEFAULT" > "$ROOTFS/etc/hostname"

# /etc/hosts minimal korrigieren
cat > "$ROOTFS/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_DEFAULT

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# temporäre und volatile Zustände entfernen
rm -f "$ROOTFS/etc/ssh/ssh_host_"*
rm -rf "$ROOTFS/tmp/"*
rm -rf "$ROOTFS/var/tmp/"*
rm -rf "$ROOTFS/run/"*
mkdir -p "$ROOTFS/run"

if [[ "$CLEAN_LOGS" == "1" ]]; then
  find "$ROOTFS/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
  rm -f "$ROOTFS/var/log/"*.gz "$ROOTFS/var/log/"*.[0-9] 2>/dev/null || true
fi

if [[ "$RESET_MACHINE_ID" == "1" ]]; then
  : > "$ROOTFS/etc/machine-id"
  rm -f "$ROOTFS/var/lib/dbus/machine-id"
  ln -sf /etc/machine-id "$ROOTFS/var/lib/dbus/machine-id"
fi

# Cloud-init Cache leeren
rm -rf "$ROOTFS/var/lib/cloud/"*

# apt cache leeren
rm -rf "$ROOTFS/var/cache/apt/archives/"*.deb 2>/dev/null || true

# Installer-Reste vermeiden
rm -f "$ROOTFS/etc/netplan/50-cloud-init.yaml" 2>/dev/null || true

# Live-Systeme sollten kein starres fstab brauchen
cat > "$ROOTFS/etc/fstab" <<'EOF'
proc /proc proc defaults 0 0
EOF

echo "==> Sicherstellen, dass Live-Boot-Pakete im RootFS vorhanden sind"
mount --bind /dev  "$ROOTFS/dev"
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys  "$ROOTFS/sys"

if [[ -L "$ROOTFS/etc/resolv.conf" || ! -e "$ROOTFS/etc/resolv.conf" ]]; then
  rm -f "$ROOTFS/etc/resolv.conf"
fi
cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -c '
set -Eeuo pipefail

apt-get update
apt-get install -y \
  casper \
  cloud-init \
  systemd-sysv \
  sudo \
  openssh-server \
  curl \
  less \
  vim-tiny \
  net-tools \
  iproute2 \
  iputils-ping

# initramfs neu bauen, damit casper sicher enthalten ist
update-initramfs -u -k all

# SSH Host Keys beim ersten Boot neu generieren
systemctl enable ssh || true

# Cloud-init im Live-System grundsätzlich aktiviert lassen
touch /etc/cloud/cloud-init.disabled || true
rm -f /etc/cloud/cloud-init.disabled || true

# Journald nicht persistieren
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/live.conf <<JEOF
[Journal]
Storage=volatile
JEOF
'
sync
sleep 1
umount -lf "$ROOTFS/dev"  || true
umount -lf "$ROOTFS/proc" || true
umount -lf "$ROOTFS/sys"  || true

echo "==> Kernel und initrd aus dem RootFS auswählen"
KERNEL_SRC="$(ls -1 "$ROOTFS"/boot/vmlinuz-* | sort -V | tail -n1)"
INITRD_SRC="$(ls -1 "$ROOTFS"/boot/initrd.img-* | sort -V | tail -n1)"

mkdir -p "$EXTRACT/casper"
cp -f "$KERNEL_SRC" "$EXTRACT/casper/vmlinuz"
cp -f "$INITRD_SRC" "$EXTRACT/casper/initrd"

if [[ -L "$ROOTFS/etc/resolv.conf" || ! -e "$ROOTFS/etc/resolv.conf" ]]; then
  rm -f "$ROOTFS/etc/resolv.conf"
fi
cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

chroot "$ROOTFS" dpkg-query -W --showformat='${Package} ${Version}\n' \
  | tee "$EXTRACT/casper/filesystem.manifest" >/dev/null

cp -f "$EXTRACT/casper/filesystem.manifest" \
      "$EXTRACT/casper/filesystem.manifest-desktop" || true

echo "==> filesystem.squashfs bauen"
rm -f "$EXTRACT/casper/filesystem.squashfs"
mksquashfs "$ROOTFS" "$EXTRACT/casper/filesystem.squashfs" \
  -comp "$COMP" \
  $MKSQUASHFS_OPTS \
  -e boot

printf '%s' "$(du -sx --block-size=1 "$ROOTFS" | awk "{print \$1}")" \
  > "$EXTRACT/casper/filesystem.size"

echo "==> md5sum.txt neu erzeugen"
(
  cd "$EXTRACT"
  rm -f md5sum.txt
  find . -path ./md5sum.txt -prune -o -type f -print0 \
    | sort -z \
    | xargs -0 md5sum \
    | sed 's# \./# #g' \
    > md5sum.txt
)

echo "==> GRUB-Konfiguration schreiben"
mkdir -p "$EXTRACT/boot/grub"

if [[ "$ENABLE_NOCLOUD" == "1" ]]; then
  mkdir -p "$EXTRACT/nocloud"

  cat > "$EXTRACT/nocloud/meta-data" <<'EOF'
instance-id: lernvirt-live
local-hostname: lernvirt-live
EOF

  cat > "$EXTRACT/nocloud/user-data" <<'EOF'
#cloud-config
users:
  - default
EOF

  if [[ -n "${NOCLOUD_DIR:-}" ]]; then
    [[ -f "$NOCLOUD_DIR/meta-data" ]] && cp -f "$NOCLOUD_DIR/meta-data" "$EXTRACT/nocloud/meta-data"
    [[ -f "$NOCLOUD_DIR/user-data" ]] && cp -f "$NOCLOUD_DIR/user-data" "$EXTRACT/nocloud/user-data"
  fi

  CLOUD_PARAM='ds=nocloud\;s=/cdrom/nocloud/'
else
  CLOUD_PARAM=''
fi

cat > "$EXTRACT/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0

if loadfont /boot/grub/font.pf2 ; then
  set gfxmode=auto
  insmod efi_gop
  insmod efi_uga
  insmod gfxterm
  terminal_output gfxterm
fi

menuentry "lernvirt Live" {
    linux   /casper/vmlinuz boot=casper maybe-ubiquity noprompt noeject quiet splash console=ttyS0 ${CLOUD_PARAM} ---
    initrd  /casper/initrd
}

menuentry "lernvirt Live (safe graphics)" {
    linux   /casper/vmlinuz boot=casper nomodeset maybe-ubiquity noprompt noeject console=ttyS0 ${CLOUD_PARAM} ---
    initrd  /casper/initrd
}
EOF

echo "==> altes Autoinstall-Verhalten neutralisieren, falls vorhanden"
# Nur die Live-Menüs sollen aktiv sein
# Weitere Original-Einträge bleiben hier absichtlich nicht erhalten.

echo "==> ISO neu bauen mit originaler Bootstruktur"
rm -f "$OUT_ISO"

XORRISO_ARGS=(
  -indev "$SOURCE_ISO"
  -outdev "$OUT_ISO"
  -map "$EXTRACT/casper/vmlinuz" /casper/vmlinuz
  -map "$EXTRACT/casper/initrd" /casper/initrd
  -map "$EXTRACT/casper/filesystem.squashfs" /casper/filesystem.squashfs
  -map "$EXTRACT/casper/filesystem.manifest" /casper/filesystem.manifest
  -map "$EXTRACT/casper/filesystem.manifest-desktop" /casper/filesystem.manifest-desktop
  -map "$EXTRACT/casper/filesystem.size" /casper/filesystem.size
  -map "$EXTRACT/boot/grub/grub.cfg" /boot/grub/grub.cfg
  -map "$EXTRACT/md5sum.txt" /md5sum.txt
  -volume_date all_file_dates "$(date -u +%Y%m%d%H%M%S)00"
  -volid "$ISO_LABEL"
  -boot_image any replay
)

if [[ "$ENABLE_NOCLOUD" == "1" ]]; then
  XORRISO_ARGS+=(
    -map "$EXTRACT/nocloud/user-data" /nocloud/user-data
    -map "$EXTRACT/nocloud/meta-data" /nocloud/meta-data
  )
fi

xorriso "${XORRISO_ARGS[@]}"

echo
echo "Fertig: $OUT_ISO"
echo
echo "Zum Testen mit QEMU:"
echo "  qemu-system-x86_64 -m 4096 -cdrom \"$OUT_ISO\" -nographic -serial mon:stdio"
echo
echo "Zum Schreiben auf USB-Stick:"
echo "  sudo dd if=\"$OUT_ISO\" of=/dev/sdX bs=4M status=progress oflag=sync"
echo "  sync"




