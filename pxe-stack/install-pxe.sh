#!/usr/bin/env bash
set -Eeuo pipefail
set -o pipefail

# lernvirt PXE Basis
#
# Installiert und konfiguriert vollständig:
#   - dnsmasq Proxy-DHCP/TFTP
#   - nginx auf Port 80
#   - GRUB UEFI für x86_64 und ARM64
#   - Ubuntu Server ISO + Kernel/Initrd für amd64 und arm64
#   - Basis-Stacks ubuntu/cna/cna-full/platen/reset
#   - Alpine/BusyBox Boot-Tools (optional)
#   - SSH-Key und Autoinstall-Dateien
#
# SUSE, OpenShift und HAProxy werden bewusst von separaten install-*.sh
# Scripts eingerichtet.

log()  { echo "[$(date -Iseconds)] INFO:  $*" >&2; }
warn() { echo "[$(date -Iseconds)] WARN:  $*" >&2; }
fail() { echo "[$(date -Iseconds)] FEHLER: $*" >&2; exit 1; }

STACK="${STACK:-ubuntu}"
VARIANT="${VARIANT:-}"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
INSTALL_DISK="${INSTALL_DISK:-/dev/nvme0n1}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.4}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
ALPINE_VERSION="${ALPINE_VERSION:-3.22}"
BOOT_TOOLS="${BOOT_TOOLS:-1}"
GRUB_TIMEOUT="${GRUB_TIMEOUT:-5}"
SSH_KEY_FILE="${SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}"
SSH_PUBLIC_KEY_URL="${SSH_PUBLIC_KEY_URL:-}"
PXE_STACK_ARCHIVE_URL="${PXE_STACK_ARCHIVE_URL:-https://github.com/mc-b/lernvirt/archive/refs/heads/main.tar.gz}"
LOGFILE="${DNSMASQ_LOGFILE:-/var/log/dnsmasq-pxe.log}"

TMP_ISO_BASE="/tmp/pxe-stack-iso"
TMP_ISO_AMD64="${TMP_ISO_BASE}/amd64"
TMP_ISO_ARM64="${TMP_ISO_BASE}/arm64"
TMP_REPO=""

cleanup() {
    for mp in "$TMP_ISO_AMD64" "$TMP_ISO_ARM64"; do
        if mountpoint -q "$mp" 2>/dev/null; then
            umount "$mp" >/dev/null 2>&1 || true
        fi
    done
    [[ -n "$TMP_REPO" ]] && rm -rf "$TMP_REPO"
}
trap cleanup EXIT

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Bitte als root/sudo ausführen."

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Befehl nicht gefunden: $1"
}

copy_first_existing() {
    local dst="$1"
    shift
    local src
    for src in "$@"; do
        if [[ -f "$src" ]]; then
            cp -f "$src" "$dst"
            return 0
        fi
    done
    return 1
}

download_file() {
    local url="$1"
    local dst="$2"
    local part="${dst}.part"

    mkdir -p "$(dirname "$dst")"
    if [[ -s "$dst" ]]; then
        log "Bereits vorhanden: $dst"
        return 0
    fi

    log "Download: $url"
    curl -fL --retry 8 --retry-delay 4 --retry-all-errors --continue-at - \
        "$url" -o "$part" || fail "Download fehlgeschlagen: $url"
    [[ -s "$part" ]] || fail "Leerer Download: $url"
    mv -f "$part" "$dst"
}

extract_iso_assets() {
    local arch="$1"
    local iso="$2"
    local mnt="$3"
    local tftp_dir="$4"

    mkdir -p "$mnt" "$tftp_dir"
    if mountpoint -q "$mnt"; then
        umount "$mnt" || fail "Konnte bestehendes Mount nicht lösen: $mnt"
    fi

    mount -o loop,ro "$iso" "$mnt" || fail "Konnte ISO nicht mounten: $iso"
    [[ -s "$mnt/casper/vmlinuz" ]] || fail "casper/vmlinuz fehlt in $iso"
    [[ -s "$mnt/casper/initrd" ]] || fail "casper/initrd fehlt in $iso"

    install -m 0644 "$mnt/casper/vmlinuz" "$tftp_dir/vmlinuz"
    install -m 0644 "$mnt/casper/initrd" "$tftp_dir/initrd"
    log "Kernel und Initrd für $arch extrahiert."
}

