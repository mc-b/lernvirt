#!/usr/bin/env bash
set -Eeuo pipefail
set -o pipefail

log()  { echo "[$(date -Iseconds)] INFO:  $*" >&2; }
warn() { echo "[$(date -Iseconds)] WARN:  $*" >&2; }
fail() { echo "[$(date -Iseconds)] FEHLER: $*" >&2; exit 1; }

TMP_ISO_BASE="/tmp/pxe-iso"
TMP_ISO_AMD64="${TMP_ISO_BASE}/amd64"
TMP_ISO_ARM64="${TMP_ISO_BASE}/arm64"

cleanup() {
  for mp in "${TMP_ISO_AMD64:-}" "${TMP_ISO_ARM64:-}"; do
    if [ -n "${mp}" ] && mountpoint -q "${mp}" 2>/dev/null; then
      umount "${mp}" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Befehl nicht gefunden: $1"
}

install_pkg_if_missing() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    log "Paket bereits installiert: $pkg"
  else
    log "Installiere Paket: $pkg"
    apt-get install -y "$pkg" || fail "Konnte Paket nicht installieren: $pkg"
  fi
}

copy_first_existing() {
  local dst="$1"
  shift
  local src
  for src in "$@"; do
    if [ -f "$src" ]; then
      cp -f "$src" "$dst"
      return 0
    fi
  done
  return 1
}

extract_iso_assets() {
  local arch="$1"
  local iso_path="$2"
  local mount_dir="$3"
  local kernel_dst="$4"
  local initrd_dst="$5"

  mkdir -p "$mount_dir"

  if mountpoint -q "$mount_dir"; then
    warn "${mount_dir} ist bereits gemountet, versuche umount."
    umount "$mount_dir" || fail "Konnte bestehendes Mount von ${mount_dir} nicht loesen."
  fi

  log "Mounte ${arch}-ISO: ${iso_path}"
  mount -o loop "$iso_path" "$mount_dir" || fail "Konnte ISO nicht mounten: ${iso_path}"

  [ -f "${mount_dir}/casper/vmlinuz" ] || fail "vmlinuz in ${iso_path} nicht gefunden."
  [ -f "${mount_dir}/casper/initrd" ] || fail "initrd in ${iso_path} nicht gefunden."

  cp "${mount_dir}/casper/vmlinuz" "$kernel_dst" || fail "Konnte ${arch}-Kernel nicht kopieren."
  cp "${mount_dir}/casper/initrd" "$initrd_dst" || fail "Konnte ${arch}-Initrd nicht kopieren."

  log "Kernel und Initrd fuer ${arch} extrahiert."
}

prepare_ssh_for_ubuntu() {
  local ssh_dir="/home/ubuntu/.ssh"
  local ssh_key_file="${ssh_dir}/id_rsa_lernvirt"

  if ! id ubuntu >/dev/null 2>&1; then
    warn "User 'ubuntu' existiert auf diesem PXE-Server nicht. SSH-Setup wird uebersprungen."
    return 0
  fi

  install -d -m 700 -o ubuntu -g ubuntu "$ssh_dir"

  cat > "${ssh_dir}/config" <<'EOF'
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
LogLevel error
User ubuntu
IdentityFile ~/.ssh/id_rsa_lernvirt
EOF
  chown ubuntu:ubuntu "${ssh_dir}/config"
  chmod 400 "${ssh_dir}/config"

  if [ ! -f "$ssh_key_file" ]; then
    log "Erzeuge neuen SSH-Key fuer User ubuntu"
    ssh-keygen -t rsa -b 4096 -N "" -f "$ssh_key_file" -C "ubuntu@lernvirt-$(date +%F)" >/dev/null
    chown ubuntu:ubuntu "${ssh_key_file}" "${ssh_key_file}.pub"
    chmod 400 "${ssh_key_file}" "${ssh_key_file}.pub"
  fi
}

inject_userdata_key() {
  local temp_userdata="/tmp/user-data.tmp"
  local ssh_key_file="/home/ubuntu/.ssh/id_rsa_lernvirt"
  local pub_key=""

  if [ ! -f "${ssh_key_file}.pub" ]; then
    warn "Public SSH-Key nicht gefunden unter ${ssh_key_file}.pub. user-data wird nicht angepasst."
    return 0
  fi

  pub_key="$(cat "${ssh_key_file}.pub")"

  log "user-data von lernvirt holen"
  if wget -nv -O "$temp_userdata" "${USERDATA_URL}"; then
    log "Injektiere neuen SSH-Key in user-data"
    sed -i "s|ssh-rsa .* insecure@lerncloud|${pub_key}|" "$temp_userdata"
    mv "$temp_userdata" "${WWW}/autoinstall/user-data"
  else
    warn "Konnte user-data nicht laden von ${USERDATA_URL}."
  fi
}

