#!/usr/bin/env bash
set -Eeuo pipefail

# lernvirt PXE Add-on: SUSE Harvester / SUSE Virtualization
#
# Voraussetzung:
#   pxe-stack/install-pxe.sh wurde bereits ausgeführt.
#
# Standard:
#   Harvester 1.8.2 AMD64 wird von releases.rancher.com geladen.
#   Kernel/Initrd werden per TFTP, RootFS/ISO und Harvester-Konfiguration
#   per HTTP bereitgestellt.
#
# Wichtige Overrides:
#   HARVESTER_VERSION=1.8.2
#   HARVESTER_ARCH=amd64          # amd64 oder arm64
#   HARVESTER_FORCE=1             # Assets erneut laden
#   HARVESTER_BASE_URL=https://releases.rancher.com/harvester
#
# Beispiel:
#   curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-harvester.sh | bash -

log()  { printf '[install-harvester] %s\n' "$*"; }
warn() { printf '[install-harvester] WARNUNG: %s\n' "$*" >&2; }
fail() { printf '[install-harvester] FEHLER: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "install-harvester.sh muss als root laufen."

CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
[[ -r "$CONFIG" ]] || fail "PXE-Basis fehlt: $CONFIG. Zuerst install-pxe.sh ausführen."

# Environment-Werte sollen rack.conf übersteuern können.
ENV_TFTP_ROOT="${TFTP_ROOT-}"
ENV_HTTP_ROOT="${HTTP_ROOT-}"
ENV_CACHE_DIR="${PXE_CACHE_DIR-}"
ENV_PXE_SERVER="${PXE_SERVER-}"

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

HARVESTER_VERSION="${HARVESTER_VERSION:-1.8.2}"
HARVESTER_ARCH="${HARVESTER_ARCH:-amd64}"
HARVESTER_FORCE="${HARVESTER_FORCE:-0}"
HARVESTER_BASE_URL="${HARVESTER_BASE_URL:-https://releases.rancher.com/harvester}"

[[ -n "$PXE_SERVER" ]] || fail "PXE_SERVER fehlt in $CONFIG."
[[ -x "$TFTP_ROOT/bin/pxe-update" ]] || fail "pxe-update fehlt. Zuerst install-pxe.sh ausführen."
[[ -d "$TFTP_ROOT/grub/stacks" ]] || fail "GRUB-Stack-Verzeichnis fehlt: $TFTP_ROOT/grub/stacks"
[[ -r "$TFTP_ROOT/grub/grub.cfg" ]] || fail "GRUB-Basiskonfiguration fehlt: $TFTP_ROOT/grub/grub.cfg"

case "$HARVESTER_ARCH" in
    amd64|arm64) ;;
    *) fail "Nicht unterstützte HARVESTER_ARCH: $HARVESTER_ARCH (unterstützt: amd64, arm64)" ;;
esac

for cmd in curl sha512sum awk grep install nginx; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Befehl fehlt: $cmd"
done

VERSION_TAG="v${HARVESTER_VERSION}"
RELEASE_URL="${HARVESTER_BASE_URL%/}/${VERSION_TAG}"

OFFICIAL_ISO="harvester-${VERSION_TAG}-${HARVESTER_ARCH}.iso"
OFFICIAL_KERNEL="harvester-${VERSION_TAG}-vmlinuz-${HARVESTER_ARCH}"
OFFICIAL_INITRD="harvester-${VERSION_TAG}-initrd-${HARVESTER_ARCH}"
OFFICIAL_ROOTFS="harvester-${VERSION_TAG}-rootfs-${HARVESTER_ARCH}.squashfs"
OFFICIAL_SHA512="harvester-${VERSION_TAG}-${HARVESTER_ARCH}.sha512"

TFTP_VERSION_DIR="$TFTP_ROOT/linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}"
HTTP_VERSION_DIR="$HTTP_ROOT/linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}"
HTTP_CONFIG_DIR="$HTTP_ROOT/harvester/config"
CACHE_DIR="$PXE_CACHE_DIR/harvester/${VERSION_TAG}/${HARVESTER_ARCH}"

TFTP_KERNEL="$TFTP_VERSION_DIR/vmlinuz"
TFTP_INITRD="$TFTP_VERSION_DIR/initrd"
HTTP_ISO="$HTTP_VERSION_DIR/harvester.iso"
HTTP_ROOTFS="$HTTP_VERSION_DIR/rootfs.squashfs"
CHECKSUM_FILE="$CACHE_DIR/$OFFICIAL_SHA512"

mkdir -p \
    "$TFTP_VERSION_DIR" \
    "$HTTP_VERSION_DIR" \
    "$HTTP_CONFIG_DIR" \
    "$CACHE_DIR" \
    "$TFTP_ROOT/grub/stacks"

