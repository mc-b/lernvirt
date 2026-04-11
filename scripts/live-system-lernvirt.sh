#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# lernvirt-live-build.sh
#
# Baut aus einem bestehenden Ubuntu-System
# ein Live-ISO mit casper.
#
# Eigenschaften:
# - echtes Live-System
# - generisches DHCP-Netz
# - Host-Netzkonfiguration wird nicht übernommen
# - SSH aktiv
# - vorhandener User "ubuntu" bleibt erhalten
# - zusätzlicher SSH-Key wird gesetzt
########################################

SOURCE_ISO="${SOURCE_ISO:-/var/www/html/linux/ubuntu/noble/amd64/ubuntu-24.04.4-live-server-amd64.iso}"
WORKDIR="${WORKDIR:-$HOME/ws/live}"
OUT_ISO="${OUT_ISO:-$PWD/lernvirt-live.iso}"
ISO_LABEL="${ISO_LABEL:-LERNVIRT_LIVE}"
HOSTNAME_DEFAULT="${HOSTNAME_DEFAULT:-lernvirt-live}"

LIVE_USER="${LIVE_USER:-ubuntu}"
PUBKEY="${PUBKEY:-ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUHol1mBvP5Nwe3Bzbpq4GsHTSw96phXLZ27aPiRdrzhnQ2jMu4kSgv9xFsnpZgBsQa84EhdJQMZz8EOeuhvYuJtmhAVzAvNjjRak+bpxLPdWlox1pLJTuhcIqfTTSfBYJYB68VRAXJ29ocQB7qn7aDj6Cuw3s9IyXoaKhyb4n7I8yI3r0U30NAcMjyvV3LYOXx/JQbX+PjVsJMzp2NlrC7snz8gcSKxUtL/eF0g+WnC75iuhBbKbNPr7QP/ItHaAh9Tv5a3myBLNZQ56SgnSCgmS0EUVeMNsO8XaaKr2H2x5592IIoz7YRyL4wlOmj35bQocwdahdOCFI7nT9fr6f insecure@lerncloud}"

COMP="${COMP:-xz}"
MKSQUASHFS_OPTS="${MKSQUASHFS_OPTS:--b 1M -Xdict-size 100%}"

MNT="$WORKDIR/mnt"
EXTRACT="$WORKDIR/extract"
ROOTFS="$WORKDIR/rootfs"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Bitte als root ausführen." >&2
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Fehlt: $1" >&2
    exit 1
  }
}

cleanup_mounts() {
  set +e

  if [[ -d "$ROOTFS" ]]; then
    fuser -km "$ROOTFS/dev/pts" 2>/dev/null || true
    fuser -km "$ROOTFS/dev" 2>/dev/null || true
    fuser -km "$ROOTFS/proc" 2>/dev/null || true
    fuser -km "$ROOTFS/sys" 2>/dev/null || true

    mountpoint -q "$ROOTFS/dev/pts" && umount -lf "$ROOTFS/dev/pts" || true
    mountpoint -q "$ROOTFS/dev" && umount -lf "$ROOTFS/dev" || true
    mountpoint -q "$ROOTFS/proc" && umount -lf "$ROOTFS/proc" || true
    mountpoint -q "$ROOTFS/sys" && umount -lf "$ROOTFS/sys" || true
  fi

  mountpoint -q "$MNT" && umount -lf "$MNT" || true
}

trap cleanup_mounts EXIT

require_root
for cmd in rsync xorriso mksquashfs mount umount chroot find sed awk cp fuser; do
  require_cmd "$cmd"
done

if [[ ! -f "$SOURCE_ISO" ]]; then
  echo "SOURCE_ISO nicht gefunden: $SOURCE_ISO" >&2
  exit 1
fi

echo "==> Arbeitsverzeichnis vorbereiten"
rm -rf "$WORKDIR"
mkdir -p "$MNT" "$EXTRACT" "$ROOTFS"