### ROOT CHECK ###
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  fail "Bitte als root/sudo ausfuehren."
fi

### REQUIREMENTS ###
for cmd in ip awk sed wget mount umount cp mkdir ssh-keygen systemctl dpkg mountpoint; do
  require_cmd "$cmd"
done

### AKTIVES NETZWERK-INTERFACE & IP ERMITTELN ###
IFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
if [ -z "${IFACE}" ]; then
  IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /lo/ {print $2; exit}')"
fi
[ -n "${IFACE}" ] || fail "Konnte aktives Netzwerkinterface nicht ermitteln."

CIDR="$(ip -4 addr show dev "${IFACE}" 2>/dev/null | awk '/inet / {print $2}' | head -n1)"
[ -n "${CIDR}" ] || fail "Konnte keine IPv4-Adresse fuer ${IFACE} finden."

PXE_IP="${CIDR%%/*}"
PREFIX="${CIDR##*/}"

IFS='.' read -r o1 o2 o3 o4 <<< "${PXE_IP}"
IP_INT=$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))
MASK_INT=$(( (0xFFFFFFFF << (32 - PREFIX)) & 0xFFFFFFFF ))
NET_INT=$(( IP_INT & MASK_INT ))

NET1=$(( (NET_INT >> 24) & 255 ))
NET2=$(( (NET_INT >> 16) & 255 ))
NET3=$(( (NET_INT >> 8) & 255 ))
NET4=$(( NET_INT & 255 ))
SUBNET="${NET1}.${NET2}.${NET3}.${NET4}"

M1=$(( (MASK_INT >> 24) & 255 ))
M2=$(( (MASK_INT >> 16) & 255 ))
M3=$(( (MASK_INT >> 8) & 255 ))
M4=$(( MASK_INT & 255 ))
NETMASK="${M1}.${M2}.${M3}.${M4}"

### KONFIGURATION ###
BASE="/srv/tftp"
WWW="/var/www/html"
LOGFILE="/var/log/dnsmasq-pxe.log"

UBUNTU_VER="24.04.4"
AMD64_URL_BASE="https://releases.ubuntu.com/noble"
ARM64_URL_BASE="https://cdimage.ubuntu.com/releases/noble/release"

AMD64_ISO="ubuntu-${UBUNTU_VER}-live-server-amd64.iso"
ARM64_ISO="ubuntu-${UBUNTU_VER}-live-server-arm64.iso"

AMD64_HTTP_DIR="${WWW}/linux/ubuntu/noble/amd64"
ARM64_HTTP_DIR="${WWW}/linux/ubuntu/noble/arm64"

AMD64_ISO_PATH="${AMD64_HTTP_DIR}/${AMD64_ISO}"
ARM64_ISO_PATH="${ARM64_HTTP_DIR}/${ARM64_ISO}"

AMD64_TFTP_DIR="${BASE}/amd64"
ARM64_TFTP_DIR="${BASE}/arm64"

AMD64_KERNEL="${AMD64_TFTP_DIR}/vmlinuz"
AMD64_INITRD="${AMD64_TFTP_DIR}/initrd"
ARM64_KERNEL="${ARM64_TFTP_DIR}/vmlinuz"
ARM64_INITRD="${ARM64_TFTP_DIR}/initrd"

GRUB_X64_DIR="${BASE}/grub/x86_64-efi"
GRUB_AA64_DIR="${BASE}/grub/arm64-efi"
GRUB_CFG="${BASE}/grub/grub.cfg"
GRUB_X64_EFI="${BASE}/grubx64.efi"
GRUB_AA64_EFI="${BASE}/grubaa64.efi"

USERDATA_URL="https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/pxe/user-data"

log "Verwende Interface: ${IFACE}, IP: ${PXE_IP}, Netz: ${SUBNET}/${PREFIX}"

log "APT Index aktualisieren"
apt-get update -y || fail "apt-get update fehlgeschlagen."

log "Pakete installieren"
for pkg in dnsmasq nginx wget unzip syslinux-common grub-common grub-efi-amd64-bin; do
  install_pkg_if_missing "$pkg"
done

