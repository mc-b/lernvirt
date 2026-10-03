#!/usr/bin/env bash
set -Eeuo pipefail

# lernvirt PXE Add-on: SUSE Harvester / SUSE Virtualization
#
# Voraussetzung:
#   pxe-stack/install-pxe.sh wurde bereits ausgeführt.
#
# Standard:
#   Harvester 1.8.2 AMD64 wird von releases.rancher.com geladen.
#   Pro Host wird die Harvester-YAML automatisch aus rack.conf erzeugt.
#
# Minimaler erster Aufruf:
#   sudo HARVESTER_VIP=192.168.1.110 ./install-harvester.sh
#
# Wichtige Overrides:
#   HARVESTER_VERSION=1.8.2
#   HARVESTER_ARCH=amd64          # amd64 oder arm64
#   HARVESTER_VIP=192.168.1.110  # Cluster-VIP, beim ersten Aufruf erforderlich
#   HARVESTER_DEVICE=/dev/nvme0n1
#   HARVESTER_INTERFACE=enp2s0    # Name wird beim PXE-Boot via ifname= gesetzt
#   HARVESTER_TOKEN=...
#   HARVESTER_PASSWORD=...
#   HARVESTER_SKIPCHECKS=true    # Production-Hardwarechecks nur als Warnung
#   HARVESTER_FORCE=1
#
# HOSTS-Syntax danach:
#   "AA:BB:CC:DD:EE:01|harvester|create:harvester-01"
#   "AA:BB:CC:DD:EE:02|harvester|join:harvester-02"

