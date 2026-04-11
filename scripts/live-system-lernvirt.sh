#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_ISO="/var/www/html/linux/ubuntu/noble/amd64/ubuntu-24.04.4-live-server-amd64.iso"
WORKDIR="$HOME/ws/live"
OUT_ISO="$PWD/live.iso"

MNT="$WORKDIR/mnt"
EXTRACT="$WORKDIR/extract"
ROOTFS="$WORKDIR/rootfs"

PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUHol1mBvP5Nwe3Bzbpq4GsHTSw96phXLZ27aPiRdrzhnQ2jMu4kSgv9xFsnpZgBsQa84EhdJQMZz8EOeuhvYuJtmhAVzAvNjjRak+bpxLPdWlox1pLJTuhcIqfTTSfBYJYB68VRAXJ29ocQB7qn7aDj6Cuw3s9IyXoaKhyb4n7I8yI3r0U30NAcMjyvV3LYOXx/JQbX+PjVsJMzp2NlrC7snz8gcSKxUtL/eF0g+WnC75iuhBbKbNPr7QP/ItHaAh9Tv5a3myBLNZQ56SgnSCgmS0EUVeMNsO8XaaKr2H2x5592IIoz7YRyL4wlOmj35bQocwdahdOCFI7nT9fr6f insecure@lerncloud"

rm -rf "$WORKDIR"
mkdir -p "$MNT" "$EXTRACT" "$ROOTFS"

echo "== ISO extrahieren"
mount -o loop "$SOURCE_ISO" "$MNT"
rsync -a "$MNT"/ "$EXTRACT"/
umount "$MNT"

echo "== RootFS kopieren"
rsync -aHAX \
  --exclude=/proc/* \
  --exclude=/sys/* \
  --exclude=/dev/* \
  --exclude=/run/* \
  --exclude=/tmp/* \
  --exclude=/mnt/* \
  --exclude=/media/* \
  --exclude=/home/ubuntu/.* \
  --exclude=/home/ubuntu/lernvirt/* \
  --exclude=/var/tmp/* \
  --exclude=/var/cache/apt/archives/*.deb \
  --exclude=/var/lib/apt/lists/* \
  --exclude=/var/www/* \
  --exclude=/lost+found \
  --exclude=/swap.img \
  --exclude="$WORKDIR/*" \
  / "$ROOTFS"/  

echo "== minimal fix"

# cloud-init AUS
touch "$ROOTFS/etc/cloud/cloud-init.disabled"

# DHCP fix
rm -f "$ROOTFS/etc/netplan/"*.yaml || true
cat > "$ROOTFS/etc/netplan/01-dhcp.yaml" <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF

# resolv.conf korrekt
rm -f "$ROOTFS/etc/resolv.conf"
ln -s /run/systemd/resolve/resolv.conf "$ROOTFS/etc/resolv.conf"

# SSH key
mkdir -p "$ROOTFS/home/ubuntu/.ssh"
echo "$PUBKEY" >> "$ROOTFS/home/ubuntu/.ssh/authorized_keys"
chmod 700 "$ROOTFS/home/ubuntu/.ssh"
chmod 600 "$ROOTFS/home/ubuntu/.ssh/authorized_keys"
chroot "$ROOTFS" chown -R ubuntu:ubuntu /home/ubuntu/.ssh

echo "== chroot minimal"

mount --bind /dev "$ROOTFS/dev"
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"

chroot "$ROOTFS" bash -c '
apt-get update
apt-get install -y casper openssh-server netplan.io

systemctl enable ssh
systemctl enable systemd-networkd
systemctl enable systemd-resolved

update-initramfs -u
'

umount "$ROOTFS/dev"
umount "$ROOTFS/proc"
umount "$ROOTFS/sys"

echo "== kernel"
cp "$ROOTFS/boot/vmlinuz-"* "$EXTRACT/casper/vmlinuz"
cp "$ROOTFS/boot/initrd.img-"* "$EXTRACT/casper/initrd"

echo "== squashfs"
mksquashfs "$ROOTFS" "$EXTRACT/casper/filesystem.squashfs"

echo "== grub"
cat > "$EXTRACT/boot/grub/grub.cfg" <<EOF
set timeout=5
menuentry "Live" {
 linux /casper/vmlinuz boot=casper noprompt console=ttyS0 ---
 initrd /casper/initrd
}
EOF

echo "== iso"
xorriso \
  -indev "$SOURCE_ISO" \
  -outdev "$OUT_ISO" \
  -map "$EXTRACT/casper/vmlinuz" /casper/vmlinuz \
  -map "$EXTRACT/casper/initrd" /casper/initrd \
  -map "$EXTRACT/casper/filesystem.squashfs" /casper/filesystem.squashfs \
  -map "$EXTRACT/boot/grub/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay

echo "DONE: $OUT_ISO"