#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# Ubuntu Live ISO Builder
#
# Profile:
#   PROFILE=headless   -> minimale headless Live-ISO
#   PROFILE=gui        -> GUI + Ubiquity + VS Code
#
# Direkt im Image:
#   - AWS CLI v2
#   - Azure CLI
#   - Google Cloud CLI
#   - Terraform
#   - OpenTofu
#
# Optional als First-Boot root-Skripte:
#   - nfsshare.sh
#   - storage-patch.sh
#   - vpn.sh
#
# GUI-Profil:
#   - Ubuntu Desktop Minimal
#   - GDM3
#   - Ubiquity
#   - VS Code
#   - Chromium per snap beim ersten Boot
#
# Verwendung:
#   sudo env PROFILE=headless bash ./build-live.sh
#   sudo env PROFILE=gui      bash ./build-live.sh
# ============================================================================

UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
ARCH="${ARCH:-amd64}"
MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu/}"

PROFILE="${PROFILE:-gui}"

WORKDIR="${WORKDIR:-$(pwd)/build-${PROFILE}}"
CHROOT_DIR="$WORKDIR/chroot"
IMAGE_DIR="$WORKDIR/image"
ISO_NAME="${ISO_NAME:-ubuntu-${PROFILE}-live-${UBUNTU_CODENAME}-${ARCH}.iso}"
ISO_PATH="$WORKDIR/$ISO_NAME"

HOSTNAME_LIVE="${HOSTNAME_LIVE:-ubuntu-live}"
USERNAME="${USERNAME:-ubuntu}"
PASSWORD="${PASSWORD:-ubuntu}"

LERNCLOUD_BASE="${LERNCLOUD_BASE:-https://raw.githubusercontent.com/mc-b/lerncloud/main/services}"
LERNCLOUD_DIR_IN_IMAGE="/opt/lerncloud"
ENABLE_FIRSTBOOT_SCRIPTS="${ENABLE_FIRSTBOOT_SCRIPTS:-yes}"

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
  echo "FEHLER: $*" >&2
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Bitte mit sudo oder als root ausfuehren."
}

validate_profile() {
  case "$PROFILE" in
    headless|gui) ;;
    *) die "Ungueltiges PROFILE: $PROFILE (erlaubt: headless|gui)" ;;
  esac
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

get_common_packages() {
  cat <<'EOF'
sudo
ubuntu-standard
casper
locales
apt-utils
curl
wget
ca-certificates
git
jq
vim
nano
less
openssh-server
wireguard
wireguard-tools
nfs-kernel-server
open-iscsi
multipath-tools
python3
python3-venv
python3-pip
systemd-sysv
linux-generic
discover
laptop-detect
os-prober
apt-transport-https
gpg
gnupg
lsb-release
software-properties-common
unzip
dnsutils
iproute2
iputils-ping
isc-dhcp-client
systemd-resolved
systemd-timesyncd
EOF
}

get_headless_packages() {
  cat <<'EOF'
network-manager
net-tools
grub-common
grub-pc-bin
grub2-common
grub-efi-amd64-bin
grub-efi-amd64-signed
shim-signed
EOF
}

get_gui_packages() {
  cat <<'EOF'
network-manager
net-tools
wireless-tools
wpagui
grub-common
grub-gfxpayload-lists
grub-pc
grub-pc-bin
grub2-common
grub-efi-amd64-bin
grub-efi-amd64-signed
shim-signed
mtools
binutils
ubiquity
ubiquity-casper
ubiquity-frontend-gtk
ubiquity-slideshow-ubuntu
ubiquity-ubuntu-artwork
plymouth-themes
ubuntu-desktop-minimal
gdm3
dbus-x11
xdg-utils
x11-xserver-utils
mesa-utils
fonts-dejavu
keyboard-configuration
console-setup
snapd
EOF
}

build_package_list() {
  local pkgs
  pkgs="$(get_common_packages)"

  if [[ "$PROFILE" == "gui" ]]; then
    pkgs="$pkgs $(get_gui_packages)"
  else
    pkgs="$pkgs $(get_headless_packages)"
  fi

  echo "$pkgs" | xargs
}

EXTRA_PACKAGES="$(build_package_list)"