log "Verzeichnisse anlegen"
mkdir -p \
  "${BASE}" \
  "${AMD64_TFTP_DIR}" \
  "${ARM64_TFTP_DIR}" \
  "${GRUB_X64_DIR}" \
  "${GRUB_AA64_DIR}" \
  "${WWW}/autoinstall" \
  "${AMD64_HTTP_DIR}" \
  "${ARM64_HTTP_DIR}" \
  "${TMP_ISO_AMD64}" \
  "${TMP_ISO_ARM64}"

mkdir -p "$(dirname "${LOGFILE}")" 2>/dev/null || true

log "dnsmasq stoppen (falls aktiv)"
systemctl stop dnsmasq >/dev/null 2>&1 || true

log "dnsmasq ProxyDHCP konfigurieren"
cat > /etc/dnsmasq.d/pxe.conf <<EOF
port=0

dhcp-range=${SUBNET},proxy,${NETMASK}

#interface=${IFACE}
#bind-interfaces
bind-dynamic

dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-match=set:efi-arm64,option:client-arch,11

dhcp-boot=tag:efi-x86_64,grubx64.efi
dhcp-boot=tag:efi-arm64,grubaa64.efi

pxe-service=tag:efi-x86_64,X86-64_EFI,"UEFI PXE Boot x86_64",grubx64.efi
pxe-service=tag:efi-arm64,ARM64_EFI,"UEFI PXE Boot ARM64",grubaa64.efi

dhcp-option-force=66,${PXE_IP}

enable-tftp
tftp-root=${BASE}

log-dhcp
log-facility=${LOGFILE}
EOF

log "Ubuntu AMD64 ISO laden"
if [ ! -f "${AMD64_ISO_PATH}" ]; then
  wget -nv -O "${AMD64_ISO_PATH}" "${AMD64_URL_BASE}/${AMD64_ISO}" \
    || fail "Download der AMD64-ISO fehlgeschlagen."
else
  log "ISO bereits vorhanden: ${AMD64_ISO_PATH}"
fi

log "Ubuntu ARM64 ISO laden"
if [ ! -f "${ARM64_ISO_PATH}" ]; then
  wget -nv -O "${ARM64_ISO_PATH}" "${ARM64_URL_BASE}/${ARM64_ISO}" \
    || fail "Download der ARM64-ISO fehlgeschlagen."
else
  log "ISO bereits vorhanden: ${ARM64_ISO_PATH}"
fi

log "Kernel und Initrd aus beiden ISOs extrahieren"
extract_iso_assets "amd64" "${AMD64_ISO_PATH}" "${TMP_ISO_AMD64}" "${AMD64_KERNEL}" "${AMD64_INITRD}"
extract_iso_assets "arm64" "${ARM64_ISO_PATH}" "${TMP_ISO_ARM64}" "${ARM64_KERNEL}" "${ARM64_INITRD}"

log "GRUB-Module fuer x86_64 kopieren"
if [ -d /usr/lib/grub/x86_64-efi ]; then
  cp -a /usr/lib/grub/x86_64-efi/. "${GRUB_X64_DIR}/" 2>/dev/null || warn "Konnte x86_64-GRUB-Module nicht vollstaendig kopieren."
else
  warn "Verzeichnis /usr/lib/grub/x86_64-efi nicht gefunden."
fi

log "GRUB-Module fuer ARM64 aus ISO kopieren"
if [ -d "${TMP_ISO_ARM64}/boot/grub/arm64-efi" ]; then
  cp -a "${TMP_ISO_ARM64}/boot/grub/arm64-efi/." "${GRUB_AA64_DIR}/" 2>/dev/null \
    || warn "Konnte ARM64-GRUB-Module aus ISO nicht vollstaendig kopieren."
else
  fail "ARM64-GRUB-Module im ISO nicht gefunden: ${TMP_ISO_ARM64}/boot/grub/arm64-efi"
fi

log "x86_64 EFI-Bootloader bereitstellen"
if copy_first_existing "${GRUB_X64_EFI}" \
  /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed \
  /usr/lib/shim/shimx64.efi.signed \
  /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
  "${TMP_ISO_AMD64}/EFI/BOOT/BOOTX64.EFI" \
  "${TMP_ISO_AMD64}/efi/boot/bootx64.efi"; then
  log "x86_64 EFI-Bootloader bereitgestellt."
else
  fail "Keinen x86_64 EFI-Bootloader gefunden."
fi

log "ARM64 EFI-Bootloader bereitstellen"
if copy_first_existing "${GRUB_AA64_EFI}" \
  "${TMP_ISO_ARM64}/efi/boot/bootaa64.efi" \
  "${TMP_ISO_ARM64}/efi/boot/grubaa64.efi"; then
  log "ARM64 EFI-Bootloader bereitgestellt."