valid_public_key() {
    local file="$1"
    [[ -s "$file" ]] || return 1
    grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-sha2-|sk-(ssh-ed25519|ecdsa-sha2-))' "$file"
}

prepare_ssh_key() {
    mkdir -p "$(dirname "$SSH_KEY_FILE")" "$HTTP_ROOT/ssh"

    if [[ -n "$SSH_PUBLIC_KEY_URL" ]]; then
        local tmp
        tmp="$(mktemp)"
        download_file "$SSH_PUBLIC_KEY_URL" "$tmp.key"
        mv -f "$tmp.key" "$tmp"
        valid_public_key "$tmp" || fail "Ungültiger SSH Public Key: $SSH_PUBLIC_KEY_URL"
        install -m 0644 "$tmp" "$SSH_KEY_FILE"
        rm -f "$tmp"
    fi

    if ! valid_public_key "$SSH_KEY_FILE"; then
        if id ubuntu >/dev/null 2>&1; then
            local ssh_dir="/home/ubuntu/.ssh"
            local private="${ssh_dir}/id_rsa_lernvirt"
            install -d -m 0700 -o ubuntu -g ubuntu "$ssh_dir"
            cat >"$ssh_dir/config" <<'EOF_SSHCFG'
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
LogLevel error
User ubuntu
IdentityFile ~/.ssh/id_rsa_lernvirt
EOF_SSHCFG
            chown ubuntu:ubuntu "$ssh_dir/config"
            chmod 0400 "$ssh_dir/config"
            if [[ ! -s "$private" || ! -s "${private}.pub" ]]; then
                log "Erzeuge SSH-Key für User ubuntu"
                ssh-keygen -t rsa -b 4096 -N "" -f "$private" \
                    -C "ubuntu@lernvirt-$(date +%F)" >/dev/null
                chown ubuntu:ubuntu "$private" "${private}.pub"
                chmod 0400 "$private" "${private}.pub"
            fi
            install -m 0644 "${private}.pub" "$SSH_KEY_FILE"
        else
            local private="/etc/lernvirt/lerncloud"
            if [[ ! -s "$private" || ! -s "${private}.pub" ]]; then
                log "Erzeuge SSH-Key unter /etc/lernvirt"
                ssh-keygen -t rsa -b 4096 -N "" -f "$private" \
                    -C "lernvirt-pxe-$(date +%F)" >/dev/null
            fi
            install -m 0644 "${private}.pub" "$SSH_KEY_FILE"
        fi
    fi

    valid_public_key "$SSH_KEY_FILE" || fail "SSH Public Key konnte nicht bereitgestellt werden: $SSH_KEY_FILE"
    install -m 0644 "$SSH_KEY_FILE" "$HTTP_ROOT/ssh/lerncloud.pub"
    log "SSH Public Key: $SSH_KEY_FILE"
}

inject_public_key() {
    local file="$1"
    local pub
    [[ -s "$file" ]] || return 0
    pub="$(cat "$SSH_KEY_FILE")"

    grep -Fqx "      - $pub" "$file" && return 0
    if grep -q 'insecure@lerncloud' "$file"; then
        sed -i "\\|insecure@lerncloud|a\\      - ${pub}" "$file"
        log "SSH-Key in $(basename "$file") ergänzt."
    else
        warn "Kein insecure@lerncloud-Eintrag in $file; SSH-Key wurde dort nicht automatisch injiziert."
    fi
}

# Netzwerkermittlung absichtlich wie in der bestehenden lernvirt/pxe/install-pxe.sh.
IFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
if [[ -z "$IFACE" ]]; then
    IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /lo/ {print $2; exit}')"