log()  { printf '[install-harvester] %s\n' "$*"; }
warn() { printf '[install-harvester] WARNUNG: %s\n' "$*" >&2; }
fail() { printf '[install-harvester] FEHLER: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "install-harvester.sh muss als root laufen."

CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
[[ -r "$CONFIG" ]] || fail "PXE-Basis fehlt: $CONFIG. Zuerst install-pxe.sh ausführen."

# Environment-Werte vor dem Einlesen von rack.conf sichern, damit explizite
# Overrides die bereits gespeicherte Konfiguration übersteuern können.
ENV_TFTP_ROOT="${TFTP_ROOT-}"
ENV_HTTP_ROOT="${HTTP_ROOT-}"
ENV_CACHE_DIR="${PXE_CACHE_DIR-}"
ENV_PXE_SERVER="${PXE_SERVER-}"
ENV_HARVESTER_VERSION="${HARVESTER_VERSION-}"
ENV_HARVESTER_ARCH="${HARVESTER_ARCH-}"
ENV_HARVESTER_VIP="${HARVESTER_VIP-}"
ENV_HARVESTER_DEVICE="${HARVESTER_DEVICE-}"
ENV_HARVESTER_INTERFACE="${HARVESTER_INTERFACE-}"
ENV_HARVESTER_TOKEN="${HARVESTER_TOKEN-}"
ENV_HARVESTER_PASSWORD="${HARVESTER_PASSWORD-}"
ENV_HARVESTER_SSH_KEY_FILE="${HARVESTER_SSH_KEY_FILE-}"
ENV_HARVESTER_NTP_SERVERS="${HARVESTER_NTP_SERVERS-}"
ENV_HARVESTER_SKIPCHECKS="${HARVESTER_SKIPCHECKS-}"
ENV_HARVESTER_BASE_URL="${HARVESTER_BASE_URL-}"
ENV_HARVESTER_FORCE="${HARVESTER_FORCE-}"

# shellcheck disable=SC1090
source "$CONFIG"

[[ -n "$ENV_TFTP_ROOT" ]] && TFTP_ROOT="$ENV_TFTP_ROOT"
[[ -n "$ENV_HTTP_ROOT" ]] && HTTP_ROOT="$ENV_HTTP_ROOT"
[[ -n "$ENV_PXE_SERVER" ]] && PXE_SERVER="$ENV_PXE_SERVER"

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
PXE_CACHE_DIR="${ENV_CACHE_DIR:-${PXE_CACHE_DIR:-/var/cache/pxe-stack}}"
PXE_SERVER="${PXE_SERVER:-}"
INSTALL_DISK="${INSTALL_DISK:-/dev/nvme0n1}"

HARVESTER_VERSION="${ENV_HARVESTER_VERSION:-${HARVESTER_VERSION:-1.8.2}}"
HARVESTER_ARCH="${ENV_HARVESTER_ARCH:-${HARVESTER_ARCH:-amd64}}"
HARVESTER_VIP="${ENV_HARVESTER_VIP:-${HARVESTER_VIP:-}}"
HARVESTER_DEVICE="${ENV_HARVESTER_DEVICE:-${HARVESTER_DEVICE:-$INSTALL_DISK}}"
HARVESTER_INTERFACE="${ENV_HARVESTER_INTERFACE:-${HARVESTER_INTERFACE:-enp2s0}}"
HARVESTER_TOKEN="${ENV_HARVESTER_TOKEN:-${HARVESTER_TOKEN:-}}"
HARVESTER_PASSWORD="${ENV_HARVESTER_PASSWORD:-${HARVESTER_PASSWORD:-}}"
HARVESTER_SSH_KEY_FILE="${ENV_HARVESTER_SSH_KEY_FILE:-${HARVESTER_SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}}"
HARVESTER_NTP_SERVERS="${ENV_HARVESTER_NTP_SERVERS:-${HARVESTER_NTP_SERVERS:-0.suse.pool.ntp.org 1.suse.pool.ntp.org}}"
HARVESTER_SKIPCHECKS="${ENV_HARVESTER_SKIPCHECKS:-${HARVESTER_SKIPCHECKS:-true}}"
HARVESTER_BASE_URL="${ENV_HARVESTER_BASE_URL:-${HARVESTER_BASE_URL:-https://releases.rancher.com/harvester}}"
HARVESTER_FORCE="${ENV_HARVESTER_FORCE:-${HARVESTER_FORCE:-0}}"

[[ -n "$PXE_SERVER" ]] || fail "PXE_SERVER fehlt in $CONFIG."
[[ -d "$TFTP_ROOT/grub/stacks" ]] || fail "GRUB-Stack-Verzeichnis fehlt: $TFTP_ROOT/grub/stacks"
[[ -r "$TFTP_ROOT/grub/grub.cfg" ]] || fail "GRUB-Basiskonfiguration fehlt: $TFTP_ROOT/grub/grub.cfg"
[[ -x "$TFTP_ROOT/bin/pxe-update" ]] || fail "pxe-update fehlt. Zuerst install-pxe.sh ausführen."
[[ -n "$HARVESTER_VIP" ]] || fail "HARVESTER_VIP fehlt. Beispiel: sudo HARVESTER_VIP=192.168.1.110 ./install-harvester.sh"
[[ -r "$HARVESTER_SSH_KEY_FILE" ]] || fail "SSH-Key nicht lesbar: $HARVESTER_SSH_KEY_FILE"

case "$HARVESTER_ARCH" in
    amd64|arm64) ;;
    *) fail "Nicht unterstützte HARVESTER_ARCH: $HARVESTER_ARCH (unterstützt: amd64, arm64)" ;;
esac

case "${HARVESTER_SKIPCHECKS,,}" in
    true|1|yes|on) HARVESTER_SKIPCHECKS=true ;;
    false|0|no|off) HARVESTER_SKIPCHECKS=false ;;
    *) fail "HARVESTER_SKIPCHECKS muss true oder false sein: $HARVESTER_SKIPCHECKS" ;;
esac

