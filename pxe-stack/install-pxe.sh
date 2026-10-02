#!/usr/bin/env bash
set -Eeuo pipefail
set -o pipefail

log()  { echo "[$(date -Iseconds)] INFO:  $*" >&2; }
warn() { echo "[$(date -Iseconds)] WARN:  $*" >&2; }
fail() { echo "[$(date -Iseconds)] FEHLER: $*" >&2; exit 1; }

STACK="${STACK:-ubuntu}"
VARIANT="${VARIANT:-}"
BOOT_TOOLS="${BOOT_TOOLS:-1}"
GRUB_TIMEOUT="${GRUB_TIMEOUT:-5}"
PREPARE_ASSETS="${PREPARE_ASSETS:-1}"

BASE="${TFTP_ROOT:-/srv/tftp}"
WWW="${HTTP_ROOT:-/var/www/html}"
LOGFILE="${PXE_LOGFILE:-/var/log/dnsmasq-pxe.log}"
INSTALL_DISK="${INSTALL_DISK:-/dev/nvme0n1}"

UBUNTU_VER="${UBUNTU_VERSION:-24.04.4}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
ALPINE_VERSION="${ALPINE_VERSION:-3.22}"

SSH_KEY_FILE="${SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}"
SSH_PUBLIC_KEY_URL="${SSH_PUBLIC_KEY_URL:-}"
SSH_KEY_REQUIRED="${SSH_KEY_REQUIRED:-1}"

PXE_STACK_ARCHIVE_URL="${PXE_STACK_ARCHIVE_URL:-https://github.com/mc-b/lernvirt/archive/refs/heads/main.tar.gz}"
PXE_STACK_SOURCE_DIR="${PXE_STACK_SOURCE_DIR:-}"

TMP_ISO_BASE="/tmp/pxe-iso"
TMP_ISO_AMD64="${TMP_ISO_BASE}/amd64"
TMP_ISO_ARM64="${TMP_ISO_BASE}/arm64"
TMP_WORK=""