else
  fail "Keinen ARM64 EFI-Bootloader im ISO gefunden."
fi

prepare_ssh_for_ubuntu
inject_userdata_key

log "GRUB PXE Menue erstellen"
cat > "${GRUB_CFG}" <<EOF
set timeout=5
set default=1

insmod part_gpt
insmod ext2
insmod fat
insmod ntfs
insmod hfsplus

if search --no-floppy --file --set=root /boot/lernvirt-installed; then
    set default="0"
fi

search --no-floppy --file --set=win_esp /EFI/Microsoft/Boot/bootmgfw.efi
if [ -n "\$win_esp" ]; then
    set default="0"
    echo "Hinweis: Windows-Installation gefunden auf \$win_esp"
    sleep 5
fi

search --no-floppy --file --set=mac_esp /EFI/Apple/Boot/bootx64.efi
if [ -n "\$mac_esp" ]; then
    set default="0"
    echo "Hinweis: macOS-Installation gefunden auf \$mac_esp"
    sleep 5
fi

search --no-floppy --file --set=mac_sys /System/Library/CoreServices/boot.efi
if [ -n "\$mac_sys" ]; then
    set default="0"
    echo "Hinweis: macOS-System gefunden auf \$mac_sys"
    sleep 5
fi

menuentry "Local boot (lernvirt)" {
    configfile (\$root)/boot/grub/grub.cfg
}

if [ "\$grub_cpu" = "x86_64" ]; then
menuentry "Ubuntu Server ${UBUNTU_VER} Autoinstall (lernvirt, amd64)" {
    set root=(tftp)
    linux /amd64/vmlinuz \\
      ip=dhcp \\
      url=http://${PXE_IP}/linux/ubuntu/noble/amd64/${AMD64_ISO} \\
      autoinstall debug \\
      cloud-config-url=http://${PXE_IP}/autoinstall/user-data \\
      ---
    initrd /amd64/initrd
}

menuentry "Ubuntu BusyBox-Shell (amd64)" {
    set root=(tftp)
    linux /amd64/vmlinuz \\
      ip=dhcp \\
      url=http://${PXE_IP}/linux/ubuntu/noble/amd64/${AMD64_ISO} \\
      autoinstall debug \\
      cloud-config-url=http://${PXE_IP}/autoinstall/user-data \\
      toram \\
      break \\
      ---
    initrd /amd64/initrd
}
fi

if [ "\$grub_cpu" = "arm64" -o "\$grub_cpu" = "aarch64" ]; then
menuentry "Ubuntu Server ${UBUNTU_VER} Autoinstall (lernvirt, arm64)" {
    set root=(tftp)
    linux /arm64/vmlinuz \\
      ip=dhcp \\
      url=http://${PXE_IP}/linux/ubuntu/noble/arm64/${ARM64_ISO} \\
      autoinstall debug \\
      cloud-config-url=http://${PXE_IP}/autoinstall/user-data \\
      ---
    initrd /arm64/initrd
}

menuentry "Ubuntu BusyBox-Shell (arm64)" {
    set root=(tftp)
    linux /arm64/vmlinuz \\
      ip=dhcp \\
      url=http://${PXE_IP}/linux/ubuntu/noble/arm64/${ARM64_ISO} \\
      autoinstall debug \\
      cloud-config-url=http://${PXE_IP}/autoinstall/user-data \\
      toram \\
      break \\
      ---
    initrd /arm64/initrd
}
fi
EOF

log "ISO-Mounts loesen"
umount "${TMP_ISO_AMD64}" >/dev/null 2>&1 || warn "Konnte ${TMP_ISO_AMD64} nicht unmounten."
umount "${TMP_ISO_ARM64}" >/dev/null 2>&1 || warn "Konnte ${TMP_ISO_ARM64} nicht unmounten."

log "nginx aktivieren"
systemctl enable --now nginx >/dev/null 2>&1 || warn "Konnte nginx nicht aktivieren."

log "dnsmasq starten"
systemctl restart dnsmasq || fail "dnsmasq konnte nicht gestartet werden."

log "Fertig."
echo "Logs: ${LOGFILE}"
echo "PXE Server IP: ${PXE_IP}"
echo "TFTP Root: ${BASE}"
echo "HTTP Root: ${WWW}"
echo "AMD64 ISO: http://${PXE_IP}/linux/ubuntu/noble/amd64/${AMD64_ISO}"
echo "ARM64 ISO: http://${PXE_IP}/linux/ubuntu/noble/arm64/${ARM64_ISO}"