echo "==> Benötigte Werkzeuge installieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  xorriso \
  squashfs-tools \
  rsync \
  ca-certificates \
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
  --exclude=/var/tmp/* \
  --exclude=/var/cache/apt/archives/*.deb \
  --exclude=/var/lib/apt/lists/* \
  --exclude=/home/ubuntu/.* \
  --exclude=/home/ubuntu/lernvirt/* \
  --exclude=/var/www/* \
  --exclude=/lost+found \
  --exclude=/swap.img \
  --exclude="$WORKDIR/*" \
  / "$ROOTFS"/

echo "==> Basisbereinigung"
echo "$HOSTNAME_DEFAULT" > "$ROOTFS/etc/hostname"

cat > "$ROOTFS/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_DEFAULT

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

rm -f "$ROOTFS/etc/ssh/ssh_host_"* || true
rm -rf "$ROOTFS/tmp/"* || true
rm -rf "$ROOTFS/var/tmp/"* || true
rm -rf "$ROOTFS/run/"* || true
mkdir -p "$ROOTFS/run"

if [[ -d "$ROOTFS/var/log" ]]; then
  find "$ROOTFS/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
  rm -f "$ROOTFS/var/log/"*.gz "$ROOTFS/var/log/"*.[0-9] 2>/dev/null || true
fi

: > "$ROOTFS/etc/machine-id"
rm -f "$ROOTFS/var/lib/dbus/machine-id"
ln -sf /etc/machine-id "$ROOTFS/var/lib/dbus/machine-id"

rm -rf "$ROOTFS/var/lib/cloud/"* || true

cat > "$ROOTFS/etc/fstab" <<'EOF'
proc /proc proc defaults 0 0
EOF

echo "==> Host-Netzkonfiguration bewusst entfernen"
rm -f "$ROOTFS/etc/netplan/"*.yaml || true
rm -f "$ROOTFS/etc/systemd/network/"*.network || true
rm -f "$ROOTFS/etc/systemd/network/"*.netdev || true
rm -f "$ROOTFS/etc/systemd/network/"*.link || true
rm -f "$ROOTFS/etc/NetworkManager/system-connections/"* 2>/dev/null || true
rm -f "$ROOTFS/etc/resolv.conf" || true

echo "==> Live-Netzkonfiguration schreiben"
mkdir -p "$ROOTFS/etc/netplan"
cat > "$ROOTFS/etc/netplan/01-live-dhcp.yaml" <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    all-en:
      match:
        name: "en*"
      dhcp4: true
      dhcp6: false
      optional: true
    all-eth:
      match:
        name: "eth*"
      dhcp4: true
      dhcp6: false
      optional: true
EOF

echo "==> cloud-init im Live-System deaktivieren"
mkdir -p "$ROOTFS/etc/cloud"
touch "$ROOTFS/etc/cloud/cloud-init.disabled"

echo "==> SSH-Key für Benutzer vorbereiten"
if ! chroot "$ROOTFS" id "$LIVE_USER" >/dev/null 2>&1; then
  echo "Benutzer '$LIVE_USER' existiert im RootFS nicht." >&2
  exit 1
fi

USER_HOME="$(chroot "$ROOTFS" getent passwd "$LIVE_USER" | awk -F: '{print $6}')"
if [[ -z "$USER_HOME" ]]; then
  echo "Home-Verzeichnis von '$LIVE_USER' konnte nicht ermittelt werden." >&2
  exit 1
fi

mkdir -p "$ROOTFS/$USER_HOME/.ssh"
chmod 700 "$ROOTFS/$USER_HOME/.ssh"
touch "$ROOTFS/$USER_HOME/.ssh/authorized_keys"
chmod 600 "$ROOTFS/$USER_HOME/.ssh/authorized_keys"

if ! grep -Fqx "$PUBKEY" "$ROOTFS/$USER_HOME/.ssh/authorized_keys"; then
  printf '%s\n' "$PUBKEY" >> "$ROOTFS/$USER_HOME/.ssh/authorized_keys"
fi

chroot "$ROOTFS" chown -R "$LIVE_USER:$LIVE_USER" "$USER_HOME/.ssh"

echo "==> Chroot vorbereiten"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"

if [[ -e /etc/resolv.conf ]]; then
  cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
else
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$ROOTFS/etc/resolv.conf"
fi

echo "==> Live-System im Chroot vorbereiten"
chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash <<'CHROOT_EOF'
set -Eeuo pipefail

apt-get update
apt-get install -y \
  casper \
  netplan.io \
  openssh-server \
  systemd-resolved \
  systemd-sysv \
  sudo \
  iproute2 \
  iputils-ping \
  net-tools \
  curl \
  less \
  vim-tiny

systemctl enable ssh || true
systemctl enable systemd-networkd || true
systemctl enable systemd-resolved || true

rm -f /etc/ssh/ssh_host_*

cat > /etc/systemd/system/ssh-hostkeys-live.service <<'EOF'
[Unit]
Description=Generate SSH host keys on first boot
Before=ssh.service
ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF

systemctl enable ssh-hostkeys-live.service || true

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-live.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
EOF

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/live.conf <<'EOF'
[Journal]
Storage=volatile
EOF

rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

netplan generate || true

# Warnung von cryptsetup ist hier tolerierbar
update-initramfs -u || true
CHROOT_EOF

echo "==> Rechte für SSH-Key sicherstellen"
chroot "$ROOTFS" chown -R "$LIVE_USER:$LIVE_USER" "$USER_HOME/.ssh"
chroot "$ROOTFS" chmod 700 "$USER_HOME/.ssh"
chroot "$ROOTFS" chmod 600 "$USER_HOME/.ssh/authorized_keys"

echo "==> Chroot sauber aushängen"
sync
cleanup_mounts

echo "==> Kernel und initrd übernehmen"
KERNEL_SRC="$(ls -1 "$ROOTFS"/boot/vmlinuz-* | sort -V | tail -n1)"
INITRD_SRC="$(ls -1 "$ROOTFS"/boot/initrd.img-* | sort -V | tail -n1)"

mkdir -p "$EXTRACT/casper"
cp -f "$KERNEL_SRC" "$EXTRACT/casper/vmlinuz"
cp -f "$INITRD_SRC" "$EXTRACT/casper/initrd"

echo "==> Manifest erzeugen"
chroot "$ROOTFS" dpkg-query -W --showformat='${Package} ${Version}\n' \
  > "$EXTRACT/casper/filesystem.manifest"

cp -f "$EXTRACT/casper/filesystem.manifest" \
      "$EXTRACT/casper/filesystem.manifest-desktop"

echo "==> SquashFS bauen"
rm -f "$EXTRACT/casper/filesystem.squashfs"
mksquashfs "$ROOTFS" "$EXTRACT/casper/filesystem.squashfs" \
  -comp "$COMP" \
  $MKSQUASHFS_OPTS

du -sx --block-size=1 "$ROOTFS" | awk '{print $1}' > "$EXTRACT/casper/filesystem.size"

echo "==> GRUB-Konfiguration schreiben"
mkdir -p "$EXTRACT/boot/grub"
cat > "$EXTRACT/boot/grub/grub.cfg" <<'EOF'
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
    linux /casper/vmlinuz boot=casper noprompt noeject console=ttyS0 ---
    initrd /casper/initrd
}

menuentry "lernvirt Live (safe graphics)" {
    linux /casper/vmlinuz boot=casper nomodeset noprompt noeject console=ttyS0 ---
    initrd /casper/initrd
}

menuentry "lernvirt Live (verbose)" {
    linux /casper/vmlinuz boot=casper noprompt noeject systemd.log_level=info console=ttyS0 ---
    initrd /casper/initrd
}
EOF

echo "==> md5sum.txt neu erzeugen"
(
  cd "$EXTRACT"
  rm -f md5sum.txt
  find . -path ./md5sum.txt -prune -o -type f -print0 \
    | sort -z \
    | xargs -0 md5sum \
    | sed 's# \./# #g' > md5sum.txt
)

echo "==> ISO neu bauen"
rm -f "$OUT_ISO"

xorriso \
  -indev "$SOURCE_ISO" \
  -outdev "$OUT_ISO" \
  -map "$EXTRACT/casper/vmlinuz" /casper/vmlinuz \
  -map "$EXTRACT/casper/initrd" /casper/initrd \
  -map "$EXTRACT/casper/filesystem.squashfs" /casper/filesystem.squashfs \
  -map "$EXTRACT/casper/filesystem.manifest" /casper/filesystem.manifest \
  -map "$EXTRACT/casper/filesystem.manifest-desktop" /casper/filesystem.manifest-desktop \
  -map "$EXTRACT/casper/filesystem.size" /casper/filesystem.size \
  -map "$EXTRACT/boot/grub/grub.cfg" /boot/grub/grub.cfg \
  -map "$EXTRACT/md5sum.txt" /md5sum.txt \
  -volid "$ISO_LABEL" \
  -volume_date all_file_dates "$(date -u +%Y%m%d%H%M%S)00" \
  -boot_image any replay

echo
echo "Fertig: $OUT_ISO"
echo
echo "QEMU-Test mit Bridge statt internem NAT:"
echo "  qemu-system-x86_64 -m 8192 -enable-kvm -cpu host -cdrom \"$OUT_ISO\" -nic bridge,br=br0,model=virtio"
echo
echo "Falls keine Bridge existiert, zuerst auf dem Host eine Bridge einrichten."