fi
[[ -n "$IFACE" ]] || fail "Konnte aktives Netzwerkinterface nicht ermitteln."

CIDR="$(ip -4 addr show dev "$IFACE" 2>/dev/null | awk '/inet / {print $2}' | head -n1)"
[[ -n "$CIDR" ]] || fail "Konnte keine IPv4-Adresse für $IFACE finden."
PXE_IP="${CIDR%%/*}"
PREFIX="${CIDR##*/}"

IFS='.' read -r o1 o2 o3 o4 <<<"$PXE_IP"
IP_INT=$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))
if (( PREFIX == 0 )); then
    MASK_INT=0
else
    MASK_INT=$(( (0xFFFFFFFF << (32 - PREFIX)) & 0xFFFFFFFF ))
fi
NET_INT=$(( IP_INT & MASK_INT ))
SUBNET="$(( (NET_INT >> 24) & 255 )).$(( (NET_INT >> 16) & 255 )).$(( (NET_INT >> 8) & 255 )).$(( NET_INT & 255 ))"
NETMASK="$(( (MASK_INT >> 24) & 255 )).$(( (MASK_INT >> 16) & 255 )).$(( (MASK_INT >> 8) & 255 )).$(( MASK_INT & 255 ))"

log "Verwende Interface: $IFACE, IP: $PXE_IP, Netz: $SUBNET/$PREFIX"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    ca-certificates curl wget rsync git \
    dnsmasq nginx \
    grub-common grub-efi-amd64-bin \
    openssh-client

for cmd in ip awk sed curl mount umount mountpoint ssh-keygen systemctl; do
    require_cmd "$cmd"
done

mkdir -p \
    "$TFTP_ROOT/bin" \
    "$TFTP_ROOT/config" \
    "$TFTP_ROOT/grub/stacks" \
    "$TFTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/amd64" \
    "$TFTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/arm64" \
    "$HTTP_ROOT/autoinstall" \
    "$HTTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/amd64" \
    "$HTTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/arm64" \
    "$TMP_ISO_AMD64" "$TMP_ISO_ARM64"

# Bei lokaler Ausführung die Dateien aus demselben pxe-stack-Verzeichnis nehmen.
# Bei curl | bash werden die Quellen aus dem Repository-Archiv geladen.
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != "-" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd || true)"
fi

if [[ -n "$SCRIPT_DIR" && -r "$SCRIPT_DIR/grub/grub.cfg" && -x "$SCRIPT_DIR/bin/pxe-update" ]]; then
    SRC="$SCRIPT_DIR"
    REPO_ROOT="$(dirname "$SRC")"
    log "Verwende lokale pxe-stack Quellen: $SRC"
else
    TMP_REPO="$(mktemp -d)"
    log "Lade pxe-stack Quellen"
    download_file "$PXE_STACK_ARCHIVE_URL" "$TMP_REPO/lernvirt.tar.gz"
    tar -xzf "$TMP_REPO/lernvirt.tar.gz" -C "$TMP_REPO"
    SRC="$(find "$TMP_REPO" -mindepth 2 -maxdepth 2 -type d -name pxe-stack -print -quit)"
    [[ -n "$SRC" && -d "$SRC" ]] || fail "pxe-stack/ im Quellarchiv nicht gefunden."
    REPO_ROOT="$(dirname "$SRC")"
fi

