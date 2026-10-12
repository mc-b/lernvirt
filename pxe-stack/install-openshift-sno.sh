#!/usr/bin/env bash
set -Eeuo pipefail

# lernvirt PXE Add-on: OpenShift Single Node (SNO)
#
# Dieses Script laeuft EINMAL auf dem PXE-Server und installiert nur gemeinsame
# Images, Programme, Konfiguration und Scripts. Cluster-spezifische Assets werden
# spaeter auf dem jeweiligen PXE-gebooteten Zielsystem erzeugt.

log()  { printf '[install-openshift-sno] %s\n' "$*"; }
warn() { printf '[install-openshift-sno] WARNUNG: %s\n' "$*" >&2; }
fail() { printf '[install-openshift-sno] FEHLER: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[install-openshift-sno] FEHLER: Zeile %s: %s (rc=%s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Muss als root laufen."
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RACK_CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
SNO_CONFIG="${SNO_CONFIG:-/srv/tftp/config/openshift-sno.conf}"
[[ -r "$RACK_CONFIG" ]] || fail "PXE-Basis fehlt: $RACK_CONFIG. Zuerst install-pxe.sh ausfuehren."

# Environment soll rack.conf / SNO config uebersteuern koennen.
ENV_FORCE="${OCP_FORCE-}"
# shellcheck disable=SC1090
source "$RACK_CONFIG"
RACK_PXE_SERVER="${PXE_SERVER:-}"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
[[ -n "$RACK_PXE_SERVER" ]] || fail "PXE_SERVER fehlt in rack.conf."
[[ -x "$TFTP_ROOT/bin/pxe-update" ]] || fail "pxe-update fehlt: $TFTP_ROOT/bin/pxe-update"
[[ -r "$SCRIPT_DIR/target/openshift-sno-install.sh" ]] || fail "Target-Script fehlt: $SCRIPT_DIR/target/openshift-sno-install.sh"

mkdir -p "$TFTP_ROOT/config"
if [[ ! -e "$SNO_CONFIG" ]]; then
    install -m 0600 "$SCRIPT_DIR/config/openshift-sno.conf.example" "$SNO_CONFIG"
    log "Konfiguration erzeugt: $SNO_CONFIG"
fi
# shellcheck disable=SC1090
source "$SNO_CONFIG"
OCP_FORCE="${ENV_FORCE:-${OCP_FORCE:-0}}"

: "${OCP_CHANNEL:?OCP_CHANNEL fehlt}"
: "${BASE_DOMAIN:?BASE_DOMAIN fehlt}"
: "${MACHINE_NETWORK_CIDR:?MACHINE_NETWORK_CIDR fehlt}"
: "${CLUSTER_NETWORK_CIDR:?CLUSTER_NETWORK_CIDR fehlt}"
: "${CLUSTER_HOST_PREFIX:?CLUSTER_HOST_PREFIX fehlt}"
: "${SERVICE_NETWORK_CIDR:?SERVICE_NETWORK_CIDR fehlt}"
: "${INSTALL_DISK:?INSTALL_DISK fehlt}"
: "${DNS_SERVER:?DNS_SERVER fehlt}"
: "${PULL_SECRET_FILE:?PULL_SECRET_FILE fehlt}"
: "${SSH_KEY_FILE:?SSH_KEY_FILE fehlt}"

PXE_SERVER="$RACK_PXE_SERVER"

export DEBIAN_FRONTEND=noninteractive
missing=()
for cmd_pkg in "curl:curl" "jq:jq" "tar:tar" "sha256sum:coreutils"; do
    cmd="${cmd_pkg%%:*}"; pkg="${cmd_pkg##*:}"
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
    apt-get update -y
    apt-get install -y ca-certificates "${missing[@]}"
fi

[[ -r "$PULL_SECRET_FILE" ]] || fail "Pull Secret fehlt: $PULL_SECRET_FILE"
[[ -r "$SSH_KEY_FILE" ]] || fail "SSH Public Key fehlt: $SSH_KEY_FILE"
jq -e '.auths and (.auths|type=="object")' "$PULL_SECRET_FILE" >/dev/null || fail "Pull Secret ist ungueltig: $PULL_SECRET_FILE"
grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-sha2-|sk-(ssh-ed25519|ecdsa-sha2-))' "$SSH_KEY_FILE" || fail "SSH Public Key ist ungueltig: $SSH_KEY_FILE"

