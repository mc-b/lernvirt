#!/usr/bin/env bash
set -Eeuo pipefail

# lernvirt PXE Add-on: openSUSE Leap + SUSE RKE2 + Helm + Rancher Manager
#
# Voraussetzung:
#   pxe-stack/install-pxe.sh wurde bereits ausgeführt.
#
# Standard:
#   - openSUSE Leap 15.6 x86_64 per AutoYaST installieren
#   - Installation auf INSTALL_DISK aus rack.conf
#   - erster Boot installiert automatisch einen Single-Node-RKE2-Cluster
#   - RKE2 Server ist schedulable, daher reicht ein Rechner als Cluster
#   - Helm 3, cert-manager und Rancher Manager werden danach automatisch installiert
#   - /boot/lernvirt-installed verhindert eine erneute PXE-Installation
#
# Wichtige Overrides:
#   SUSE_VERSION=15.6
#   SUSE_ARCH=x86_64
#   SUSE_ISO=/pfad/zur.iso
#   SUSE_ISO_URL=https://server/image.iso
#   SUSE_SHA256=<sha256>
#   SUSE_SHA256_URL=https://server/image.iso.sha256
#   SUSE_FORCE=1
#   KEEP_ISO=1
#   SUSE_HOSTNAME=suse-rke2
#   SUSE_ROOT_PASSWORD=insecure
#   SUSE_AUTOYAST=suse-rke2.xml
#   RKE2_CHANNEL=stable
#   RKE2_VERSION=v1.xx.y+rke2r1   # optional; leer = Channel verwenden
#   RKE2_METHOD=tar
#   HELM_VERSION=v3.22.0
#   CERT_MANAGER_VERSION=v1.21.2
#   RANCHER_VERSION=2.15.2
#   RANCHER_HOST=               # leer = <Node-IP>.sslip.io
#   RANCHER_BOOTSTRAP_PASSWORD= # leer = SUSE_ROOT_PASSWORD
#
# Beispiel:
#   sudo ./install-suse.sh

log()  { printf '[install-suse] %s\n' "$*"; }
warn() { printf '[install-suse] WARNUNG: %s\n' "$*" >&2; }
fail() { printf '[install-suse] FEHLER: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "install-suse.sh muss als root laufen."

CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
[[ -r "$CONFIG" ]] || fail "PXE-Basis fehlt: $CONFIG. Zuerst install-pxe.sh ausführen."

# Environment-Werte sichern, damit sie rack.conf übersteuern können.
ENV_TFTP_ROOT="${TFTP_ROOT-}"
ENV_HTTP_ROOT="${HTTP_ROOT-}"
ENV_CACHE_DIR="${PXE_CACHE_DIR-}"
ENV_SUSE_VERSION="${SUSE_VERSION-}"
ENV_SUSE_ARCH="${SUSE_ARCH-}"
ENV_SUSE_ISO="${SUSE_ISO-}"
ENV_SUSE_ISO_URL="${SUSE_ISO_URL-}"
ENV_SUSE_SHA256="${SUSE_SHA256-}"
ENV_SUSE_SHA256_URL="${SUSE_SHA256_URL-}"
ENV_SUSE_FORCE="${SUSE_FORCE-}"
ENV_KEEP_ISO="${KEEP_ISO-}"
ENV_SUSE_HOSTNAME="${SUSE_HOSTNAME-}"
ENV_SUSE_ROOT_PASSWORD="${SUSE_ROOT_PASSWORD-}"
ENV_SUSE_AUTOYAST="${SUSE_AUTOYAST-}"
ENV_RKE2_CHANNEL="${RKE2_CHANNEL-}"
ENV_RKE2_VERSION="${RKE2_VERSION-}"
ENV_RKE2_METHOD="${RKE2_METHOD-}"
ENV_HELM_VERSION="${HELM_VERSION-}"
ENV_CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION-}"
ENV_RANCHER_VERSION="${RANCHER_VERSION-}"
ENV_RANCHER_HOST="${RANCHER_HOST-}"
ENV_RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD-}"

# shellcheck disable=SC1090
source "$CONFIG"