[[ "$HARVESTER_INTERFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || \
    fail "Ungültiger HARVESTER_INTERFACE: $HARVESTER_INTERFACE"

for cmd in curl sha512sum awk grep install tar cmp; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Befehl fehlt: $cmd"
done

random_hex() {
    local bytes="$1"
    od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

[[ -n "$HARVESTER_TOKEN" ]] || HARVESTER_TOKEN="$(random_hex 24)"
[[ -n "$HARVESTER_PASSWORD" ]] || HARVESTER_PASSWORD="$(random_hex 12)"

case "$HARVESTER_VIP" in
    *[!0-9.]*|'') fail "HARVESTER_VIP muss eine IPv4-Adresse sein: $HARVESTER_VIP" ;;
esac

# Harvester-Werte zentral in rack.conf persistieren. Token und Passwort werden
# beim ersten Aufruf automatisch erzeugt und bei weiteren Aufrufen beibehalten.
set_config_var() {
    local name="$1"
    local value="$2"
    local tmp current_line
    local replaced=0

    tmp="$(mktemp "${CONFIG}.XXXXXX")"

    # Nicht via awk -v schreiben: Shell-Escapes wie "\ " in mit %q
    # erzeugten Werten würden von awk interpretiert und beschädigt.
    while IFS= read -r current_line || [[ -n "$current_line" ]]; do
        if [[ "$current_line" == "${name}="* && "$replaced" -eq 0 ]]; then
            printf '%s=%q\n' "$name" "$value" >>"$tmp"
            replaced=1
        else
            printf '%s\n' "$current_line" >>"$tmp"
        fi
    done <"$CONFIG"

    if [[ "$replaced" -eq 0 ]]; then
        printf '%s=%q\n' "$name" "$value" >>"$tmp"
    fi

    chmod --reference="$CONFIG" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
    chown --reference="$CONFIG" "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$CONFIG"
}

if [[ ! -e "${CONFIG}.pre-harvester" ]]; then
    cp -a "$CONFIG" "${CONFIG}.pre-harvester"
fi

set_config_var HARVESTER_VERSION "$HARVESTER_VERSION"
set_config_var HARVESTER_ARCH "$HARVESTER_ARCH"
set_config_var HARVESTER_VIP "$HARVESTER_VIP"
set_config_var HARVESTER_DEVICE "$HARVESTER_DEVICE"
set_config_var HARVESTER_INTERFACE "$HARVESTER_INTERFACE"
set_config_var HARVESTER_TOKEN "$HARVESTER_TOKEN"
set_config_var HARVESTER_PASSWORD "$HARVESTER_PASSWORD"
set_config_var HARVESTER_SSH_KEY_FILE "$HARVESTER_SSH_KEY_FILE"
set_config_var HARVESTER_NTP_SERVERS "$HARVESTER_NTP_SERVERS"
set_config_var HARVESTER_SKIPCHECKS "$HARVESTER_SKIPCHECKS"

# Die Harvester-Integration benötigt die dazu passende pxe-update- und grub.cfg-
# Version. Bei lokaler Ausführung werden die Dateien aus demselben Paket genommen.
# Nach dem Commit ins Repository funktioniert derselbe Ablauf auch via curl | bash.
TMP_REPO=""
cleanup() {
    if [[ -n "$TMP_REPO" ]]; then
        rm -rf "$TMP_REPO"
    fi
    return 0
}
trap cleanup EXIT

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != "-" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd || true)"
fi

SRC=""
if [[ -n "$SCRIPT_DIR" && -r "$SCRIPT_DIR/bin/pxe-update" && -r "$SCRIPT_DIR/grub/grub.cfg" ]]; then
    SRC="$SCRIPT_DIR"
else
    TMP_REPO="$(mktemp -d)"
    archive="$TMP_REPO/lernvirt.tar.gz"
    repo_url="${PXE_STACK_ARCHIVE_URL:-https://github.com/mc-b/lernvirt/archive/refs/heads/main.tar.gz}"
    log "Lade aktuelle pxe-stack Quellen"
    curl -fL --retry 5 --retry-delay 3 "$repo_url" -o "$archive" \
        || fail "pxe-stack Quellen konnten nicht geladen werden. Alternativ das bereitgestellte Paket lokal ausführen."
    tar -xzf "$archive" -C "$TMP_REPO"
    SRC="$(find "$TMP_REPO" -mindepth 2 -maxdepth 2 -type d -name pxe-stack -print -quit)"
fi

[[ -n "$SRC" && -r "$SRC/bin/pxe-update" && -r "$SRC/grub/grub.cfg" ]] || \
    fail "Passende pxe-stack Quellen nicht gefunden."
grep -q 'HARVESTER_CONFIG_DIR' "$SRC/bin/pxe-update" || \
    fail "Die gefundene pxe-update-Version enthält die Harvester-Integration noch nicht. Bitte das bereitgestellte Gesamtpaket verwenden."
grep -q 'COS_STATE' "$SRC/grub/grub.cfg" || \
    fail "Die gefundene grub.cfg enthält die Harvester-Local-Boot-Erkennung noch nicht. Bitte das bereitgestellte Gesamtpaket verwenden."

if ! cmp -s "$SRC/bin/pxe-update" "$TFTP_ROOT/bin/pxe-update"; then
    [[ -e "$TFTP_ROOT/bin/pxe-update.pre-harvester" ]] || \
        cp -a "$TFTP_ROOT/bin/pxe-update" "$TFTP_ROOT/bin/pxe-update.pre-harvester"
    install -m 0755 "$SRC/bin/pxe-update" "$TFTP_ROOT/bin/pxe-update"
    log "pxe-update aktualisiert"
fi

if ! cmp -s "$SRC/grub/grub.cfg" "$TFTP_ROOT/grub/grub.cfg"; then
    [[ -e "$TFTP_ROOT/grub/grub.cfg.pre-harvester" ]] || \
        cp -a "$TFTP_ROOT/grub/grub.cfg" "$TFTP_ROOT/grub/grub.cfg.pre-harvester"
    install -m 0644 "$SRC/grub/grub.cfg" "$TFTP_ROOT/grub/grub.cfg"
    log "grub.cfg aktualisiert"
fi

VERSION_TAG="v${HARVESTER_VERSION}"
RELEASE_URL="${HARVESTER_BASE_URL%/}/${VERSION_TAG}"
OFFICIAL_ISO="harvester-${VERSION_TAG}-${HARVESTER_ARCH}.iso"
OFFICIAL_KERNEL="harvester-${VERSION_TAG}-vmlinuz-${HARVESTER_ARCH}"
OFFICIAL_INITRD="harvester-${VERSION_TAG}-initrd-${HARVESTER_ARCH}"
OFFICIAL_ROOTFS="harvester-${VERSION_TAG}-rootfs-${HARVESTER_ARCH}.squashfs"
OFFICIAL_SHA512="harvester-${VERSION_TAG}-${HARVESTER_ARCH}.sha512"

TFTP_VERSION_DIR="$TFTP_ROOT/linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}"
HTTP_VERSION_DIR="$HTTP_ROOT/linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}"
CACHE_DIR="$PXE_CACHE_DIR/harvester/${VERSION_TAG}/${HARVESTER_ARCH}"

TFTP_KERNEL="$TFTP_VERSION_DIR/vmlinuz"
TFTP_INITRD="$TFTP_VERSION_DIR/initrd"
HTTP_ISO="$HTTP_VERSION_DIR/harvester.iso"
HTTP_ROOTFS="$HTTP_VERSION_DIR/rootfs.squashfs"
CHECKSUM_FILE="$CACHE_DIR/$OFFICIAL_SHA512"

mkdir -p "$TFTP_VERSION_DIR" "$HTTP_VERSION_DIR" "$CACHE_DIR" "$TFTP_ROOT/grub/stacks"

download_file() {
    local url="$1"
    local dst="$2"
    local part="${dst}.part"

    mkdir -p "$(dirname "$dst")"
    if [[ "$HARVESTER_FORCE" == "1" ]]; then
        rm -f "$dst" "$part"
    fi
    if [[ -s "$dst" ]]; then
        log "Bereits vorhanden: $dst"
        return 0
    fi

    log "Download: $url"
    curl -fL --retry 8 --retry-delay 5 --retry-all-errors --continue-at - \
        "$url" -o "$part" || fail "Download fehlgeschlagen: $url"
    [[ -s "$part" ]] || fail "Leerer Download: $url"
    mv -f "$part" "$dst"
}

checksum_for() {
    local official_name="$1"
    local expected=""
    local hashes=()

    expected="$(awk -v f="$official_name" '
        $1 ~ /^[0-9A-Fa-f]{128}$/ {
            n=$2
            sub(/^\\*/, "", n)
            sub(/^\.\//, "", n)
            if (n == f) { print tolower($1); exit }
        }
    ' "$CHECKSUM_FILE")"

    if [[ -n "$expected" ]]; then
        printf '%s\n' "$expected"
        return 0
    fi

    mapfile -t hashes < <(awk '$1 ~ /^[0-9A-Fa-f]{128}$/ {print tolower($1)}' "$CHECKSUM_FILE")
    if [[ "$official_name" == "$OFFICIAL_ISO" && ${#hashes[@]} -eq 1 ]]; then
        printf '%s\n' "${hashes[0]}"
        return 0
    fi
    return 1
}

verify_required() {
    local official_name="$1"
    local local_file="$2"
    local expected actual
    expected="$(checksum_for "$official_name")" || \
        fail "Keine SHA512-Prüfsumme für $official_name in $CHECKSUM_FILE gefunden."
    actual="$(sha512sum "$local_file" | awk '{print tolower($1)}')"
    [[ "$actual" == "$expected" ]]
}

verify_optional() {
    local official_name="$1"
    local local_file="$2"
    local expected actual
    if ! expected="$(checksum_for "$official_name")"; then
        return 0
    fi
    actual="$(sha512sum "$local_file" | awk '{print tolower($1)}')"
    [[ "$actual" == "$expected" ]] || fail "SHA512-Prüfung fehlgeschlagen: $official_name"
}

log "Lade offizielle SHA512-Prüfsumme"
download_file "$RELEASE_URL/$OFFICIAL_SHA512" "$CHECKSUM_FILE"

download_file "$RELEASE_URL/$OFFICIAL_ISO" "$HTTP_ISO"
if ! verify_required "$OFFICIAL_ISO" "$HTTP_ISO"; then
    warn "Vorhandenes ISO hat eine falsche SHA512-Prüfsumme; lade es neu."
    rm -f "$HTTP_ISO" "${HTTP_ISO}.part"
    download_file "$RELEASE_URL/$OFFICIAL_ISO" "$HTTP_ISO"
    verify_required "$OFFICIAL_ISO" "$HTTP_ISO" || fail "SHA512-Prüfung des Harvester-ISO fehlgeschlagen."
fi
log "SHA512-Prüfung des Harvester-ISO erfolgreich."

download_file "$RELEASE_URL/$OFFICIAL_KERNEL" "$TFTP_KERNEL"
download_file "$RELEASE_URL/$OFFICIAL_INITRD" "$TFTP_INITRD"
download_file "$RELEASE_URL/$OFFICIAL_ROOTFS" "$HTTP_ROOTFS"
verify_optional "$OFFICIAL_KERNEL" "$TFTP_KERNEL"
verify_optional "$OFFICIAL_INITRD" "$TFTP_INITRD"
verify_optional "$OFFICIAL_ROOTFS" "$HTTP_ROOTFS"
chmod 0644 "$TFTP_KERNEL" "$TFTP_INITRD" "$HTTP_ISO" "$HTTP_ROOTFS"

cat >"$TFTP_ROOT/grub/stacks/harvester.cfg" <<'GRUB_EOF'
if [ -z "${variant}" ]; then
    menuentry "Harvester - keine Hostkonfiguration" {
        echo "Harvester benötigt eine explizite MAC-Regel in rack.conf"
        echo "VARIANT: create:hostname oder join:hostname"
        sleep 5
    }
else
    menuentry "Install Harvester ${harvester_version}" {
        linux /linux/harvester/v${harvester_version}/${harvester_arch}/vmlinuz ip=dhcp net.ifnames=1 ifname=${harvester_interface}:${net_default_mac} rd.cos.disable rd.noverifyssl console=tty1 root=live:http://${pxe_server}/linux/harvester/v${harvester_version}/${harvester_arch}/rootfs.squashfs harvester.install.automatic=true harvester.install.skipchecks=${harvester_skipchecks} harvester.install.config_url=http://${pxe_server}/harvester/config/${variant}
        initrd /linux/harvester/v${harvester_version}/${harvester_arch}/initrd
    }
fi
GRUB_EOF
chmod 0644 "$TFTP_ROOT/grub/stacks/harvester.cfg"

"$TFTP_ROOT/bin/pxe-update"

log "Harvester PXE Add-on ist eingerichtet."
echo "Version     : $HARVESTER_VERSION"
echo "Architektur : $HARVESTER_ARCH"
echo "Cluster-VIP : $HARVESTER_VIP"
echo "Install-Disk: $HARVESTER_DEVICE"
echo "Interface   : $HARVESTER_INTERFACE (beim Boot an die PXE-MAC gebunden)"
echo "HW-Checks   : skipchecks=$HARVESTER_SKIPCHECKS"
echo "Konfiguration: $CONFIG"
echo
echo "HOSTS-Beispiel:"
echo '  "AA:BB:CC:DD:EE:01|harvester|create:harvester-01"'
echo '  "AA:BB:CC:DD:EE:02|harvester|join:harvester-02"'
echo
echo "Nach Änderung von HOSTS ausführen:"
echo "  sudo $TFTP_ROOT/bin/pxe-update"
echo "  sudo $TFTP_ROOT/bin/pxe-show"