CACHE_DIR="${PXE_CACHE_DIR:-/var/cache/pxe-stack}/openshift-sno"
TFTP_SNO="$TFTP_ROOT/linux/openshift-sno"
HTTP_SNO="$HTTP_ROOT/openshift-sno"
HTTP_BIN="$HTTP_SNO/bin"
HTTP_CONFIG="$HTTP_SNO/config"
HTTP_SCRIPTS="$HTTP_SNO/scripts"
STACK_FILE="$TFTP_ROOT/grub/stacks/openshift-sno.cfg"
install -d -m 0755 "$CACHE_DIR" "$TFTP_SNO" "$HTTP_SNO" "$HTTP_BIN" "$HTTP_CONFIG" "$HTTP_SCRIPTS" "$TFTP_ROOT/grub/stacks"

CLIENT_BASE="${OCP_CLIENT_BASE:-https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_CHANNEL}}"
INSTALLER_URL="${OPENSHIFT_INSTALL_URL:-${CLIENT_BASE}/openshift-install-linux.tar.gz}"
OC_URL="${OC_URL:-${CLIENT_BASE}/openshift-client-linux.tar.gz}"

download_file() {
    local url="$1" dst="$2" part="${2}.part"
    if [[ -s "$dst" && "$OCP_FORCE" != "1" ]]; then return 0; fi
    [[ "$OCP_FORCE" == "1" ]] && rm -f "$dst" "$part"
    log "Download: $url"
    curl -fL --retry 8 --retry-delay 5 --retry-all-errors --continue-at - "$url" -o "$part"
    [[ -s "$part" ]] || fail "Leerer Download: $url"
    mv -f "$part" "$dst"
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

download_file "$INSTALLER_URL" "$CACHE_DIR/openshift-install-linux.tar.gz"
download_file "$OC_URL" "$CACHE_DIR/openshift-client-linux.tar.gz"
tar -xzf "$CACHE_DIR/openshift-install-linux.tar.gz" -C "$TMP"
tar -xzf "$CACHE_DIR/openshift-client-linux.tar.gz" -C "$TMP"
[[ -x "$TMP/openshift-install" ]] || fail "openshift-install fehlt im Archiv."
[[ -x "$TMP/oc" ]] || fail "oc fehlt im Archiv."

INSTALLER="$TMP/openshift-install"
OCP_VERSION="$($INSTALLER version | awk '/^openshift-install / {print $2; exit}')"
[[ -n "$OCP_VERSION" ]] || OCP_VERSION="$($INSTALLER version | head -n1 | awk '{print $NF}')"
log "OpenShift Installer: $OCP_VERSION"

# Die zum Installer passende RHCOS-Version direkt vom Installer bestimmen.
STREAM_JSON="$TMP/stream.json"
"$INSTALLER" coreos print-stream-json > "$STREAM_JSON"
KERNEL_URL="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.kernel.location // empty' "$STREAM_JSON")"
INITRAMFS_URL="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.initramfs.location // empty' "$STREAM_JSON")"
ROOTFS_URL="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.rootfs.location // empty' "$STREAM_JSON")"
[[ -n "$KERNEL_URL" && -n "$INITRAMFS_URL" && -n "$ROOTFS_URL" ]] || fail "RHCOS PXE URLs konnten aus coreos print-stream-json nicht bestimmt werden."

download_file "$KERNEL_URL" "$CACHE_DIR/rhcos-live-kernel"
download_file "$INITRAMFS_URL" "$CACHE_DIR/rhcos-live-initramfs.img"
download_file "$ROOTFS_URL" "$CACHE_DIR/rhcos-live-rootfs.img"

# Gemeinsame Assets publizieren. nginx wird NICHT veraendert.
install -m 0644 "$CACHE_DIR/rhcos-live-kernel" "$TFTP_SNO/rhcos-live-kernel"
install -m 0644 "$CACHE_DIR/rhcos-live-initramfs.img" "$TFTP_SNO/rhcos-live-initramfs.img"
install -m 0644 "$CACHE_DIR/rhcos-live-kernel" "$HTTP_SNO/rhcos-live-kernel"
install -m 0644 "$CACHE_DIR/rhcos-live-initramfs.img" "$HTTP_SNO/rhcos-live-initramfs.img"
install -m 0644 "$CACHE_DIR/rhcos-live-rootfs.img" "$HTTP_SNO/rhcos-live-rootfs.img"
install -m 0755 "$TMP/openshift-install" "$HTTP_BIN/openshift-install"
install -m 0755 "$TMP/oc" "$HTTP_BIN/oc"
install -m 0755 "$SCRIPT_DIR/target/openshift-sno-install.sh" "$HTTP_SCRIPTS/openshift-sno-install.sh"
install -m 0644 "$PULL_SECRET_FILE" "$HTTP_CONFIG/pull-secret.json"
install -m 0644 "$SSH_KEY_FILE" "$HTTP_CONFIG/ssh-key.pub"

# Nur die globalen, nicht hostspezifischen Parameter werden publiziert.
cat > "$HTTP_CONFIG/openshift-sno.conf" <<EOF_CONF
BASE_DOMAIN="${BASE_DOMAIN}"
MACHINE_NETWORK_CIDR="${MACHINE_NETWORK_CIDR}"
CLUSTER_NETWORK_CIDR="${CLUSTER_NETWORK_CIDR}"
CLUSTER_HOST_PREFIX="${CLUSTER_HOST_PREFIX}"
SERVICE_NETWORK_CIDR="${SERVICE_NETWORK_CIDR}"
INSTALL_DISK="${INSTALL_DISK}"
DNS_SERVER="${DNS_SERVER}"
OCP_VERSION="${OCP_VERSION}"
EOF_CONF
chmod 0644 "$HTTP_CONFIG/openshift-sno.conf"

# Generische Live-Ignition: SSH-Key + Launcher. Der Launcher liest PXE-Server und
# Clustername ausschliesslich aus der Kernel-Commandline und holt danach das
# aktuelle Target-Script per HTTP.
ssh_key="$(tr -d '\r\n' < "$SSH_KEY_FILE")"
LAUNCHER=$(cat <<'EOF_LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail
cmdline="$(cat /proc/cmdline)"
getarg() {
    local key="$1" token
    for token in $cmdline; do
        case "$token" in "$key"=*) printf '%s\n' "${token#*=}"; return 0;; esac
    done
    return 1
}
pxe="$(getarg lernvirt.pxe_server || true)"
variant="$(getarg lernvirt.variant || true)"
if [[ -z "$pxe" || -z "$variant" ]]; then
    echo "[openshift-sno-launch] FEHLER: lernvirt.pxe_server oder lernvirt.variant fehlt" >&2
    exit 1
fi
mkdir -p /run/lernvirt-openshift-sno
url="http://${pxe}/openshift-sno/scripts/openshift-sno-install.sh"
echo "[openshift-sno-launch] Lade ${url} fuer Cluster ${variant}"
curl -fL --retry 30 --retry-delay 5 --retry-all-errors "$url" -o /run/lernvirt-openshift-sno/install.sh
chmod 0755 /run/lernvirt-openshift-sno/install.sh
exec /run/lernvirt-openshift-sno/install.sh
EOF_LAUNCH
)
UNIT=$(cat <<'EOF_UNIT'
[Unit]
Description=lernvirt OpenShift SNO self installer
Wants=network-online.target
After=network-online.target
ConditionKernelCommandLine=lernvirt.stack=openshift-sno

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lernvirt-openshift-sno-launch
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_UNIT
)
LAUNCHER_URL="data:text/plain;charset=utf-8;base64,$(printf '%s' "$LAUNCHER" | base64 -w0)"