# Verhindert lediglich Directory Listing; die Konfigurationsdateien müssen für
# die PXE-Clients weiterhin direkt per HTTP lesbar sein.
: > "$HTTP_CONFIG_DIR/index.html"
chmod 0644 "$HTTP_CONFIG_DIR/index.html"

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
    curl -fL \
        --retry 8 \
        --retry-delay 5 \
        --retry-all-errors \
        --continue-at - \
        "$url" \
        -o "$part"

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
            if (n == f) {
                print tolower($1)
                exit
            }
        }
    ' "$CHECKSUM_FILE")"

    if [[ -n "$expected" ]]; then
        printf '%s\n' "$expected"
        return 0
    fi

    # Einige Harvester-Releases liefern für das ISO eine Datei mit genau
    # einer Prüfsumme ohne Dateinamen.
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

    expected="$(checksum_for "$official_name")" \
        || fail "Keine SHA512-Prüfsumme für $official_name in $CHECKSUM_FILE gefunden."
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
    [[ "$actual" == "$expected" ]] \
        || fail "SHA512-Prüfung fehlgeschlagen: $official_name"
}

log "Lade offizielle SHA512-Prüfsumme"
download_file "$RELEASE_URL/$OFFICIAL_SHA512" "$CHECKSUM_FILE"

# ISO ist für die eigentliche Installation zwingend und wird mit der offiziellen
# Harvester-Prüfsumme validiert.
download_file "$RELEASE_URL/$OFFICIAL_ISO" "$HTTP_ISO"
if ! verify_required "$OFFICIAL_ISO" "$HTTP_ISO"; then
    warn "Vorhandenes ISO hat eine falsche SHA512-Prüfsumme; lade es einmal neu."
    rm -f "$HTTP_ISO" "${HTTP_ISO}.part"
    download_file "$RELEASE_URL/$OFFICIAL_ISO" "$HTTP_ISO"
    verify_required "$OFFICIAL_ISO" "$HTTP_ISO" \
        || fail "SHA512-Prüfung des Harvester-ISO fehlgeschlagen."
fi
log "SHA512-Prüfung des Harvester-ISO erfolgreich."

# Harvester stellt Kernel, initrd und rootfs separat für PXE bereit.
download_file "$RELEASE_URL/$OFFICIAL_KERNEL" "$TFTP_KERNEL"
download_file "$RELEASE_URL/$OFFICIAL_INITRD" "$TFTP_INITRD"
download_file "$RELEASE_URL/$OFFICIAL_ROOTFS" "$HTTP_ROOTFS"

# Falls die Release-Prüfsummendatei auch Einträge für diese Assets enthält,
# werden sie ebenfalls validiert.
verify_optional "$OFFICIAL_KERNEL" "$TFTP_KERNEL"
verify_optional "$OFFICIAL_INITRD" "$TFTP_INITRD"
verify_optional "$OFFICIAL_ROOTFS" "$HTTP_ROOTFS"

chmod 0644 "$TFTP_KERNEL" "$TFTP_INITRD" "$HTTP_ISO" "$HTTP_ROOTFS"

SSH_KEY="CHANGE-ME"
if [[ -s "$HTTP_ROOT/ssh/lerncloud.pub" ]]; then
    SSH_KEY="$(head -n1 "$HTTP_ROOT/ssh/lerncloud.pub")"
    SSH_KEY="${SSH_KEY//\"/\\\"}"
fi

# Beispiele werden bei jedem Aufruf aktualisiert. Echte *.yaml-Dateien werden
# bewusst nie überschrieben, weil sie Token und Passwörter enthalten können.
cat > "$HTTP_CONFIG_DIR/config-create.yaml.example" <<EOF_CREATE
# Harvester CREATE – pro Node kopieren und anpassen.
# ACHTUNG: Diese Datei enthält nach dem Ausfüllen Zugangsdaten.
scheme_version: 1
token: "CHANGE-ME"
os:
  hostname: "harvester-01"
  ssh_authorized_keys:
    - "$SSH_KEY"
  password: "CHANGE-ME"
  ntp_servers:
    - 0.suse.pool.ntp.org
    - 1.suse.pool.ntp.org
install:
  mode: create
  management_interface:
    interfaces:
      - name: "CHANGE-ME"
    default_route: true
    method: dhcp
    bond_options:
      mode: active-backup
      miimon: 100
  device: "$INSTALL_DISK"
  iso_url: "http://${PXE_SERVER}/linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}/harvester.iso"
  vip: "CHANGE-ME"
  vip_mode: static
EOF_CREATE

cat > "$HTTP_CONFIG_DIR/config-join.yaml.example" <<EOF_JOIN
# Harvester JOIN – pro Node kopieren und anpassen.
# ACHTUNG: Diese Datei enthält nach dem Ausfüllen Zugangsdaten.
scheme_version: 1
server_url: "https://CHANGE-ME:443"
token: "CHANGE-ME"
os:
  hostname: "harvester-02"
  ssh_authorized_keys:
    - "$SSH_KEY"
  password: "CHANGE-ME"
  ntp_servers:
    - 0.suse.pool.ntp.org
    - 1.suse.pool.ntp.org
install:
  mode: join
  management_interface:
    interfaces:
      - name: "CHANGE-ME"
    default_route: true
    method: dhcp
    bond_options:
      mode: active-backup
      miimon: 100
  device: "$INSTALL_DISK"
  iso_url: "http://${PXE_SERVER}/linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}/harvester.iso"