install_host_deps() {
  log "Installiere Host-Abhaengigkeiten"
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
    findutils \
    curl \
    ca-certificates \
    gpg
}

prepare_dirs() {
  log "Bereite Verzeichnisse vor"
  rm -rf "$WORKDIR"
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
# Ubuntu

deb $MIRROR $UBUNTU_CODENAME main restricted universe multiverse
deb $MIRROR $UBUNTU_CODENAME-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
}

write_chroot_script() {
  log "Erzeuge chroot-Konfiguration fuer Profil: $PROFILE"

  cat > "$CHROOT_DIR/root/configure-live.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

PROFILE="$PROFILE"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
HOSTNAME_LIVE="$HOSTNAME_LIVE"
EXTRA_PACKAGES="$EXTRA_PACKAGES"

echo "\$HOSTNAME_LIVE" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
127.0.1.1 \$HOSTNAME_LIVE
::1 localhost ip6-localhost ip6-loopback
HOSTS

apt-get update
apt-get install -y libterm-readline-gnu-perl dbus dialog apt-utils
apt-get -y upgrade

if [[ "\$PROFILE" == "gui" ]]; then
  apt-get install -y \$EXTRA_PACKAGES
else
  apt-get install -y --no-install-recommends \$EXTRA_PACKAGES
fi

apt-get purge -y 'libreoffice*' || true
apt-get autoremove -y || true

dbus-uuidgen > /etc/machine-id || true
ln -sf /etc/machine-id /var/lib/dbus/machine-id

if [[ ! -L /sbin/initctl ]]; then
  dpkg-divert --local --rename --add /sbin/initctl
  ln -sf /bin/true /sbin/initctl
fi

sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
sed -i 's/^# *de_CH.UTF-8 UTF-8/de_CH.UTF-8 UTF-8/' /etc/locale.gen || true
grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
grep -q '^de_CH.UTF-8 UTF-8' /etc/locale.gen || echo 'de_CH.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
update-locale LANG=de_CH.UTF-8

id -u "\$USERNAME" >/dev/null 2>&1 || useradd -m -s /bin/bash "\$USERNAME"
echo "\$USERNAME:\$PASSWORD" | chpasswd
usermod -aG sudo "\$USERNAME"
passwd -d root || true

mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/90-\$USERNAME-nopasswd <<SUDOE
\$USERNAME ALL=(ALL) NOPASSWD:ALL
SUDOE
chmod 0440 /etc/sudoers.d/90-\$USERNAME-nopasswd

mkdir -p /var/run/sshd
systemctl enable ssh || true

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-live.conf <<SSHEOF
PasswordAuthentication yes
PermitRootLogin prohibit-password
SSHEOF

# Netzwerk
systemctl enable NetworkManager || true
systemctl enable systemd-resolved || true
systemctl disable systemd-networkd || true
systemctl disable systemd-networkd-wait-online.service || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# GUI-spezifisch
if [[ "\$PROFILE" == "gui" ]]; then
  mkdir -p /etc/gdm3
  cat > /etc/gdm3/custom.conf <<'GDMEOF'
[daemon]
WaylandEnable=false
GDMEOF
fi

# Tastatur Schweiz / Deutsch
mkdir -p /etc/default
cat > /etc/default/keyboard <<'KBD'
XKBLAYOUT="ch"
XKBVARIANT="de"
XKBMODEL="pc105"
XKBOPTIONS=""
BACKSPACE="guess"
KBD

systemctl enable serial-getty@ttyS0.service || true

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
EOF

  chmod +x "$CHROOT_DIR/root/configure-live.sh"
}

run_chroot_config() {
  log "Fuehre chroot-Konfiguration aus"
  chroot "$CHROOT_DIR" env LANG=C.UTF-8 LC_ALL=C.UTF-8 /bin/bash /root/configure-live.sh
}