[[ -n "$ENV_TFTP_ROOT" ]] && TFTP_ROOT="$ENV_TFTP_ROOT"
[[ -n "$ENV_HTTP_ROOT" ]] && HTTP_ROOT="$ENV_HTTP_ROOT"
[[ -n "$ENV_CACHE_DIR" ]] && PXE_CACHE_DIR="$ENV_CACHE_DIR"
[[ -n "$ENV_SUSE_VERSION" ]] && SUSE_VERSION="$ENV_SUSE_VERSION"
[[ -n "$ENV_SUSE_ARCH" ]] && SUSE_ARCH="$ENV_SUSE_ARCH"
[[ -n "$ENV_SUSE_ISO" ]] && SUSE_ISO="$ENV_SUSE_ISO"
[[ -n "$ENV_SUSE_ISO_URL" ]] && SUSE_ISO_URL="$ENV_SUSE_ISO_URL"
[[ -n "$ENV_SUSE_SHA256" ]] && SUSE_SHA256="$ENV_SUSE_SHA256"
[[ -n "$ENV_SUSE_SHA256_URL" ]] && SUSE_SHA256_URL="$ENV_SUSE_SHA256_URL"
[[ -n "$ENV_SUSE_FORCE" ]] && SUSE_FORCE="$ENV_SUSE_FORCE"
[[ -n "$ENV_KEEP_ISO" ]] && KEEP_ISO="$ENV_KEEP_ISO"
[[ -n "$ENV_SUSE_HOSTNAME" ]] && SUSE_HOSTNAME="$ENV_SUSE_HOSTNAME"
[[ -n "$ENV_SUSE_ROOT_PASSWORD" ]] && SUSE_ROOT_PASSWORD="$ENV_SUSE_ROOT_PASSWORD"
[[ -n "$ENV_SUSE_AUTOYAST" ]] && SUSE_AUTOYAST="$ENV_SUSE_AUTOYAST"
[[ -n "$ENV_RKE2_CHANNEL" ]] && RKE2_CHANNEL="$ENV_RKE2_CHANNEL"
[[ -n "$ENV_RKE2_VERSION" ]] && RKE2_VERSION="$ENV_RKE2_VERSION"
[[ -n "$ENV_RKE2_METHOD" ]] && RKE2_METHOD="$ENV_RKE2_METHOD"
[[ -n "$ENV_HELM_VERSION" ]] && HELM_VERSION="$ENV_HELM_VERSION"
[[ -n "$ENV_CERT_MANAGER_VERSION" ]] && CERT_MANAGER_VERSION="$ENV_CERT_MANAGER_VERSION"
[[ -n "$ENV_RANCHER_VERSION" ]] && RANCHER_VERSION="$ENV_RANCHER_VERSION"
[[ -n "$ENV_RANCHER_HOST" ]] && RANCHER_HOST="$ENV_RANCHER_HOST"
[[ -n "$ENV_RANCHER_BOOTSTRAP_PASSWORD" ]] && RANCHER_BOOTSTRAP_PASSWORD="$ENV_RANCHER_BOOTSTRAP_PASSWORD"

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
PXE_CACHE_DIR="${PXE_CACHE_DIR:-/var/cache/pxe-stack}"
INSTALL_DISK="${INSTALL_DISK:-/dev/nvme0n1}"
PXE_SERVER="${PXE_SERVER:-}"

SUSE_VERSION="${SUSE_VERSION:-15.6}"
SUSE_ARCH="${SUSE_ARCH:-x86_64}"
SUSE_FORCE="${SUSE_FORCE:-0}"
KEEP_ISO="${KEEP_ISO:-0}"
SUSE_ISO="${SUSE_ISO:-}"
SUSE_ISO_URL="${SUSE_ISO_URL:-}"
SUSE_SHA256="${SUSE_SHA256:-}"
SUSE_SHA256_URL="${SUSE_SHA256_URL:-}"
SUSE_HOSTNAME="${SUSE_HOSTNAME:-suse-rke2}"
SUSE_ROOT_PASSWORD="${SUSE_ROOT_PASSWORD:-insecure}"
SUSE_AUTOYAST="${SUSE_AUTOYAST:-suse-rke2.xml}"
RKE2_CHANNEL="${RKE2_CHANNEL:-stable}"
RKE2_VERSION="${RKE2_VERSION:-}"
RKE2_METHOD="${RKE2_METHOD:-tar}"
HELM_VERSION="${HELM_VERSION:-v3.22.0}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.2}"
RANCHER_VERSION="${RANCHER_VERSION:-2.15.2}"
RANCHER_HOST="${RANCHER_HOST:-}"
RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:-$SUSE_ROOT_PASSWORD}"
SSH_KEY_FILE="${SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}"

: "${PXE_SERVER:?PXE_SERVER fehlt in rack.conf}"
[[ -x "$TFTP_ROOT/bin/pxe-update" ]] || fail "pxe-update fehlt. Zuerst install-pxe.sh ausführen."
[[ -d "$TFTP_ROOT/grub/stacks" ]] || fail "GRUB-Stack-Verzeichnis fehlt: $TFTP_ROOT/grub/stacks"
[[ -r "$TFTP_ROOT/grub/grub.cfg" ]] || fail "GRUB-Basiskonfiguration fehlt: $TFTP_ROOT/grub/grub.cfg"