jq -n \
  --arg key "$ssh_key" \
  --arg launcher "$LAUNCHER_URL" \
  --arg unit "$UNIT" \
  '{
    ignition:{version:"3.4.0"},
    passwd:{users:[{name:"core",sshAuthorizedKeys:[$key]}]},
    storage:{files:[{
      path:"/usr/local/sbin/lernvirt-openshift-sno-launch",
      mode:493,
      overwrite:true,
      contents:{source:$launcher}
    }]},
    systemd:{units:[{
      name:"lernvirt-openshift-sno.service",
      enabled:true,
      contents:$unit
    }]}
  }' > "$HTTP_SNO/live.ign"
chmod 0644 "$HTTP_SNO/live.ign"
jq -e '.ignition.version == "3.4.0" and (.systemd.units|length)==1' "$HTTP_SNO/live.ign" >/dev/null || fail "live.ign konnte nicht validiert werden."

cat > "$STACK_FILE" <<'EOF_GRUB'
# OpenShift SNO: ein generischer Stack fuer beliebig viele SNO-Cluster.
# rack.conf VARIANT wird zum Cluster-Namen, z.B.:
#   "80:ee:73:ef:0d:e9|openshift-sno|hf01"

set sno_root=""
set sno_boot=""
set sno_mode=""

