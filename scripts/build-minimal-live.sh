#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# Ubuntu Minimal Live ISO Builder + lerncloud Integration
# - headless
# - ohne GUI
# - ohne Java
# - ohne VS Code
# - BIOS + UEFI bootfähig
# - integriert lerncloud Skripte via First-Boot systemd Service
# ============================================================================
#
# Verwendung:
#   sudo bash build-minimal-live-lerncloud.sh
#
# Optional:
#   UBUNTU_CODENAME=noble ISO_NAME=my-live.iso sudo bash build-minimal-live-lerncloud.sh
# ============================================================================

UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
ARCH="${ARCH:-amd64}"
MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu/}"

WORKDIR="${WORKDIR:-$HOME/live-ubuntu-minimal}"
CHROOT_DIR="$WORKDIR/chroot"
IMAGE_DIR="$WORKDIR/image"
ISO_NAME="${ISO_NAME:-ubuntu-minimal-live-${UBUNTU_CODENAME}-${ARCH}.iso}"
ISO_PATH="$WORKDIR/$ISO_NAME"

HOSTNAME_LIVE="${HOSTNAME_LIVE:-ubuntu-live}"
USERNAME="${USERNAME:-ubuntu}"
PASSWORD="${PASSWORD:-ubuntu}"

LERNCLOUD_BASE="${LERNCLOUD_BASE:-https://raw.githubusercontent.com/mc-b/lerncloud/main/services}"
LERNCLOUD_DIR_IN_IMAGE="/opt/lerncloud"

EXTRA_PACKAGES="${EXTRA_PACKAGES:-\
ubuntu-standard \
casper \
discover \
laptop-detect \
os-prober \
network-manager \
systemd-sysv \
linux-generic \
grub-common \
grub-pc-bin \
grub2-common \
grub-efi-amd64-bin \
grub-efi-amd64-signed \
shim-signed \
sudo \
locales \
nano \
vim \
less \
curl \
wget \
ca-certificates \
git \
jq \
iproute2 \
iputils-ping \
net-tools \
dnsutils \
openssh-server \
isc-dhcp-client \
systemd-resolved \
systemd-timesyncd \
wireguard \
wireguard-tools \
nfs-kernel-server \
open-iscsi \
multipath-tools}"

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
  echo "FEHLER: $*" >&2
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Bitte mit sudo oder als root ausführen."
}

cleanup_mounts() {
  set +e
  for mp in \
    "$CHROOT_DIR/proc" \
    "$CHROOT_DIR/sys" \
    "$CHROOT_DIR/dev/pts" \
    "$CHROOT_DIR/dev" \
    "$CHROOT_DIR/run"
  do
    if mountpoint -q "$mp"; then
      umount -lf "$mp" || true
    fi
  done
}

cleanup_on_exit() {
  cleanup_mounts
}
trap cleanup_on_exit EXIT

install_host_deps() {
  log "Installiere Host-Abhängigkeiten"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    debootstrap \
    squashfs-tools \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-amd64-signed \
    shim-signed \
    mtools \
    dosfstools \
    rsync \
    gdisk \
    sed \
    gawk \
    coreutils \
    findutils
}

prepare_dirs() {
  log "Bereite Verzeichnisse vor"
  mkdir -p "$WORKDIR" "$CHROOT_DIR" "$IMAGE_DIR"
}

bootstrap_base_system() {
  log "Erzeuge Basissystem mit debootstrap"
  debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    "$UBUNTU_CODENAME" \
    "$CHROOT_DIR" \
    "$MIRROR"
}

mount_chroot() {
  log "Binde chroot-Dateisysteme ein"
  mount --bind /dev "$CHROOT_DIR/dev"
  mount --bind /run "$CHROOT_DIR/run"
  mount -t proc /proc "$CHROOT_DIR/proc"
  mount -t sysfs /sys "$CHROOT_DIR/sys"
  mount -t devpts /dev/pts "$CHROOT_DIR/dev/pts"
}

write_sources_list() {
  log "Schreibe sources.list"
  cat > "$CHROOT_DIR/etc/apt/sources.list" <<EOF
deb $MIRROR $UBUNTU_CODENAME main restricted universe multiverse
deb $MIRROR $UBUNTU_CODENAME-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
}