# Wenn das Script aus dem bereitgestellten Paket ausgeführt wird, die integrierte
# grub.cfg übernehmen. Sie enthält sowohl Harvester (COS_STATE) als auch den
# openSUSE/SUSE-UEFI-Local-Boot und überschreibt damit keine Harvester-Funktion.
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != "-" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd || true)"
fi
if [[ -n "$SCRIPT_DIR" && -r "$SCRIPT_DIR/grub/grub.cfg" ]]; then
    BUNDLED_GRUB="$SCRIPT_DIR/grub/grub.cfg"
    grep -q 'COS_STATE' "$BUNDLED_GRUB" || fail "Gebündelte grub.cfg enthält die Harvester-Erkennung nicht."
    grep -q '/EFI/opensuse/' "$BUNDLED_GRUB" || fail "Gebündelte grub.cfg enthält den openSUSE-Local-Boot nicht."
    if ! cmp -s "$BUNDLED_GRUB" "$TFTP_ROOT/grub/grub.cfg"; then
        [[ -e "$TFTP_ROOT/grub/grub.cfg.pre-suse-rke2" ]] || cp -a "$TFTP_ROOT/grub/grub.cfg" "$TFTP_ROOT/grub/grub.cfg.pre-suse-rke2"
        install -m 0644 "$BUNDLED_GRUB" "$TFTP_ROOT/grub/grub.cfg"
        log "grub.cfg aktualisiert (Harvester + openSUSE Local Boot)"
    fi