# Nur die zwei administrativen Werkzeuge werden im laufenden System benötigt.
install -m 0755 "$SRC/bin/pxe-update" "$TFTP_ROOT/bin/pxe-update"
install -m 0755 "$SRC/bin/pxe-show" "$TFTP_ROOT/bin/pxe-show"
install -m 0644 "$SRC/grub/grub.cfg" "$TFTP_ROOT/grub/grub.cfg"
install -m 0644 "$SRC/grub/boot-tools.cfg" "$TFTP_ROOT/grub/boot-tools.cfg"
for f in "$SRC"/grub/stacks/*.cfg; do
    install -m 0644 "$f" "$TFTP_ROOT/grub/stacks/$(basename "$f")"
done

if [[ ! -e "$TFTP_ROOT/config/rack.conf" ]]; then
    cat >"$TFTP_ROOT/config/rack.conf" <<EOF_RACK
PXE_SERVER="$PXE_IP"
TFTP_ROOT="$TFTP_ROOT"
HTTP_ROOT="$HTTP_ROOT"
INSTALL_DISK="$INSTALL_DISK"
UBUNTU_VERSION="$UBUNTU_VERSION"
UBUNTU_CODENAME="$UBUNTU_CODENAME"
ALPINE_VERSION="$ALPINE_VERSION"
BOOT_TOOLS="$BOOT_TOOLS"
GRUB_TIMEOUT="$GRUB_TIMEOUT"

HOSTS=(
    "*|$STACK|$VARIANT"
)
EOF_RACK
else
    log "Bestehendes $TFTP_ROOT/config/rack.conf bleibt unverändert."
fi

# Ab jetzt ist rack.conf die zentrale Laufzeitkonfiguration.
# shellcheck disable=SC1090
source "$TFTP_ROOT/config/rack.conf"
if [[ "$PXE_SERVER" != "$PXE_IP" ]]; then
    warn "rack.conf verwendet PXE_SERVER=$PXE_SERVER, aktuell erkannt wurde $PXE_IP."
fi

prepare_ssh_key

# Basis-Autoinstall-Dateien nicht überschreiben.
for profile in user-data user-data-reset; do
    if [[ ! -s "$HTTP_ROOT/autoinstall/$profile" ]]; then
        install -m 0644 "$SRC/autoinstall/$profile" "$HTTP_ROOT/autoinstall/$profile"
    fi
done

# Bestehende lernvirt-Profile cna/cna-full/platen aus dem Repository übernehmen.
for profile in user-data-cna user-data-cna-full user-data-platen; do
    target="$HTTP_ROOT/autoinstall/$profile"
    [[ -s "$target" ]] && continue
    found="$(find "$REPO_ROOT" -type f -name "$profile" -size +0c -print -quit 2>/dev/null || true)"
    if [[ -n "$found" ]]; then
        install -m 0644 "$found" "$target"
        log "Autoinstall übernommen: $profile"
    else
        warn "Autoinstall-Datei im Repository nicht gefunden: $profile"
    fi
done

for f in "$HTTP_ROOT"/autoinstall/user-data*; do
    [[ -f "$f" ]] && inject_public_key "$f"
done

# Ubuntu Images für beide vom ursprünglichen Installer unterstützten Architekturen.
AMD64_ISO="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
ARM64_ISO="ubuntu-${UBUNTU_VERSION}-live-server-arm64.iso"
AMD64_URL="${UBUNTU_AMD64_ISO_URL:-https://mirror.init7.net/ubuntu-releases/${UBUNTU_CODENAME}/${AMD64_ISO}}"
ARM64_URL="${UBUNTU_ARM64_ISO_URL:-https://cdimage.ubuntu.com/releases/${UBUNTU_CODENAME}/release/${ARM64_ISO}}"
AMD64_ISO_PATH="$HTTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/amd64/$AMD64_ISO"
ARM64_ISO_PATH="$HTTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/arm64/$ARM64_ISO"

download_file "$AMD64_URL" "$AMD64_ISO_PATH"
download_file "$ARM64_URL" "$ARM64_ISO_PATH"
extract_iso_assets amd64 "$AMD64_ISO_PATH" "$TMP_ISO_AMD64" "$TFTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/amd64"
extract_iso_assets arm64 "$ARM64_ISO_PATH" "$TMP_ISO_ARM64" "$TFTP_ROOT/linux/ubuntu/$UBUNTU_CODENAME/arm64"

# GRUB UEFI wie im bestehenden lernvirt PXE-Installer bereitstellen.
mkdir -p "$TFTP_ROOT/grub/x86_64-efi" "$TFTP_ROOT/grub/arm64-efi"
[[ -d /usr/lib/grub/x86_64-efi ]] || fail "/usr/lib/grub/x86_64-efi fehlt."
cp -a /usr/lib/grub/x86_64-efi/. "$TFTP_ROOT/grub/x86_64-efi/"

[[ -d "$TMP_ISO_ARM64/boot/grub/arm64-efi" ]] || \
    fail "ARM64 GRUB-Module fehlen im Ubuntu ARM64 ISO."
cp -a "$TMP_ISO_ARM64/boot/grub/arm64-efi/." "$TFTP_ROOT/grub/arm64-efi/"

copy_first_existing "$TFTP_ROOT/grubx64.efi" \
    /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed \
    /usr/lib/shim/shimx64.efi.signed \
    /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
    "$TMP_ISO_AMD64/EFI/BOOT/BOOTX64.EFI" \
    "$TMP_ISO_AMD64/efi/boot/bootx64.efi" || \
    fail "Keinen x86_64 EFI-Bootloader gefunden."

copy_first_existing "$TFTP_ROOT/grubaa64.efi" \
    "$TMP_ISO_ARM64/efi/boot/bootaa64.efi" \
    "$TMP_ISO_ARM64/efi/boot/grubaa64.efi" \
    "$TMP_ISO_ARM64/EFI/BOOT/BOOTAA64.EFI" || \
    fail "Keinen ARM64 EFI-Bootloader im Ubuntu ISO gefunden."

# Alpine/BusyBox sind optionale Boot-Tools, keine Installationsstacks.
if [[ "$BOOT_TOOLS" == "1" ]]; then
    ALPINE_BASE="${ALPINE_NETBOOT_URL:-https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/x86_64/netboot}"
    mkdir -p "$TFTP_ROOT/linux/alpine" "$HTTP_ROOT/linux/alpine"
    download_file "$ALPINE_BASE/vmlinuz-lts" "$TFTP_ROOT/linux/alpine/vmlinuz-lts"
    download_file "$ALPINE_BASE/initramfs-lts" "$TFTP_ROOT/linux/alpine/initramfs-lts"
    download_file "$ALPINE_BASE/modloop-lts" "$HTTP_ROOT/linux/alpine/modloop-lts"
fi

# Proxy-DHCP/TFTP: absichtlich keine feste interface=... Vorgabe.
# Das entspricht der funktionierenden lernvirt/pxe/install-pxe.sh.
rm -f /etc/dnsmasq.d/pxe-stack.conf
cat >/etc/dnsmasq.d/pxe.conf <<EOF_DNSMASQ
port=0

dhcp-range=${SUBNET},proxy,${NETMASK}

# interface=${IFACE}
# bind-interfaces
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
tftp-root=${TFTP_ROOT}

log-dhcp
log-facility=${LOGFILE}
EOF_DNSMASQ

dnsmasq --test || fail "dnsmasq-Konfiguration ist ungültig."

# nginx bleibt auf Port 80. Andere Add-ons ändern diese Site nicht.
cat >/etc/nginx/sites-available/pxe-stack <<EOF_NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root ${HTTP_ROOT};

    location / {
        try_files \$uri \$uri/ =404;
        autoindex on;
    }
}
EOF_NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/pxe-stack /etc/nginx/sites-enabled/pxe-stack
nginx -t || fail "nginx-Konfiguration ist ungültig."

"$TFTP_ROOT/bin/pxe-update"

systemctl enable nginx dnsmasq >/dev/null
systemctl restart nginx
systemctl restart dnsmasq || fail "dnsmasq konnte nicht gestartet werden."

log "PXE-Basis fertig."
echo "PXE Server : $PXE_IP"
echo "Interface  : $IFACE"
echo "TFTP       : $TFTP_ROOT"
echo "HTTP       : http://$PXE_IP/"
echo "dnsmasq Log: $LOGFILE"
echo
"$TFTP_ROOT/bin/pxe-show"