install_vscode_in_chroot() {
  log "Installiere VS Code im chroot"

  cat > "$CHROOT_DIR/root/install-vscode.sh" <<'EOF'
#!/usr/bin/env bash
set +e
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "[INFO] Installing Visual Studio Code"

if [ -r /etc/os-release ]; then
  . /etc/os-release
fi

ARCH_DEB="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  apt-transport-https \
  software-properties-common \
  lsb-release || true

if command -v code >/dev/null 2>&1; then
  echo "[INFO] VS Code ist bereits installiert"
  exit 0
fi

mkdir -p /etc/apt/keyrings

curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor \
  -o /etc/apt/keyrings/microsoft-vscode.gpg || true

cat > /etc/apt/sources.list.d/vscode.list <<VSCODEEOF
deb [arch=${ARCH_DEB} signed-by=/etc/apt/keyrings/microsoft-vscode.gpg] https://packages.microsoft.com/repos/code stable main
VSCODEEOF

apt-get update -y
apt-get install -y code || true

if [ -f /usr/share/code/chrome-sandbox ]; then
  chown root:root /usr/share/code/chrome-sandbox || true
  chmod 4755 /usr/share/code/chrome-sandbox || true
fi

mkdir -p /usr/local/bin
cat > /usr/local/bin/code-live <<'WRAPEOF'
#!/usr/bin/env bash
exec /usr/bin/code --no-sandbox --disable-gpu --disable-dev-shm-usage "$@"
WRAPEOF
chmod +x /usr/local/bin/code-live

if [ -f /usr/share/applications/code.desktop ]; then
  sed -i 's#^Exec=/usr/share/code/code --unity-launch %F#Exec=/usr/local/bin/code-live %F#' /usr/share/applications/code.desktop || true
  sed -i 's#^Exec=/usr/share/code/code --new-window %F#Exec=/usr/local/bin/code-live %F#' /usr/share/applications/code.desktop || true
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

  chmod +x "$CHROOT_DIR/root/install-vscode.sh"
  chroot "$CHROOT_DIR" env LANG=C.UTF-8 LC_ALL=C.UTF-8 /bin/bash /root/install-vscode.sh
  rm -f "$CHROOT_DIR/root/install-vscode.sh"
}

install_cloud_tools_in_chroot() {
  log "Installiere Cloud-CLIs, Terraform und OpenTofu direkt im chroot"

  cat > "$CHROOT_DIR/root/install-cloud-tools.sh" <<'EOF'
#!/usr/bin/env bash
set +e
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "[INFO] Installing AWS CLI + Azure CLI + Google Cloud CLI + Terraform + OpenTofu"

if [ -r /etc/os-release ]; then
  . /etc/os-release
  DISTRO="${NAME:-Unknown}"
  CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo noble)}"
else
  DISTRO="Unknown"
  CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)"
fi

ARCH_DEB="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
ARCH_UNAME="$(uname -m)"

echo "[INFO] Distribution: ${DISTRO} (${CODENAME}), Architektur: ${ARCH_DEB}/${ARCH_UNAME}"

apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common \
  unzip \
  wget \
  gpg || echo "[WARN] Einige Prerequisites konnten nicht installiert werden"

# AWS CLI v2
if ! command -v aws >/dev/null 2>&1; then
  TMP_DIR="$(mktemp -d)"
  AWS_ZIP="${TMP_DIR}/awscliv2.zip"

  if [ "${ARCH_UNAME}" = "x86_64" ]; then
    AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  elif [ "${ARCH_UNAME}" = "aarch64" ] || [ "${ARCH_UNAME}" = "arm64" ]; then
    AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  else
    AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  fi

  curl -fsSL "${AWS_URL}" -o "${AWS_ZIP}" || true
  unzip -q "${AWS_ZIP}" -d "${TMP_DIR}" || true
  "${TMP_DIR}/aws/install" -i /usr/local/aws-cli -b /usr/local/bin || true
  rm -rf "${TMP_DIR}"
fi

# Azure CLI
if ! command -v az >/dev/null 2>&1; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg || true

  cat > /etc/apt/sources.list.d/azure-cli.sources <<AZSRC
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${CODENAME}
Components: main
Architectures: ${ARCH_DEB}
Signed-By: /etc/apt/keyrings/microsoft.gpg
AZSRC

  apt-get update -y
  apt-get install -y azure-cli || true
fi

# Google Cloud CLI
if ! command -v gcloud >/dev/null 2>&1; then
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg || true

  cat > /etc/apt/sources.list.d/google-cloud-sdk.list <<'GCSRC'
deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main
GCSRC

  apt-get update -y
  apt-get install -y google-cloud-cli || true
fi

# Terraform
if ! command -v terraform >/dev/null 2>&1; then
  mkdir -p /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/hashicorp-archive-keyring.gpg ]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | gpg --dearmor \
      -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg || true
  fi

  cat > /etc/apt/sources.list.d/hashicorp.list <<HASHISRC
deb [arch=${ARCH_DEB} signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main
HASHISRC

  apt-get update -y
  apt-get install -y terraform || true
fi

# OpenTofu
if ! command -v tofu >/dev/null 2>&1; then
  curl -fsSL https://get.opentofu.org/install-opentofu.sh \
    | bash -s -- --install-method standalone \
                 --opentofu-version latest \
                 --install-path /opt/opentofu \
                 --symlink-path /usr/local/bin || true
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

  chmod +x "$CHROOT_DIR/root/install-cloud-tools.sh"
  chroot "$CHROOT_DIR" env LANG=C.UTF-8 LC_ALL=C.UTF-8 /bin/bash /root/install-cloud-tools.sh
  rm -f "$CHROOT_DIR/root/install-cloud-tools.sh"
}

download_root_firstboot_scripts() {
  log "Lade optionale root-First-Boot Skripte ins Image"
  mkdir -p "$CHROOT_DIR$LERNCLOUD_DIR_IN_IMAGE"

  local scripts=(
    nfsshare.sh
    storage-patch.sh
    vpn.sh
  )

  for s in "${scripts[@]}"; do
    curl -fsSL "$LERNCLOUD_BASE/$s" -o "$CHROOT_DIR$LERNCLOUD_DIR_IN_IMAGE/$s"
    chmod +x "$CHROOT_DIR$LERNCLOUD_DIR_IN_IMAGE/$s"
  done
}