fi
[[ "$SUSE_AUTOYAST" != */* ]] || fail "SUSE_AUTOYAST darf nur ein Dateiname sein."
[[ "$SUSE_AUTOYAST" == *.xml ]] || fail "SUSE_AUTOYAST muss auf .xml enden."
[[ "$SUSE_HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$ ]] || fail "Ungültiger SUSE_HOSTNAME: $SUSE_HOSTNAME"
case "$SUSE_ARCH" in
    x86_64|aarch64) ;;
    *) fail "Nicht unterstützte SUSE_ARCH: $SUSE_ARCH (unterstützt: x86_64, aarch64)" ;;
esac
case "$RKE2_METHOD" in
    tar|rpm) ;;
    *) fail "RKE2_METHOD muss tar oder rpm sein." ;;
esac
[[ "$HELM_VERSION" =~ ^v3\.[0-9]+\.[0-9]+$ ]] || fail "HELM_VERSION muss eine Helm-3-Version wie v3.22.0 sein."
[[ "$CERT_MANAGER_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Ungültige CERT_MANAGER_VERSION: $CERT_MANAGER_VERSION"
[[ "$RANCHER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Ungültige RANCHER_VERSION: $RANCHER_VERSION"
if [[ -n "$RANCHER_HOST" ]]; then
    [[ "$RANCHER_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || fail "Ungültiger RANCHER_HOST: $RANCHER_HOST"
fi
[[ "$RANCHER_BOOTSTRAP_PASSWORD" != *$'\n'* ]] || fail "RANCHER_BOOTSTRAP_PASSWORD darf keinen Zeilenumbruch enthalten."

export DEBIAN_FRONTEND=noninteractive
missing=()
for cmd_pkg in \
    "curl:curl" \
    "rsync:rsync" \
    "sha256sum:coreutils" \
    "base64:coreutils" \
    "openssl:openssl" \
    "mount:mount"; do
    cmd="${cmd_pkg%%:*}"
    pkg="${cmd_pkg##*:}"
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
    log "Installiere benötigte Pakete: ${missing[*]}"
    apt-get update -y
    apt-get install -y ca-certificates "${missing[@]}"
fi

mkdir -p \
    "$PXE_CACHE_DIR" \
    "$TFTP_ROOT/linux/suse" \
    "$TFTP_ROOT/grub/stacks" \
    "$HTTP_ROOT/linux/suse" \
    "$HTTP_ROOT/autoyast"

TMP="$(mktemp -d)"
MNT="$TMP/iso"
mkdir -p "$MNT"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == "1" ]] && mountpoint -q "$MNT"; then
        umount "$MNT" || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

xml_escape() {
    local s=${1-}
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    s=${s//\"/&quot;}
    s=${s//\'/&apos;}
    printf '%s' "$s"
}

# Offizieller openSUSE-Leap-15.x-Standardpfad.
if [[ -n "$SUSE_ISO" ]]; then
    ISO_SOURCE="$SUSE_ISO"
elif [[ -n "$SUSE_ISO_URL" ]]; then
    ISO_SOURCE="$SUSE_ISO_URL"
else
    [[ "$SUSE_VERSION" == 15.* ]] || \
        fail "Für SUSE_VERSION=$SUSE_VERSION bitte SUSE_ISO_URL oder SUSE_ISO angeben."
    ISO_SOURCE="https://download.opensuse.org/distribution/leap/${SUSE_VERSION}/iso/openSUSE-Leap-${SUSE_VERSION}-DVD-${SUSE_ARCH}-Current.iso"
    SUSE_SHA256_URL="${SUSE_SHA256_URL:-${ISO_SOURCE}.sha256}"
fi

EXPECTED_SHA256=""
if [[ -n "$SUSE_SHA256" ]]; then
    EXPECTED_SHA256="$(printf '%s' "$SUSE_SHA256" | tr '[:upper:]' '[:lower:]')"
elif [[ -n "$SUSE_SHA256_URL" ]]; then
    log "Lade SHA256-Prüfsumme"
    curl -fL --retry 5 --retry-delay 3 "$SUSE_SHA256_URL" -o "$TMP/image.sha256" \
        || fail "SHA256-Prüfsumme konnte nicht geladen werden: $SUSE_SHA256_URL"
    EXPECTED_SHA256="$(awk '$1 ~ /^[0-9A-Fa-f]{64}$/ {print tolower($1); exit}' "$TMP/image.sha256")"
    [[ -n "$EXPECTED_SHA256" ]] || fail "Keine gültige SHA256-Prüfsumme gefunden."
fi

HTTP_CURRENT="$HTTP_ROOT/linux/suse/current"
MARKER="$HTTP_CURRENT/.lernvirt-suse-source"
TFTP_KERNEL="$TFTP_ROOT/linux/suse/linux"
TFTP_INITRD="$TFTP_ROOT/linux/suse/initrd"

SKIP_PREPARE=0
if [[ "$SUSE_FORCE" != "1" && -s "$TFTP_KERNEL" && -s "$TFTP_INITRD" && -d "$HTTP_CURRENT/boot" && -f "$MARKER" ]]; then
    marker_source="$(sed -n 's/^source=//p' "$MARKER" | head -n1)"
    marker_sha="$(sed -n 's/^sha256=//p' "$MARKER" | head -n1)"
    if [[ "$marker_source" == "$ISO_SOURCE" && ( -z "$EXPECTED_SHA256" || "$marker_sha" == "$EXPECTED_SHA256" ) ]]; then
        SKIP_PREPARE=1
        log "SUSE-Installationsquelle ist bereits vollständig aufbereitet."
    fi
fi

if [[ "$SKIP_PREPARE" != "1" ]]; then
    ISO_PATH=""
    DOWNLOADED_ISO=0
    case "$ISO_SOURCE" in
        http://*|https://*)
            DOWNLOADED_ISO=1
            ISO_CACHE="$PXE_CACHE_DIR/suse-${SUSE_VERSION}-${SUSE_ARCH}.iso"
            ISO_PART="${ISO_CACHE}.part"
            if [[ "$SUSE_FORCE" == "1" ]]; then
                rm -f "$ISO_CACHE" "$ISO_PART"
            fi
            if [[ -s "$ISO_CACHE" && -n "$EXPECTED_SHA256" ]]; then
                actual="$(sha256sum "$ISO_CACHE" | awk '{print $1}')"
                if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
                    warn "Vorhandenes ISO hat eine falsche SHA256-Prüfsumme und wird neu geladen."
                    rm -f "$ISO_CACHE"
                fi
            fi
            if [[ ! -s "$ISO_CACHE" ]]; then
                log "Lade SUSE-Installationsimage: $ISO_SOURCE"
                curl -fL --retry 8 --retry-delay 5 --retry-all-errors --continue-at - \
                    "$ISO_SOURCE" -o "$ISO_PART"
                [[ -s "$ISO_PART" ]] || fail "ISO-Download ist leer."
                if [[ -n "$EXPECTED_SHA256" ]]; then
                    actual="$(sha256sum "$ISO_PART" | awk '{print $1}')"
                    [[ "$actual" == "$EXPECTED_SHA256" ]] || {
                        rm -f "$ISO_PART"
                        fail "SHA256-Prüfung des heruntergeladenen ISO fehlgeschlagen."
                    }
                fi
                mv -f "$ISO_PART" "$ISO_CACHE"
            fi
            ISO_PATH="$ISO_CACHE"
            ;;
        *)
            [[ -s "$ISO_SOURCE" ]] || fail "SUSE ISO nicht gefunden: $ISO_SOURCE"
            ISO_PATH="$ISO_SOURCE"
            ;;
    esac

    actual="$(sha256sum "$ISO_PATH" | awk '{print $1}')"
    if [[ -n "$EXPECTED_SHA256" ]]; then
        [[ "$actual" == "$EXPECTED_SHA256" ]] || fail "SHA256-Prüfung des ISO fehlgeschlagen."
    else
        warn "Keine externe SHA256-Prüfsumme angegeben; lokale Prüfsumme: $actual"
    fi

    log "Mounte Installationsimage"
    mount -o loop,ro "$ISO_PATH" "$MNT"
    MOUNTED=1
    LOADER_DIR="$MNT/boot/$SUSE_ARCH/loader"
    if [[ ! -s "$LOADER_DIR/linux" || ! -s "$LOADER_DIR/initrd" ]]; then
        kernel_candidate="$(find "$MNT/boot" -type f -path '*/loader/linux' -print -quit 2>/dev/null || true)"
        [[ -n "$kernel_candidate" ]] || fail "Kein SUSE-PXE-Kernel (*/loader/linux) im ISO gefunden."
        LOADER_DIR="$(dirname "$kernel_candidate")"
    fi
    [[ -s "$LOADER_DIR/linux" ]] || fail "SUSE PXE-Kernel fehlt: $LOADER_DIR/linux"
    [[ -s "$LOADER_DIR/initrd" ]] || fail "SUSE PXE-initrd fehlt: $LOADER_DIR/initrd"

    log "Installiere Kernel und initrd nach TFTP"
    install -m 0644 "$LOADER_DIR/linux" "$TFTP_KERNEL.new"
    install -m 0644 "$LOADER_DIR/initrd" "$TFTP_INITRD.new"
    mv -f "$TFTP_KERNEL.new" "$TFTP_KERNEL"
    mv -f "$TFTP_INITRD.new" "$TFTP_INITRD"

    log "Kopiere vollständigen SUSE-Installationsbaum nach $HTTP_CURRENT"
    mkdir -p "$HTTP_CURRENT"
    rsync -aH --delete --exclude='.lernvirt-suse-source' "$MNT/" "$HTTP_CURRENT/"
    cat > "$MARKER" <<MARKER_EOF
source=$ISO_SOURCE
sha256=$actual
version=$SUSE_VERSION
arch=$SUSE_ARCH
MARKER_EOF

    umount "$MNT"
    MOUNTED=0
    if [[ "$DOWNLOADED_ISO" == "1" && "$KEEP_ISO" != "1" ]]; then
        log "Entferne ISO-Cache (KEEP_ISO=1 würde ihn behalten)"
        rm -f "$ISO_PATH"
    fi
fi

# SSH-Key aus der PXE-Basis übernehmen.
if [[ ! -s "$SSH_KEY_FILE" && -s "$HTTP_ROOT/ssh/lerncloud.pub" ]]; then
    SSH_KEY_FILE="$HTTP_ROOT/ssh/lerncloud.pub"
fi
[[ -s "$SSH_KEY_FILE" ]] || fail "SSH Public Key fehlt: $SSH_KEY_FILE"
SSH_PUBLIC_KEY="$(head -n1 "$SSH_KEY_FILE")"
[[ "$SSH_PUBLIC_KEY" =~ ^(ssh-(rsa|ed25519)|ecdsa-sha2-|sk-) ]] || fail "Ungültiger SSH Public Key: $SSH_KEY_FILE"

# AutoYaST enthält nur den Hash, nicht das Klartextpasswort.
ROOT_PASSWORD_HASH="$(openssl passwd -6 "$SUSE_ROOT_PASSWORD")"

# RKE2-Bootstrap-Script separat bauen, danach als Base64 in AutoYaST einbetten.
BOOTSTRAP="$TMP/lernvirt-rke2-bootstrap"
{
    cat <<'BOOTSTRAP_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
exec >>/var/log/lernvirt-rke2-bootstrap.log 2>&1
BOOTSTRAP_HEAD
    printf 'NODE_HOSTNAME=%q\n' "$SUSE_HOSTNAME"
    printf 'RKE2_CHANNEL=%q\n' "$RKE2_CHANNEL"
    printf 'RKE2_VERSION=%q\n' "$RKE2_VERSION"
    printf 'RKE2_METHOD=%q\n' "$RKE2_METHOD"
    printf 'HELM_VERSION=%q\n' "$HELM_VERSION"
    printf 'CERT_MANAGER_VERSION=%q\n' "$CERT_MANAGER_VERSION"
    printf 'RANCHER_VERSION=%q\n' "$RANCHER_VERSION"
    printf 'RANCHER_HOST=%q\n' "$RANCHER_HOST"
    printf 'RANCHER_BOOTSTRAP_PASSWORD=%q\n' "$RANCHER_BOOTSTRAP_PASSWORD"
    cat <<'BOOTSTRAP_BODY'

log() { printf '[lernvirt-rke2] %s %s\n' "$(date -Iseconds)" "$*"; }

hostnamectl set-hostname "$NODE_HOSTNAME"
mkdir -p /etc/rancher/rke2 /var/lib/lernvirt /etc/sysctl.d /opt/rke2/bin

# Wicked kann die von RKE2 gesetzten Forwarding-Werte sonst zurücksetzen.
cat >/etc/sysctl.d/90-rke2.conf <<'SYSCTL_EOF'
net.ipv4.conf.all.forwarding=1
SYSCTL_EOF
sysctl --system >/dev/null || true

# Falls NetworkManager aktiv ist, CNI-Interfaces nicht verwalten lassen.
if systemctl -q is-enabled NetworkManager.service 2>/dev/null || systemctl -q is-active NetworkManager.service 2>/dev/null; then
    mkdir -p /etc/NetworkManager/conf.d
    cat >/etc/NetworkManager/conf.d/rke2-canal.conf <<'NM_EOF'
[keyfile]
unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
NM_EOF
    systemctl reload NetworkManager.service 2>/dev/null || true
fi

# RKE2 dokumentiert firewalld als inkompatibel mit dem Default-CNI Canal.
systemctl disable --now firewalld.service 2>/dev/null || true

# Benötigte Werkzeuge sicherstellen.
zypper --non-interactive --gpg-auto-import-keys refresh || true
zypper --non-interactive install --no-recommends curl ca-certificates apparmor-parser iptables tar gzip || \
    zypper --non-interactive install curl ca-certificates apparmor-parser iptables tar gzip

for cmd in curl tar gzip sha256sum awk sed grep mountpoint; do
    command -v "$cmd" >/dev/null 2>&1 || { log "Fehlendes Werkzeug: $cmd"; exit 1; }
done

# TLS-SAN enthält Hostname und aktuelle primäre IPv4, damit eine kopierte
# kubeconfig auch ausserhalb des Nodes verwendet werden kann.
NODE_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
[[ -n "$NODE_IP" ]] || NODE_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$NODE_IP" ]] || { log "Keine primäre IPv4-Adresse gefunden."; exit 1; }

if [[ ! -f /var/lib/lernvirt/rke2-ready ]]; then
    # Erst fortfahren, wenn die offizielle RKE2-Installationsquelle erreichbar ist.
    for _ in $(seq 1 60); do
        if curl -fsS --connect-timeout 5 https://get.rke2.io/ -o /tmp/install-rke2.sh; then
            break
        fi
        log "Warte auf Netzwerk/DNS für get.rke2.io ..."
        sleep 10
    done
    [[ -s /tmp/install-rke2.sh ]] || { log "RKE2 Installer konnte nicht geladen werden."; exit 1; }
    chmod 0700 /tmp/install-rke2.sh

    cat >/etc/rancher/rke2/config.yaml <<RKE2_CONFIG
write-kubeconfig-mode: "0644"
cni: canal
tls-san:
  - "$NODE_HOSTNAME"
  - "$NODE_IP"
RKE2_CONFIG

    log "Installiere RKE2 (channel=$RKE2_CHANNEL, method=$RKE2_METHOD${RKE2_VERSION:+, version=$RKE2_VERSION})"
    export INSTALL_RKE2_TYPE=server
    export INSTALL_RKE2_METHOD="$RKE2_METHOD"
    export INSTALL_RKE2_CHANNEL="$RKE2_CHANNEL"
    if [[ -n "$RKE2_VERSION" ]]; then
        export INSTALL_RKE2_VERSION="$RKE2_VERSION"
    fi
    /tmp/install-rke2.sh

    systemctl enable rke2-server.service
    systemctl restart rke2-server.service
else
    log "RKE2 wurde bereits provisioniert."
    systemctl enable rke2-server.service >/dev/null 2>&1 || true
    systemctl start rke2-server.service
fi

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/opt/rke2/bin:/var/lib/rancher/rke2/bin:$PATH"
KUBECTL=/var/lib/rancher/rke2/bin/kubectl

# RKE2 kann beim ersten Start mehrere Minuten Images laden.
ready=0
for _ in $(seq 1 180); do
    if [[ -x "$KUBECTL" && -s "$KUBECONFIG" ]] && \
       "$KUBECTL" --kubeconfig "$KUBECONFIG" get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {found=1} END {exit !found}'; then
        ready=1
        break
    fi
    sleep 5
done
[[ "$ready" == "1" ]] || { log "RKE2-Node wurde nicht rechtzeitig Ready."; exit 1; }

touch /var/lib/lernvirt/rke2-ready
ln -sfn "$KUBECTL" /usr/local/bin/kubectl

# Helm 3 installieren. Rancher dokumentiert die Installation weiterhin mit Helm 3.
HELM=/opt/rke2/bin/helm
if [[ ! -x "$HELM" ]]; then
    case "$(uname -m)" in
        x86_64) HELM_ARCH=amd64 ;;
        aarch64|arm64) HELM_ARCH=arm64 ;;
        *) log "Nicht unterstützte Architektur für Helm: $(uname -m)"; exit 1 ;;
    esac
    HELM_TGZ="/tmp/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
    HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
    log "Installiere Helm $HELM_VERSION"
    curl -fL --retry 5 --retry-delay 3 "$HELM_URL" -o "$HELM_TGZ"
    expected="$(curl -fsSL "${HELM_URL}.sha256sum" | awk '{print $1}')"
    actual="$(sha256sum "$HELM_TGZ" | awk '{print $1}')"
    [[ -n "$expected" && "$actual" == "$expected" ]] || { log "Helm SHA256-Prüfung fehlgeschlagen."; exit 1; }
    rm -rf "/tmp/linux-${HELM_ARCH}"
    tar -xzf "$HELM_TGZ" -C /tmp
    install -m 0755 "/tmp/linux-${HELM_ARCH}/helm" "$HELM"