cleanup() {
  for mp in "${TMP_ISO_AMD64:-}" "${TMP_ISO_ARM64:-}"; do
    if [ -n "${mp}" ] && mountpoint -q "${mp}" 2>/dev/null; then
      umount "${mp}" >/dev/null 2>&1 || true
    fi
  done
  if [ -n "${TMP_WORK:-}" ] && [ -d "$TMP_WORK" ]; then
    rm -rf "$TMP_WORK"
  fi
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

set_config_value() {
  local file="$1" key="$2" value="$3"
  local escaped="${value//\/\\}"
  escaped="${escaped//\"/\\\"}"

  if grep -qE "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*$|${key}=\"${escaped}\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$escaped" >>"$file"
  fi
}

inject_ssh_key_into_userdata() {
  local pub_key=""
  local file

  [ -r "$SSH_KEY_FILE" ] || {
    warn "SSH Public Key fehlt: $SSH_KEY_FILE"
    return 0
  }

  pub_key="$(cat "$SSH_KEY_FILE")"
  shopt -s nullglob
  local files=("${WWW}"/autoinstall/user-data*)
  shopt -u nullglob

  for file in "${files[@]}"; do
    [ -f "$file" ] || continue

    if grep -Fq "$pub_key" "$file"; then
      continue
    fi

    if grep -Eq '^[[:space:]]*-[[:space:]]+ssh-rsa .* insecure@lerncloud[[:space:]]*$' "$file"; then
      log "Injektiere SSH-Key in $(basename "$file")"
      sed -i "\|^[[:space:]]*-[[:space:]]*ssh-rsa .* insecure@lerncloud[[:space:]]*$|a\\      - ${pub_key}" "$file"
    else
      warn "Kein 'insecure@lerncloud'-Referenzkey in $file gefunden; Datei bleibt unverändert."
    fi
  done
}

### ROOT CHECK ###
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  fail "Bitte als root/sudo ausfuehren."
fi

### REQUIREMENTS / PACKAGES ###
export DEBIAN_FRONTEND=noninteractive

log "APT Index aktualisieren"
apt-get update -y || fail "apt-get update fehlgeschlagen."

log "Pakete installieren"
for pkg in \
  ca-certificates curl dnsmasq git nginx openssh-client \
  wget unzip syslinux-common grub-common grub-efi-amd64-bin; do
  install_pkg_if_missing "$pkg"
done

for cmd in ip awk sed wget curl mount umount cp mkdir ssh-keygen systemctl dpkg mountpoint tar; do
  require_cmd "$cmd"
done

### AKTIVES NETZWERK-INTERFACE & IP ERMITTELN ###
# Bewusst aus der bestehenden lernvirt/pxe/install-pxe.sh übernommen.
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

log "Verwende Interface: ${IFACE}, IP: ${PXE_IP}, Netz: ${SUBNET}/${PREFIX}"

### pxe-stack QUELLEN LADEN ###
TMP_WORK="$(mktemp -d)"
tmp="$TMP_WORK"
src=""
repo_root=""

if [ -n "$PXE_STACK_SOURCE_DIR" ]; then
  src="$(readlink -f "$PXE_STACK_SOURCE_DIR")"
  [ -d "$src" ] || fail "PXE_STACK_SOURCE_DIR existiert nicht: $src"
  repo_root="$(dirname "$src")"
else
  log "pxe-stack Quellen laden"
  curl -fsSL --retry 5 --retry-delay 3 "$PXE_STACK_ARCHIVE_URL" -o "$tmp/lernvirt.tar.gz" \
    || fail "Konnte pxe-stack Quellen nicht laden: $PXE_STACK_ARCHIVE_URL"
  tar -xzf "$tmp/lernvirt.tar.gz" -C "$tmp" || fail "Konnte Quellarchiv nicht entpacken."
  src="$(find "$tmp" -mindepth 2 -maxdepth 2 -type d -name pxe-stack -print -quit)"
  [ -n "$src" ] && [ -d "$src" ] || fail "pxe-stack/ im Quellarchiv nicht gefunden."
  repo_root="$(dirname "$src")"
fi

### VERZEICHNISSE / PXE-STACK INSTALLIEREN ###
log "Verzeichnisse anlegen"
mkdir -p \
  "$BASE/bin" \
  "$BASE/config" \
  "$BASE/grub/stacks" \
  "$BASE/grub/x86_64-efi" \
  "$BASE/grub/arm64-efi" \
  "$BASE/amd64" \
  "$BASE/arm64" \
  "$WWW/autoinstall" \
  "$WWW/linux/ubuntu/$UBUNTU_CODENAME/amd64" \
  "$WWW/linux/ubuntu/$UBUNTU_CODENAME/arm64" \
  "$TMP_ISO_AMD64" \
  "$TMP_ISO_ARM64" \
  "$(dirname "$LOGFILE")"

log "PXE Stack-Dateien installieren"
install -m 0644 "$src/grub/grub.cfg" "$BASE/grub/grub.cfg"
install -m 0644 "$src/grub/boot-tools.cfg" "$BASE/grub/boot-tools.cfg"

shopt -s nullglob
stack_files=("$src"/grub/stacks/*.cfg)
bin_files=("$src"/bin/*)
shopt -u nullglob

((${#stack_files[@]} > 0)) || fail "Keine GRUB-Basis-Stacks gefunden."
((${#bin_files[@]} > 0)) || fail "Keine PXE-Hilfsscripts gefunden."

for f in "${stack_files[@]}"; do
  install -m 0644 "$f" "$BASE/grub/stacks/$(basename "$f")"
done
for f in "${bin_files[@]}"; do
  [ -f "$f" ] || continue
  install -m 0755 "$f" "$BASE/bin/$(basename "$f")"
done

RACK_CONFIG="$BASE/config/rack.conf"
if [ ! -e "$RACK_CONFIG" ]; then
  cat >"$RACK_CONFIG" <<EOF_RACK
PXE_SERVER="${PXE_IP}"
PXE_INTERFACE="${IFACE}"
PXE_NETWORK="${SUBNET}"
PXE_NETMASK="${NETMASK}"

TFTP_ROOT="${BASE}"
HTTP_ROOT="${WWW}"
INSTALL_DISK="${INSTALL_DISK}"

UBUNTU_VERSION="${UBUNTU_VER}"
UBUNTU_CODENAME="${UBUNTU_CODENAME}"
ALPINE_VERSION="${ALPINE_VERSION}"
BOOT_TOOLS="${BOOT_TOOLS}"
GRUB_TIMEOUT="${GRUB_TIMEOUT}"

SSH_KEY_FILE="${SSH_KEY_FILE}"
SSH_PUBLIC_KEY_URL="${SSH_PUBLIC_KEY_URL}"

HOSTS=(
    "*|${STACK}|${VARIANT}"
)
EOF_RACK
else
  log "Bestehendes $RACK_CONFIG bleibt erhalten; Netzwerkwerte werden aktualisiert."
  set_config_value "$RACK_CONFIG" PXE_SERVER "$PXE_IP"
  set_config_value "$RACK_CONFIG" PXE_INTERFACE "$IFACE"
  set_config_value "$RACK_CONFIG" PXE_NETWORK "$SUBNET"
  set_config_value "$RACK_CONFIG" PXE_NETMASK "$NETMASK"
  set_config_value "$RACK_CONFIG" TFTP_ROOT "$BASE"
  set_config_value "$RACK_CONFIG" HTTP_ROOT "$WWW"
fi

# Ab hier gelten bei Wiederholungsinstallationen die Werte aus rack.conf.
# shellcheck disable=SC1090
source "$RACK_CONFIG"

### AUTOINSTALL BASIS ###
for profile in user-data user-data-reset; do
  if [ ! -e "$WWW/autoinstall/$profile" ]; then
    install -m 0644 "$src/autoinstall/$profile" "$WWW/autoinstall/$profile"
  fi
done

### SSH-KEY: bestehende Originalfunktion plus optionale URL aus pxe-stack ###
log "SSH Public Key vorbereiten"
if ! PXE_STACK_REPO_ROOT="$repo_root" \
     SSH_KEY_FILE="$SSH_KEY_FILE" \
     SSH_PUBLIC_KEY_URL="$SSH_PUBLIC_KEY_URL" \
     "$BASE/bin/prepare-ssh-key"; then
  if [ "$SSH_KEY_REQUIRED" = "1" ]; then
    fail "SSH Public Key konnte nicht vorbereitet werden."
  fi
  warn "SSH Public Key wurde nicht eingerichtet."
fi

### HOSTREGELN / ASSETS ###
log "GRUB Host-/Runtime-Konfiguration rendern"
"$BASE/bin/pxe-render"

if [ "$PREPARE_ASSETS" = "1" ]; then
  log "Images/Assets fuer aktive Basis-Stacks vorbereiten"
  PXE_STACK_REPO_ROOT="$repo_root" "$BASE/bin/pxe-prepare"
fi

# pxe-prepare importiert ggf. user-data-cna, user-data-cna-full, platen usw.
# Erst danach den SSH-Key wie im bisherigen Installer in die Autoinstall-Dateien einfügen.
inject_ssh_key_into_userdata

### GRUB-MODULE / UEFI-BOOTLOADER ###
AMD64_ISO="$WWW/linux/ubuntu/$UBUNTU_CODENAME/amd64/ubuntu-${UBUNTU_VER}-live-server-amd64.iso"
ARM64_ISO="$WWW/linux/ubuntu/$UBUNTU_CODENAME/arm64/ubuntu-${UBUNTU_VER}-live-server-arm64.iso"

if [ "$PREPARE_ASSETS" = "1" ]; then
  [ -s "$AMD64_ISO" ] || fail "AMD64 ISO fehlt nach Asset-Vorbereitung: $AMD64_ISO"
  [ -s "$ARM64_ISO" ] || fail "ARM64 ISO fehlt nach Asset-Vorbereitung: $ARM64_ISO"
fi

log "GRUB-Module fuer x86_64 kopieren"
if [ -d /usr/lib/grub/x86_64-efi ]; then
  cp -a /usr/lib/grub/x86_64-efi/. "$BASE/grub/x86_64-efi/" 2>/dev/null \
    || warn "Konnte x86_64-GRUB-Module nicht vollstaendig kopieren."
else
  warn "Verzeichnis /usr/lib/grub/x86_64-efi nicht gefunden."
fi

log "x86_64 EFI-Bootloader bereitstellen"
if copy_first_existing "$BASE/grubx64.efi" \
  /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed \
  /usr/lib/shim/shimx64.efi.signed \
  /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi; then
  log "x86_64 EFI-Bootloader bereitgestellt."
elif [ -s "$AMD64_ISO" ]; then
  mountpoint -q "$TMP_ISO_AMD64" && umount "$TMP_ISO_AMD64" || true
  mount -o loop,ro "$AMD64_ISO" "$TMP_ISO_AMD64" || fail "Konnte AMD64 ISO nicht mounten."
  copy_first_existing "$BASE/grubx64.efi" \
    "$TMP_ISO_AMD64/EFI/BOOT/BOOTX64.EFI" \
    "$TMP_ISO_AMD64/efi/boot/bootx64.efi" \
    || fail "Keinen x86_64 EFI-Bootloader gefunden."
  umount "$TMP_ISO_AMD64" || true
  log "x86_64 EFI-Bootloader aus Ubuntu ISO bereitgestellt."
else
  fail "Keinen x86_64 EFI-Bootloader gefunden."
fi

# ARM64-Modul und Bootloader stammen wie beim bestehenden Installer aus dem
# Ubuntu-ARM64-ISO. Bei PREPARE_ASSETS=0 bleibt ARM64 optional, falls das ISO
# nicht bereits vorhanden ist.
if [ -s "$ARM64_ISO" ]; then
  log "ARM64 GRUB-Module/EFI-Bootloader aus Ubuntu ISO bereitstellen"
  mountpoint -q "$TMP_ISO_ARM64" && umount "$TMP_ISO_ARM64" || true
  mount -o loop,ro "$ARM64_ISO" "$TMP_ISO_ARM64" || fail "Konnte ARM64 ISO nicht mounten."

  if [ -d "$TMP_ISO_ARM64/boot/grub/arm64-efi" ]; then
    cp -a "$TMP_ISO_ARM64/boot/grub/arm64-efi/." "$BASE/grub/arm64-efi/" 2>/dev/null \
      || warn "Konnte ARM64-GRUB-Module nicht vollstaendig kopieren."
  else
    fail "ARM64-GRUB-Module im ISO nicht gefunden: $TMP_ISO_ARM64/boot/grub/arm64-efi"
  fi

  if copy_first_existing "$BASE/grubaa64.efi" \
    "$TMP_ISO_ARM64/efi/boot/bootaa64.efi" \
    "$TMP_ISO_ARM64/efi/boot/grubaa64.efi"; then
    log "ARM64 EFI-Bootloader bereitgestellt."
  else
    fail "Keinen ARM64 EFI-Bootloader im ISO gefunden."
  fi

  umount "$TMP_ISO_ARM64" || true
elif [ "$PREPARE_ASSETS" = "1" ]; then
  fail "ARM64 ISO fehlt: $ARM64_ISO"
else
  warn "ARM64 ISO fehlt; ARM64-PXE wird in diesem Lauf nicht aktualisiert."
fi

### DNSMASQ - AUS BESTEHENDER pxe/install-pxe.sh ###
log "dnsmasq stoppen (falls aktiv)"
systemctl stop dnsmasq >/dev/null 2>&1 || true

# Alte Konfiguration aus frueheren pxe-stack-Versionen darf nicht parallel geladen werden.
rm -f /etc/dnsmasq.d/pxe-stack.conf

log "dnsmasq ProxyDHCP konfigurieren"
cat >/etc/dnsmasq.d/pxe.conf <<EOF_DNSMASQ
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
EOF_DNSMASQ

dnsmasq --test || fail "dnsmasq Konfiguration ist ungueltig."

### NGINX - WIE IM BESTEHENDEN INSTALLER AUF PORT 80 ###
# Frühere pxe-stack-Versionen legten eine eigene Site an. Diese wird entfernt,
# danach wird wieder die Ubuntu/nginx-Standard-Site mit /var/www/html verwendet.
if [ -L /etc/nginx/sites-enabled/pxe-stack ] || [ -e /etc/nginx/sites-enabled/pxe-stack ]; then
  rm -f /etc/nginx/sites-enabled/pxe-stack
fi
if [ -f /etc/nginx/sites-available/default ] && [ ! -e /etc/nginx/sites-enabled/default ]; then
  ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi
nginx -t || fail "nginx Konfiguration ist ungueltig."

log "nginx aktivieren"
systemctl enable --now nginx >/dev/null 2>&1 || warn "Konnte nginx nicht aktivieren."

log "dnsmasq aktivieren und starten"
systemctl enable dnsmasq >/dev/null 2>&1 || true
systemctl restart dnsmasq || fail "dnsmasq konnte nicht gestartet werden."

log "Fertig."
echo "Logs: ${LOGFILE}"
echo "PXE Server IP: ${PXE_IP}"
echo "Interface: ${IFACE}"
echo "TFTP Root: ${BASE}"
echo "HTTP Root: ${WWW}"
echo "Stack: ${STACK}${VARIANT:+ (${VARIANT})}"
echo
"$BASE/bin/pxe-show"
