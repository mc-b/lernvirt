#!/usr/bin/env bash
set -Eeuo pipefail

# lernvirt PXE Add-on: openSUSE Leap + SUSE Rancher RKE2
#
# Voraussetzung:
#   pxe-stack/install-pxe.sh wurde bereits ausgeführt.
#
# Standard:
#   - openSUSE Leap 15.6 x86_64 per AutoYaST installieren
#   - Installation auf INSTALL_DISK aus rack.conf
#   - erster Boot installiert automatisch einen Single-Node-RKE2-Cluster
#   - RKE2 Server ist schedulable, daher reicht ein Rechner als Cluster
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
    cat <<'BOOTSTRAP_BODY'

log() { printf '[lernvirt-rke2] %s %s\n' "$(date -Iseconds)" "$*"; }

if [[ -f /var/lib/lernvirt/rke2-ready ]]; then
    log "Cluster wurde bereits provisioniert."
    exit 0
fi

hostnamectl set-hostname "$NODE_HOSTNAME"
mkdir -p /etc/rancher/rke2 /var/lib/lernvirt /etc/sysctl.d

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
zypper --non-interactive install --no-recommends curl ca-certificates apparmor-parser iptables || \
    zypper --non-interactive install curl ca-certificates apparmor-parser iptables

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

# TLS-SAN enthält Hostname und aktuelle primäre IPv4, damit eine kopierte
# kubeconfig auch ausserhalb des Nodes verwendet werden kann.
NODE_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
cat >/etc/rancher/rke2/config.yaml <<RKE2_CONFIG
write-kubeconfig-mode: "0644"
cni: canal
tls-san:
  - "$NODE_HOSTNAME"
RKE2_CONFIG
if [[ -n "$NODE_IP" ]]; then
    printf '  - "%s"\n' "$NODE_IP" >>/etc/rancher/rke2/config.yaml
fi

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

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:$PATH"

# RKE2 kann beim ersten Start mehrere Minuten Images laden.
ready=0
for _ in $(seq 1 180); do
    if [[ -x /var/lib/rancher/rke2/bin/kubectl && -s "$KUBECONFIG" ]] && \
       /var/lib/rancher/rke2/bin/kubectl --kubeconfig "$KUBECONFIG" get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {found=1} END {exit !found}'; then
        ready=1
        break
    fi
    sleep 5
done
[[ "$ready" == "1" ]] || { log "RKE2-Node wurde nicht rechtzeitig Ready."; exit 1; }

ln -sfn /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
cat >/etc/profile.d/rke2.sh <<'PROFILE_EOF'
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=/var/lib/rancher/rke2/bin:$PATH
PROFILE_EOF
chmod 0644 /etc/profile.d/rke2.sh

touch /var/lib/lernvirt/rke2-ready
log "RKE2 Single-Node-Cluster ist Ready."
/var/lib/rancher/rke2/bin/kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
/var/lib/rancher/rke2/bin/kubectl --kubeconfig "$KUBECONFIG" get pods -A
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
printf '\nStack in rack.conf:\n'
printf '  HOSTS=( "*|suse|" )\n'
printf '\nNach PXE-Installation und erstem lokalen Boot wird RKE2 automatisch installiert.\n'
printf 'Status auf dem Node:\n'
printf '  systemctl status lernvirt-rke2-bootstrap --no-pager\n'
printf '  journalctl -u lernvirt-rke2-bootstrap -f\n'
printf '  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml\n'
printf '  kubectl get nodes -o wide\n'