fi
ln -sfn "$HELM" /usr/local/bin/helm

cat >/etc/profile.d/rke2.sh <<'PROFILE_EOF'
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=/opt/rke2/bin:/var/lib/rancher/rke2/bin:$PATH
PROFILE_EOF
chmod 0644 /etc/profile.d/rke2.sh

touch /var/lib/lernvirt/helm-ready
log "Helm ist bereit: $($HELM version --short)"

# Rancher Manager benötigt bei selbstsigniertem TLS cert-manager.
if [[ ! -f /var/lib/lernvirt/rancher-ready ]]; then
    [[ -n "$RANCHER_HOST" ]] || RANCHER_HOST="${NODE_IP}.sslip.io"
    log "Installiere cert-manager $CERT_MANAGER_VERSION"
    "$HELM" repo add jetstack https://charts.jetstack.io --force-update
    "$HELM" repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update
    "$HELM" repo update

    "$HELM" upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version "$CERT_MANAGER_VERSION" \
        --set crds.enabled=true \
        --wait \
        --timeout 15m

    "$KUBECTL" --kubeconfig "$KUBECONFIG" create namespace cattle-system \
        --dry-run=client -o yaml | "$KUBECTL" --kubeconfig "$KUBECONFIG" apply -f -

    RANCHER_HOST_YAML="$(printf '%s' "$RANCHER_HOST" | sed "s/'/''/g")"
    RANCHER_PASSWORD_YAML="$(printf '%s' "$RANCHER_BOOTSTRAP_PASSWORD" | sed "s/'/''/g")"
    cat >/tmp/rancher-values.yaml <<RANCHER_VALUES