write_chroot_script() {
  log "Erzeuge chroot-Konfiguration"
  cat > "$CHROOT_DIR/root/configure-live.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export LC_ALL=C

echo "$HOSTNAME_LIVE" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_LIVE
::1 localhost ip6-localhost ip6-loopback
HOSTS

apt-get update
apt-get install -y libterm-readline-gnu-perl dbus
apt-get install -y $EXTRA_PACKAGES

dbus-uuidgen > /etc/machine-id || true
ln -sf /etc/machine-id /var/lib/dbus/machine-id

if [[ ! -L /sbin/initctl ]]; then
  dpkg-divert --local --rename --add /sbin/initctl
  ln -sf /bin/true /sbin/initctl
fi

sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

id -u $USERNAME >/dev/null 2>&1 || useradd -m -s /bin/bash $USERNAME
echo '$USERNAME:$PASSWORD' | chpasswd
usermod -aG sudo $USERNAME
passwd -d root || true

mkdir -p /var/run/sshd
systemctl enable ssh || true

systemctl enable systemd-networkd || true
systemctl enable systemd-resolved || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-wired.network <<NETEOF
[Match]
Name=en* eth* wl* eth0 ens* enp*

[Network]
DHCP=yes
IPv6AcceptRA=yes
NETEOF

systemctl enable serial-getty@ttyS0.service || true

mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/90-$USERNAME-nopasswd <<SUDOE
$USERNAME ALL=(ALL) NOPASSWD:ALL
SUDOE
chmod 0440 /etc/sudoers.d/90-$USERNAME-nopasswd

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-live.conf <<SSHEOF
PasswordAuthentication yes
PermitRootLogin prohibit-password
SSHEOF

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
EOF

  chmod +x "$CHROOT_DIR/root/configure-live.sh"
}

run_chroot_config() {
  log "Führe chroot-Konfiguration aus"
  chroot "$CHROOT_DIR" /bin/bash /root/configure-live.sh
}

download_lerncloud_scripts() {
  log "Lade lerncloud Skripte ins Image"
  mkdir -p "$CHROOT_DIR$LERNCLOUD_DIR_IN_IMAGE"

  local scripts=(
    nfsshare.sh
    storage-patch.sh
    vpn.sh
    k3scontrol.sh
    k3scontroladdons.sh
    jupyter-lab.sh
  )

  for s in "${scripts[@]}"; do
    curl -fsSL "$LERNCLOUD_BASE/$s" -o "$CHROOT_DIR$LERNCLOUD_DIR_IN_IMAGE/$s"
    chmod +x "$CHROOT_DIR$LERNCLOUD_DIR_IN_IMAGE/$s"
  done
}

write_firstboot_runner() {
  log "Erzeuge First-Boot Runner"
  mkdir -p "$CHROOT_DIR/usr/local/sbin" "$CHROOT_DIR/var/lib/lerncloud"

  cat > "$CHROOT_DIR/usr/local/sbin/lerncloud-firstboot.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

LOGFILE="/var/log/lerncloud-firstboot.log"
MARKER="/var/lib/lerncloud/firstboot.done"
LERNCLOUD_DIR="/opt/lerncloud"
USERNAME="ubuntu"

exec > >(tee -a "$LOGFILE") 2>&1

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

run_script() {
  local script="$1"
  if [[ -x "$LERNCLOUD_DIR/$script" ]]; then
    log "Starte $script"
    bash "$LERNCLOUD_DIR/$script"
  else
    log "Überspringe $script, nicht gefunden"
  fi
}

wait_for_network() {
  log "Warte auf Netzwerk"
  local i
  for i in $(seq 1 60); do
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 github.com >/dev/null 2>&1; then
      log "Netzwerk verfügbar"
      return 0
    fi
    sleep 5
  done
  log "Netzwerk nicht bestätigt, fahre trotzdem fort"
  return 0
}

wait_for_k3s() {
  log "Warte auf k3s API"
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

  local i
  for i in $(seq 1 90); do
    if [[ -f /etc/rancher/k3s/k3s.yaml ]] && kubectl get nodes >/dev/null 2>&1; then
      log "k3s ist bereit"
      return 0
    fi
    sleep 5
  done

  log "k3s wurde nicht rechtzeitig bereit"
  return 1
}

main() {
  if [[ -f "$MARKER" ]]; then
    log "First-Boot wurde bereits ausgeführt"
    exit 0
  fi

  mkdir -p /var/lib/lerncloud

  wait_for_network

  # Systemnahe Teile zuerst
  run_script nfsshare.sh || true
  run_script storage-patch.sh || true
  run_script vpn.sh || true

  # K3s aufsetzen
  run_script k3scontrol.sh || true

  if wait_for_k3s; then
    run_script k3scontroladdons.sh || true
  else
    log "Überspringe k3scontroladdons.sh, da k3s nicht bereit"
  fi

  # Jupyter Lab als ubuntu User
  if id -u "$USERNAME" >/dev/null 2>&1; then
    log "Starte jupyter-lab.sh als $USERNAME"
    su - "$USERNAME" -c "bash $LERNCLOUD_DIR/jupyter-lab.sh" || true
  else
    log "User $USERNAME nicht gefunden, überspringe jupyter-lab.sh"
  fi

  touch "$MARKER"
  log "First-Boot abgeschlossen"
}

main "$@"
EOF

  chmod +x "$CHROOT_DIR/usr/local/sbin/lerncloud-firstboot.sh"
}