if search --no-floppy --file --set=sno_root /EFI/redhat/shimx64.efi; then
    set sno_boot="/EFI/redhat/shimx64.efi"
    set sno_mode="chain"
elif search --no-floppy --file --set=sno_root /EFI/redhat/grubx64.efi; then
    set sno_boot="/EFI/redhat/grubx64.efi"
    set sno_mode="chain"
elif search --no-floppy --file --set=sno_root /EFI/BOOT/BOOTX64.EFI; then
    set sno_boot="/EFI/BOOT/BOOTX64.EFI"
    set sno_mode="chain"
elif search --no-floppy --file --set=sno_root /grub2/grub.cfg; then
    set sno_boot="/grub2/grub.cfg"
    set sno_mode="config"
fi

if [ -n "${sno_root}" ]; then
    set default="openshift-sno-local"
fi

if [ -n "${sno_root}" ]; then
    menuentry "Local OpenShift SNO" --id openshift-sno-local {
        set root="${sno_root}"
        if [ "${sno_mode}" = "chain" ]; then
            insmod chain
            chainloader ${sno_boot}
            boot
        else
            configfile ${sno_boot}
        fi
    }
fi

menuentry "Install OpenShift SNO ${variant}" --id openshift-sno-install {
    if [ -z "${variant}" ]; then
        echo "ERROR: rack.conf VARIANT fehlt. Beispiel: MAC|openshift-sno|hf01"
        sleep 10
    else
        linux /linux/openshift-sno/rhcos-live-kernel \
            ip=dhcp rd.neednet=1 \
            ignition.firstboot ignition.platform.id=metal \
            ignition.config.url=http://${pxe_server}/openshift-sno/live.ign \
            coreos.live.rootfs_url=http://${pxe_server}/openshift-sno/rhcos-live-rootfs.img \
            lernvirt.stack=openshift-sno \
            lernvirt.variant=${variant} \
            lernvirt.pxe_server=${pxe_server}
        initrd /linux/openshift-sno/rhcos-live-initramfs.img
    fi
}
EOF_GRUB
chmod 0644 "$STACK_FILE"

# Bestehendes nginx nur pruefen, niemals veraendern.
if command -v nginx >/dev/null 2>&1; then
    nginx -t || fail "Bestehende nginx-Konfiguration ist ungueltig."
fi

"$TFTP_ROOT/bin/pxe-update"

log "OpenShift SNO PXE-Stack bereit."
printf '  PXE server : %s\n' "$PXE_SERVER"
printf '  Stack      : %s\n' "$STACK_FILE"
printf '  HTTP       : http://%s/openshift-sno/\n' "$PXE_SERVER"
printf '  OpenShift  : %s\n' "$OCP_VERSION"
printf '\nBeispiel rack.conf:\n'
printf '  "80:ee:73:ef:0d:e9|openshift-sno|hf01"\n'
printf '\nDas Zielsystem erzeugt die fuer die Installation benoetigten OpenShift-Namen lokal in /etc/hosts.\n'