hostname: '$RANCHER_HOST_YAML'
replicas: 1
bootstrapPassword: '$RANCHER_PASSWORD_YAML'
RANCHER_VALUES

    log "Installiere Rancher Manager $RANCHER_VERSION unter https://$RANCHER_HOST"
    "$HELM" upgrade --install rancher rancher-latest/rancher \
        --namespace cattle-system \
        --version "$RANCHER_VERSION" \
        -f /tmp/rancher-values.yaml \
        --wait \
        --timeout 20m

    "$KUBECTL" --kubeconfig "$KUBECONFIG" -n cattle-system rollout status deployment/rancher --timeout=1200s
    touch /var/lib/lernvirt/rancher-ready
else
    [[ -n "$RANCHER_HOST" ]] || RANCHER_HOST="$($HELM get values rancher -n cattle-system -o json 2>/dev/null | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p')"
    [[ -n "$RANCHER_HOST" ]] || RANCHER_HOST="${NODE_IP}.sslip.io"
    log "Rancher wurde bereits provisioniert."
fi

cat >/root/rancher-access.txt <<RANCHER_ACCESS
Rancher URL: https://$RANCHER_HOST
Benutzer: admin
Bootstrap-Passwort: $RANCHER_BOOTSTRAP_PASSWORD
RANCHER_ACCESS
chmod 0600 /root/rancher-access.txt