write_firstboot_service() {
  log "Erzeuge systemd Service für First-Boot"
  mkdir -p "$CHROOT_DIR/etc/systemd/system"

  cat > "$CHROOT_DIR/etc/systemd/system/lerncloud-firstboot.service" <<'EOF'
[Unit]
Description=Lerncloud First Boot Initialisierung
Wants=network-online.target
After=network-online.target ssh.service systemd-networkd-wait-online.service
ConditionPathExists=!/var/lib/lerncloud/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lerncloud-firstboot.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

  chroot "$CHROOT_DIR" systemctl enable lerncloud-firstboot.service
}

prepare_image_tree() {
  log "Erzeuge ISO-Verzeichnisbaum"
  mkdir -p \
    "$IMAGE_DIR/casper" \
    "$IMAGE_DIR/isolinux" \
    "$IMAGE_DIR/boot/grub"

  touch "$IMAGE_DIR/ubuntu"

  local kver
  kver="$(basename "$(ls -1 "$CHROOT_DIR"/boot/vmlinuz-* | sort | tail -n1)")"
  cp -f "$CHROOT_DIR/boot/$kver" "$IMAGE_DIR/casper/vmlinuz"

  local initrd
  initrd="$(basename "$(ls -1 "$CHROOT_DIR"/boot/initrd.img-* | sort | tail -n1)")"
  cp -f "$CHROOT_DIR/boot/$initrd" "$IMAGE_DIR/casper/initrd"
}

write_grub_cfg() {
  log "Schreibe GRUB-Menü"
  cat > "$IMAGE_DIR/isolinux/grub.cfg" <<'EOF'
search --set=root --file /ubuntu

insmod all_video
set default=0
set timeout=5

menuentry "Ubuntu Minimal Live + lerncloud" {
    linux /casper/vmlinuz boot=casper nopersistent quiet console=tty1 console=ttyS0 ---
    initrd /casper/initrd
}

menuentry "Ubuntu Minimal Live + lerncloud (debug)" {
    linux /casper/vmlinuz boot=casper nopersistent debug systemd.log_level=debug console=tty1 console=ttyS0 ---
    initrd /casper/initrd
}

if [ "$grub_platform" = "efi" ]; then
menuentry "UEFI Firmware Settings" {
    fwsetup
}
fi
EOF
}

create_manifest() {
  log "Erzeuge Paket-Manifest"
  chroot "$CHROOT_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' \
    > "$IMAGE_DIR/casper/filesystem.manifest"
  cp -f "$IMAGE_DIR/casper/filesystem.manifest" \
        "$IMAGE_DIR/casper/filesystem.manifest-desktop"
}

write_diskdefines() {
  log "Schreibe README.diskdefines"
  cat > "$IMAGE_DIR/README.diskdefines" <<EOF
#define DISKNAME  Ubuntu Minimal Live lerncloud
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  $ARCH
#define ARCH$ARCH  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  1
#define TOTALNUM1  1
EOF
}

create_efi_image() {
  log "Erzeuge EFI-Boot-Image"

  local shim=""
  local mm=""
  local grubefi=""

  for f in \
    "$CHROOT_DIR/usr/lib/shim/shimx64.efi.signed" \
    "$CHROOT_DIR/usr/lib/shim/shimx64.efi.signed.latest" \
    "$CHROOT_DIR/usr/lib/shim/shimx64.efi.signed.previous"
  do
    [[ -f "$f" ]] && shim="$f" && break
  done

  for f in \
    "$CHROOT_DIR/usr/lib/shim/mmx64.efi" \
    "$CHROOT_DIR/usr/lib/shim/mmx64.efi.signed"
  do
    [[ -f "$f" ]] && mm="$f" && break
  done

  for f in \
    "$CHROOT_DIR/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" \
    "$CHROOT_DIR/usr/lib/grub/x86_64-efi/grub.efi"
  do
    [[ -f "$f" ]] && grubefi="$f" && break
  done

  [[ -n "$shim" ]] || die "shim EFI-Datei nicht gefunden"
  [[ -n "$mm" ]] || die "mmx64.efi nicht gefunden"
  [[ -n "$grubefi" ]] || die "grubx64.efi nicht gefunden"

  cp -f "$shim"    "$IMAGE_DIR/isolinux/bootx64.efi"
  cp -f "$mm"      "$IMAGE_DIR/isolinux/mmx64.efi"
  cp -f "$grubefi" "$IMAGE_DIR/isolinux/grubx64.efi"

  (
    cd "$IMAGE_DIR/isolinux"
    dd if=/dev/zero of=efiboot.img bs=1M count=10 status=none
    mkfs.vfat -F 16 efiboot.img
    LC_CTYPE=C mmd -i efiboot.img ::efi ::efi/boot ::efi/ubuntu
    LC_CTYPE=C mcopy -i efiboot.img ./bootx64.efi ::efi/boot/bootx64.efi
    LC_CTYPE=C mcopy -i efiboot.img ./mmx64.efi   ::efi/boot/mmx64.efi
    LC_CTYPE=C mcopy -i efiboot.img ./grubx64.efi ::efi/boot/grubx64.efi
    LC_CTYPE=C mcopy -i efiboot.img ./grub.cfg    ::efi/ubuntu/grub.cfg
  )
}