write_gui_firstboot_extras() {
  log "Erzeuge GUI First-Boot Extras"
  mkdir -p "$CHROOT_DIR/usr/local/sbin" "$CHROOT_DIR/etc/systemd/system"

  cat > "$CHROOT_DIR/usr/local/sbin/gui-firstboot.sh" <<'GUIFIRSTBOOT'
#!/usr/bin/env bash
set -Eeuo pipefail

LOGFILE="/var/log/gui-firstboot.log"
MARKER="/var/lib/gui-firstboot.done"

exec > >(tee -a "$LOGFILE") 2>&1

wait_for_network() {
  local i
  for i in $(seq 1 60); do
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 snapcraft.io >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

wait_for_snapd() {
  local i
  for i in $(seq 1 60); do
    if systemctl is-active snapd >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

main() {
  [[ -f "$MARKER" ]] && exit 0

  systemctl enable snapd || true
  systemctl start snapd || true
  systemctl enable snapd.socket || true
  systemctl start snapd.socket || true

  wait_for_network || true
  wait_for_snapd || true

  snap install chromium || true

  touch "$MARKER"
}

main "$@"
GUIFIRSTBOOT

  chmod +x "$CHROOT_DIR/usr/local/sbin/gui-firstboot.sh"

  cat > "$CHROOT_DIR/etc/systemd/system/gui-firstboot.service" <<'GUISVC'
[Unit]
Description=GUI First Boot Extras
Wants=network-online.target snapd.service snapd.socket
After=network-online.target snapd.service snapd.socket
ConditionPathExists=!/var/lib/gui-firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/gui-firstboot.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
GUISVC

  chroot "$CHROOT_DIR" systemctl enable gui-firstboot.service
}

write_firstboot_runner() {
  log "Erzeuge First-Boot Runner"
  mkdir -p "$CHROOT_DIR/usr/local/sbin" "$CHROOT_DIR/var/lib/lerncloud"

  cat > "$CHROOT_DIR/usr/local/sbin/lerncloud-firstboot.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

LOGFILE="/var/log/lerncloud-firstboot.log"
MARKER="/var/lib/lerncloud/firstboot.done"
LERNCLOUD_DIR="$LERNCLOUD_DIR_IN_IMAGE"

exec > >(tee -a "\$LOGFILE") 2>&1

log() {
  printf '\n[%s] %s\n' "\$(date '+%F %T')" "\$*"
}

run_script() {
  local script="\$1"
  if [[ -x "\$LERNCLOUD_DIR/\$script" ]]; then
    log "Starte \$script als root"
    bash "\$LERNCLOUD_DIR/\$script"
  else
    log "Ueberspringe \$script, nicht gefunden"
  fi
}

wait_for_network() {
  log "Warte auf Netzwerk"
  local i
  for i in \$(seq 1 60); do
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 github.com >/dev/null 2>&1; then
      log "Netzwerk verfuegbar"
      return 0
    fi
    sleep 5
  done
  log "Netzwerk nicht bestaetigt, fahre trotzdem fort"
  return 0
}

main() {
  if [[ -f "\$MARKER" ]]; then
    log "First-Boot wurde bereits ausgefuehrt"
    exit 0
  fi

  mkdir -p /var/lib/lerncloud
  wait_for_network

  run_script nfsshare.sh || true
  run_script storage-patch.sh || true
  run_script vpn.sh || true

  touch "\$MARKER"
  log "First-Boot abgeschlossen"
}

main "\$@"
EOF

  chmod +x "$CHROOT_DIR/usr/local/sbin/lerncloud-firstboot.sh"
}

write_firstboot_service() {
  log "Erzeuge systemd Service fuer First-Boot"
  mkdir -p "$CHROOT_DIR/etc/systemd/system"

  cat > "$CHROOT_DIR/etc/systemd/system/lerncloud-firstboot.service" <<'EOF'
[Unit]
Description=Lerncloud First Boot Initialisierung
Wants=network-online.target
After=network-online.target NetworkManager.service ssh.service
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
  log "Schreibe GRUB-Menue"

  local menu_title splash_arg
  if [[ "$PROFILE" == "gui" ]]; then
    menu_title="Ubuntu GUI Live"
    splash_arg="quiet splash"
  else
    menu_title="Ubuntu Minimal Live"
    splash_arg="quiet"
  fi

  cat > "$IMAGE_DIR/isolinux/grub.cfg" <<EOF
search --set=root --file /ubuntu

insmod all_video
set default=0
set timeout=5

menuentry "$menu_title" {
    linux /casper/vmlinuz boot=casper nopersistent $splash_arg console=tty1 console=ttyS0 ---
    initrd /casper/initrd
}

menuentry "$menu_title (debug)" {
    linux /casper/vmlinuz boot=casper nopersistent debug systemd.log_level=debug console=tty1 console=ttyS0 ---
    initrd /casper/initrd
}

if [ "\$grub_platform" = "efi" ]; then
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

  local diskname
  if [[ "$PROFILE" == "gui" ]]; then
    diskname="Ubuntu GUI Live"
  else
    diskname="Ubuntu Minimal Live"
  fi

  cat > "$IMAGE_DIR/README.diskdefines" <<EOF
#define DISKNAME  $diskname
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
  rm -f "$CHROOT_DIR/root/install-vscode.sh"
  rm -f "$CHROOT_DIR/root/install-cloud-tools.sh"

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
      -volid "Ubuntu-${PROFILE}-Live" \
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
  validate_profile
  install_host_deps
  prepare_dirs
  bootstrap_base_system
  mount_chroot
  write_sources_list
  write_chroot_script
  run_chroot_config

  if [[ "$PROFILE" == "gui" ]]; then
    install_vscode_in_chroot
    write_gui_firstboot_extras
  fi

  install_cloud_tools_in_chroot

  if [[ "$ENABLE_FIRSTBOOT_SCRIPTS" == "yes" ]]; then
    download_root_firstboot_scripts
    write_firstboot_runner
    write_firstboot_service
  fi

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
  echo "Profil: $PROFILE"
  echo "ISO erstellt: $ISO_PATH"
  if [[ "$ENABLE_FIRSTBOOT_SCRIPTS" == "yes" ]]; then
    echo "First-Boot Log im Live-System: /var/log/lerncloud-firstboot.log"
  fi
  if [[ "$PROFILE" == "gui" ]]; then
    echo "GUI First-Boot Log im Live-System: /var/log/gui-firstboot.log"
  fi
}

main "$@"