log "SUSE RKE2 + Helm + Rancher ist Ready."
"$KUBECTL" --kubeconfig "$KUBECONFIG" get nodes -o wide
"$KUBECTL" --kubeconfig "$KUBECONFIG" get pods -A
printf '\nRancher: https://%s\n' "$RANCHER_HOST"
printf 'Zugangsdaten: /root/rancher-access.txt\n'
BOOTSTRAP_BODY
} > "$BOOTSTRAP"
chmod 0755 "$BOOTSTRAP"

UNIT="$TMP/lernvirt-rke2-bootstrap.service"
cat > "$UNIT" <<'UNIT_EOF'
[Unit]
Description=lernvirt RKE2 Single-Node Bootstrap
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lernvirt-rke2-bootstrap
RemainAfterExit=yes
Restart=on-failure
RestartSec=30s

[Install]
WantedBy=multi-user.target
UNIT_EOF

BOOTSTRAP_B64="$(base64 -w0 "$BOOTSTRAP")"
UNIT_B64="$(base64 -w0 "$UNIT")"

AY_FILE="$HTTP_ROOT/autoyast/$SUSE_AUTOYAST"
DEVICE_XML="$(xml_escape "$INSTALL_DISK")"
HOST_XML="$(xml_escape "$SUSE_HOSTNAME")"
KEY_XML="$(xml_escape "$SSH_PUBLIC_KEY")"
PASS_XML="$(xml_escape "$ROOT_PASSWORD_HASH")"

cat > "$AY_FILE" <<EOF_AUTOYAST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE profile>
<profile xmlns="http://www.suse.com/1.0/yast2ns" xmlns:config="http://www.suse.com/1.0/configns">
  <general>
    <mode>
      <confirm config:type="boolean">false</confirm>
      <second_stage config:type="boolean">false</second_stage>
      <forceboot config:type="boolean">true</forceboot>
      <final_reboot config:type="boolean">true</final_reboot>
    </mode>
  </general>

  <networking>
    <keep_install_network config:type="boolean">true</keep_install_network>
  </networking>

  <timezone>
    <hwclock>UTC</hwclock>
    <timezone>Europe/Zurich</timezone>
  </timezone>

  <users config:type="list">
    <user>
      <username>root</username>
      <encrypted config:type="boolean">true</encrypted>
      <user_password>${PASS_XML}</user_password>
      <authorized_keys config:type="list">
        <listentry>${KEY_XML}</listentry>
      </authorized_keys>
    </user>
  </users>

  <partitioning config:type="list">
    <drive>
      <device>${DEVICE_XML}</device>
      <initialize config:type="boolean">true</initialize>
      <partitions config:type="list">
        <partition>
          <mount>/</mount>
          <size>max</size>
          <filesystem config:type="symbol">btrfs</filesystem>
        </partition>
      </partitions>
    </drive>
  </partitioning>

  <software>
    <products config:type="list">
      <product>Leap</product>
    </products>
    <patterns config:type="list">
      <pattern>enhanced_base</pattern>
    </patterns>
  </software>

  <services-manager>
    <services>
      <enable config:type="list">
        <service>sshd</service>
      </enable>
    </services>
  </services-manager>

  <firewall>
    <enable_firewall config:type="boolean">false</enable_firewall>
    <start_firewall config:type="boolean">false</start_firewall>
  </firewall>

  <scripts>
    <chroot-scripts config:type="list">
      <script>
        <chrooted config:type="boolean">true</chrooted>
        <filename>lernvirt-rke2-prepare.sh</filename>
        <interpreter>/bin/bash -e</interpreter>
        <source><![CDATA[
mkdir -p /usr/local/sbin /etc/systemd/system /boot /var/lib/lernvirt
printf '%s' '${BOOTSTRAP_B64}' | base64 -d >/usr/local/sbin/lernvirt-rke2-bootstrap
chmod 0755 /usr/local/sbin/lernvirt-rke2-bootstrap
printf '%s' '${UNIT_B64}' | base64 -d >/etc/systemd/system/lernvirt-rke2-bootstrap.service
chmod 0644 /etc/systemd/system/lernvirt-rke2-bootstrap.service
systemctl enable sshd.service
systemctl enable lernvirt-rke2-bootstrap.service
touch /boot/lernvirt-installed
# Der Marker auf der EFI-Systempartition ist fuer den PXE-GRUB besonders robust,
# weil er unabhaengig von Btrfs-Subvolumes gefunden werden kann.
if grep -qs ' /boot/efi ' /proc/mounts; then
    touch /boot/efi/lernvirt-installed
fi
printf '%s\n' '${HOST_XML}' >/etc/hostname
]]></source>
      </script>
    </chroot-scripts>
  </scripts>