create_bios_image() {
  log "Erzeuge BIOS-Boot-Image"
  grub-mkstandalone \
    --format=i386-pc \
    --output="$IMAGE_DIR/isolinux/core.img" \
    --install-modules="linux16 linux normal iso9660 biosdisk search tar ls" \
    --modules="linux16 linux normal iso9660 biosdisk search" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=$IMAGE_DIR/isolinux/grub.cfg"

  cat /usr/lib/grub/i386-pc/cdboot.img "$IMAGE_DIR/isolinux/core.img" \
    > "$IMAGE_DIR/isolinux/bios.img"
}

cleanup_chroot_for_squashfs() {
  log "Bereinige chroot"
  rm -f "$CHROOT_DIR/root/configure-live.sh"

  truncate -s 0 "$CHROOT_DIR/etc/machine-id" || true
  rm -f "$CHROOT_DIR/var/lib/dbus/machine-id" || true

  if [[ -L "$CHROOT_DIR/sbin/initctl" ]]; then
    rm -f "$CHROOT_DIR/sbin/initctl"
    chroot "$CHROOT_DIR" dpkg-divert --rename --remove /sbin/initctl || true
  fi

  rm -rf "$CHROOT_DIR/tmp/"*
  rm -f "$CHROOT_DIR/root/.bash_history"
}

create_squashfs() {
  log "Erzeuge filesystem.squashfs"
  mksquashfs "$CHROOT_DIR" "$IMAGE_DIR/casper/filesystem.squashfs" \
    -noappend -no-duplicates -no-recovery \
    -wildcards \
    -comp xz -b 1M -Xdict-size 100% \
    -e "var/cache/apt/archives/*" \
    -e "root/*" \
    -e "root/.*" \
    -e "tmp/*" \
    -e "tmp/.*" \
    -e "swapfile"

  du -sx --block-size=1 "$CHROOT_DIR" | cut -f1 \
    > "$IMAGE_DIR/casper/filesystem.size"
}

generate_md5() {
  log "Erzeuge md5sum.txt"
  (
    cd "$IMAGE_DIR"
    find . -type f -print0 \
      | xargs -0 md5sum \
      | grep -v -E './isolinux/(efiboot.img|bios.img)$' \
      > md5sum.txt
  )
}

build_iso() {
  log "Erzeuge ISO: $ISO_PATH"
  (
    cd "$IMAGE_DIR"

    xorriso \
      -as mkisofs \
      -iso-level 3 \
      -full-iso9660-filenames \
      -volid "Ubuntu-Minimal-Live" \
      -output "$ISO_PATH" \
      -eltorito-boot isolinux/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
      -eltorito-catalog isolinux/boot.cat \
      -eltorito-alt-boot \
      -e isolinux/efiboot.img \
        -no-emul-boot \
      -isohybrid-gpt-basdat \
      .
  )
}

main() {
  require_root
  install_host_deps
  prepare_dirs
  bootstrap_base_system
  mount_chroot
  write_sources_list
  write_chroot_script
  run_chroot_config
  download_lerncloud_scripts
  write_firstboot_runner
  write_firstboot_service
  prepare_image_tree
  write_grub_cfg
  create_manifest
  write_diskdefines
  create_efi_image
  create_bios_image
  cleanup_chroot_for_squashfs
  cleanup_mounts
  create_squashfs
  generate_md5
  build_iso

  log "Fertig"
  echo "ISO erstellt: $ISO_PATH"
  echo "First-Boot Log später im Live-System: /var/log/lerncloud-firstboot.log"
}

main "$@"