EOF_JOIN

chmod 0644 \
    "$HTTP_CONFIG_DIR/config-create.yaml.example" \
    "$HTTP_CONFIG_DIR/config-join.yaml.example"

# Harvester nutzt bei PXE keine interaktive Installation. Darum wird nur bei
# gesetzter VARIANT automatisch installiert; VARIANT ist der Dateiname unter
# /var/www/html/harvester/config/.
cat > "$TFTP_ROOT/grub/stacks/harvester.cfg" <<GRUB_EOF
if [ -z "\${variant}" ]; then
    menuentry "Harvester - Konfiguration fehlt" {
        echo "Harvester PXE benötigt eine YAML-Konfiguration."
        echo "rack.conf: MAC|harvester|<datei.yaml>"
        sleep 8
    }
else
    menuentry "Install Harvester ${HARVESTER_VERSION} (${HARVESTER_ARCH}) - \${variant}" {
        linux /linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}/vmlinuz \\
            ip=dhcp \\
            net.ifnames=1 \\
            rd.cos.disable \\
            rd.noverifyssl \\
            console=tty1 \\
            root=live:http://\${pxe_server}/linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}/rootfs.squashfs \\
            harvester.install.automatic=true \\
            harvester.install.config_url=http://\${pxe_server}/harvester/config/\${variant}
        initrd /linux/harvester/${VERSION_TAG}/${HARVESTER_ARCH}/initrd
    }
fi
GRUB_EOF
chmod 0644 "$TFTP_ROOT/grub/stacks/harvester.cfg"

# Ein installiertes Harvester besitzt eine COS_STATE-Partition. Die PXE-Basis
# erkennt normalerweise lokale Installationen über /lernvirt-installed; für
# Harvester wird zusätzlich COS_STATE erkannt. Der vorhandene Local-Boot-Eintrag
# kann danach /grub2/grub.cfg von COS_STATE laden.
ensure_harvester_local_boot() {
    local grub_cfg="$TFTP_ROOT/grub/grub.cfg"
    local tmp

    if grep -q 'search --no-floppy --label --set=localroot COS_STATE' "$grub_cfg"; then
        return 0
    fi

    log "Erweitere PXE-GRUB um Harvester/COS_STATE-Erkennung"
    [[ -e "${grub_cfg}.pre-harvester" ]] || cp -a "$grub_cfg" "${grub_cfg}.pre-harvester"
    tmp="$(mktemp)"

    awk '
        /# Der Reset-Stack muss unabhängig vom lokalen Marker neu installieren\./ && !inserted {
            print "# Harvester / Elemental legt den lokalen Bootloader auf COS_STATE ab."
            print "# Damit wird nach erfolgreicher Harvester-Installation lokal gebootet."
            print "if [ \"${lernvirt_installed}\" = \"0\" ]; then"
            print "    if search --no-floppy --label --set=localroot COS_STATE; then"
            print "        set lernvirt_installed=\"1\""
            print "        set default=\"0\""
            print "    fi"
            print "fi"
            inserted=1
        }
        { print }
        END {
            if (!inserted) exit 42
        }
    ' "$grub_cfg" > "$tmp" || {
        rm -f "$tmp"
        fail "Konnte Harvester-Erkennung nicht in $grub_cfg einfügen. Bitte grub/grub.cfg aus dem aktualisierten pxe-stack installieren."
    }

    install -m 0644 "$tmp" "$grub_cfg"
    rm -f "$tmp"
}

ensure_harvester_local_boot

# nginx-Konfiguration gehört zur PXE-Basis und wird nicht verändert.
nginx -t || fail "Bestehende nginx-Konfiguration ist ungültig."

"$TFTP_ROOT/bin/pxe-update"

log "Harvester PXE Add-on bereit."
printf '  Version      : %s\n' "$HARVESTER_VERSION"
printf '  Architektur : %s\n' "$HARVESTER_ARCH"
printf '  TFTP Kernel : %s\n' "$TFTP_KERNEL"
printf '  TFTP initrd : %s\n' "$TFTP_INITRD"
printf '  HTTP RootFS : http://%s/linux/harvester/%s/%s/rootfs.squashfs\n' "$PXE_SERVER" "$VERSION_TAG" "$HARVESTER_ARCH"
printf '  HTTP ISO    : http://%s/linux/harvester/%s/%s/harvester.iso\n' "$PXE_SERVER" "$VERSION_TAG" "$HARVESTER_ARCH"
printf '  Configs     : %s\n' "$HTTP_CONFIG_DIR"
printf '\nNächste Schritte:\n'
printf '  1. config-create.yaml.example bzw. config-join.yaml.example kopieren und anpassen.\n'
printf '  2. rack.conf pro Node z.B. mit MAC|harvester|node1.yaml konfigurieren.\n'
printf '  3. %s/bin/pxe-update ausführen.\n' "$TFTP_ROOT"
printf '\nHinweis: Harvester %s PXE-Neuinstallationen benötigen UEFI.\n' "$HARVESTER_VERSION"