</profile>
EOF_AUTOYAST
chmod 0644 "$AY_FILE"

# suse ohne VARIANT ist jetzt bewusst vollständig unattended und baut RKE2.
# Eine explizite VARIANT bleibt als benutzerdefiniertes AutoYaST-Profil kompatibel.
cat > "$TFTP_ROOT/grub/stacks/suse.cfg" <<'GRUB_EOF'
if [ -z "${variant}" ]; then
    menuentry "Install openSUSE + RKE2 (Single Node)" {
        linux /linux/suse/linux \
            netsetup=dhcp \
            install=http://${pxe_server}/linux/suse/current/ \
            autoyast=http://${pxe_server}/autoyast/suse-rke2.xml
        initrd /linux/suse/initrd
    }
else
    menuentry "Install SUSE - AutoYaST ${variant}" {
        linux /linux/suse/linux \
            netsetup=dhcp \
            install=http://${pxe_server}/linux/suse/current/ \
            autoyast=http://${pxe_server}/autoyast/${variant}
        initrd /linux/suse/initrd
    }
fi
GRUB_EOF
chmod 0644 "$TFTP_ROOT/grub/stacks/suse.cfg"

# Bei abweichendem Profilnamen die Default-Stack-Datei passend setzen.
if [[ "$SUSE_AUTOYAST" != "suse-rke2.xml" ]]; then
    sed -i "s#autoyast=http://\${pxe_server}/autoyast/suse-rke2.xml#autoyast=http://\${pxe_server}/autoyast/${SUSE_AUTOYAST}#" \
        "$TFTP_ROOT/grub/stacks/suse.cfg"
fi

if command -v nginx >/dev/null 2>&1; then
    nginx -t || fail "Bestehende nginx-Konfiguration ist ungültig."
fi

"$TFTP_ROOT/bin/pxe-update"

log "SUSE/RKE2 PXE Add-on bereit."
printf '  TFTP Kernel : %s\n' "$TFTP_KERNEL"
printf '  TFTP initrd : %s\n' "$TFTP_INITRD"
printf '  HTTP Source : http://%s/linux/suse/current/\n' "$PXE_SERVER"
printf '  AutoYaST    : http://%s/autoyast/%s\n' "$PXE_SERVER" "$SUSE_AUTOYAST"
printf '  Zielplatte  : %s\n' "$INSTALL_DISK"
printf '  Hostname    : %s\n' "$SUSE_HOSTNAME"
printf '  RKE2        : channel=%s method=%s%s\n' "$RKE2_CHANNEL" "$RKE2_METHOD" "${RKE2_VERSION:+ version=$RKE2_VERSION}"
printf '  Helm        : %s\n' "$HELM_VERSION"
printf '  cert-manager: %s\n' "$CERT_MANAGER_VERSION"
printf '  Rancher     : %s%s\n' "$RANCHER_VERSION" "${RANCHER_HOST:+ host=$RANCHER_HOST}"
printf '\nStack in rack.conf:\n'
printf '  HOSTS=( "*|suse|" )\n'
printf '\nNach PXE-Installation und erstem lokalen Boot werden RKE2, Helm, cert-manager und Rancher automatisch installiert.\n'
printf 'Status auf dem Node:\n'
printf '  systemctl status lernvirt-rke2-bootstrap --no-pager\n'
printf '  journalctl -u lernvirt-rke2-bootstrap -f\n'
printf '  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml\n'
printf '  kubectl get nodes -o wide\n'
printf '  helm list -A\n'
printf '  cat /root/rancher-access.txt\n'
