#!/usr/bin/env bash
set -Eeuo pipefail

log()  { echo "[install-openshift] $*"; }
warn() { echo "[install-openshift] WARNUNG: $*" >&2; }
fail() { echo "[install-openshift] FEHLER: $*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "install-openshift.sh muss als root laufen."

RACK_CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
OCP_CONFIG="${OCP_CONFIG:-/srv/tftp/config/openshift.conf}"
[[ -r "$RACK_CONFIG" ]] || fail "PXE-Basis fehlt: $RACK_CONFIG. Zuerst install-pxe.sh ausführen."

# shellcheck disable=SC1090
source "$RACK_CONFIG"

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
OCP_FORCE="${OCP_FORCE:-0}"

[[ -x "$TFTP_ROOT/bin/pxe-update" ]] || fail "pxe-update fehlt. Zuerst install-pxe.sh ausführen."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl jq tar

mkdir -p "$TFTP_ROOT/config" "$TFTP_ROOT/grub/stacks" "$TFTP_ROOT/linux/openshift" \
    "$HTTP_ROOT/linux/openshift" "$HTTP_ROOT/openshift" /etc/lernvirt

# Bestehende Konfiguration bleibt erhalten. Bei der ersten Installation wird ein
# für das lernvirt-Lab passendes Beispiel erzeugt und muss bei Bedarf angepasst werden.
if [[ ! -e "$OCP_CONFIG" ]]; then
    cat >"$OCP_CONFIG" <<EOF_CFG
OCP_CHANNEL="${OCP_CHANNEL:-stable-4.20}"
CLUSTER_NAME="${CLUSTER_NAME:-ocp}"
BASE_DOMAIN="${BASE_DOMAIN:-lernvirt.test}"

TERRA1_IP="${TERRA1_IP:-$PXE_SERVER}"
TERRA2_IP="${TERRA2_IP:-192.168.1.102}"
TERRA3_IP="${TERRA3_IP:-192.168.1.103}"
TERRA4_IP="${TERRA4_IP:-192.168.1.104}"

TERRA2_MAC="${TERRA2_MAC:-80:EE:73:EF:0D:E9}"
TERRA3_MAC="${TERRA3_MAC:-80:EE:73:EF:03:B3}"
TERRA4_MAC="${TERRA4_MAC:-80:EE:73:EF:01:81}"

INSTALL_DISK="${INSTALL_DISK:-/dev/nvme0n1}"
CORE_PASSWORD="${CORE_PASSWORD:-insecure}"

BOOTSTRAP_NAME="${BOOTSTRAP_NAME:-ocp-bootstrap}"
BOOTSTRAP_MAC="${BOOTSTRAP_MAC:-52:54:00:00:01:05}"
BOOTSTRAP_IP="${BOOTSTRAP_IP:-192.168.1.105}"
BOOTSTRAP_PREFIX="${BOOTSTRAP_PREFIX:-24}"
BOOTSTRAP_BRIDGE="${BOOTSTRAP_BRIDGE:-br0}"
BOOTSTRAP_VCPUS="${BOOTSTRAP_VCPUS:-4}"
BOOTSTRAP_RAM_MIB="${BOOTSTRAP_RAM_MIB:-16384}"
BOOTSTRAP_DISK_GIB="${BOOTSTRAP_DISK_GIB:-100}"

OCP_DIR="${OCP_DIR:-/opt/openshift}"
PULL_SECRET_FILE="${PULL_SECRET_FILE:-/etc/lernvirt/pull-secret.json}"
SSH_KEY_FILE="${SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}"
EOF_CFG
    chmod 0600 "$OCP_CONFIG"
    log "OpenShift-Konfiguration erzeugt: $OCP_CONFIG"
fi

# shellcheck disable=SC1090
source "$OCP_CONFIG"

: "${OCP_CHANNEL:?OCP_CHANNEL fehlt}"
: "${CLUSTER_NAME:?CLUSTER_NAME fehlt}"
: "${BASE_DOMAIN:?BASE_DOMAIN fehlt}"
: "${OCP_DIR:?OCP_DIR fehlt}"

ARCH="${OCP_ARCH:-x86_64}"
CLIENT_BASE="${OCP_CLIENT_BASE:-https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_CHANNEL}}"
INSTALLER_URL="${OPENSHIFT_INSTALL_URL:-${CLIENT_BASE}/openshift-install-linux.tar.gz}"
OC_URL="${OC_URL:-${CLIENT_BASE}/openshift-client-linux.tar.gz}"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

download() {
    local url="$1" dest="$2"
    if [[ -s "$dest" && "$OCP_FORCE" != "1" ]]; then
        log "Bereits vorhanden: $dest"
        return 0
    fi
    local part="${dest}.part"
    [[ "$OCP_FORCE" == "1" ]] && rm -f "$dest" "$part"
    log "Download: $url"
    curl -fL --retry 8 --retry-delay 4 --retry-all-errors --continue-at - "$url" -o "$part"
    [[ -s "$part" ]] || fail "Leerer Download: $url"
    mv -f "$part" "$dest"
}

log "OpenShift Clients installieren: $OCP_CHANNEL"
download "$INSTALLER_URL" "$TMP/openshift-install.tar.gz"
download "$OC_URL" "$TMP/openshift-client.tar.gz"
tar -xzf "$TMP/openshift-install.tar.gz" -C "$TMP"
tar -xzf "$TMP/openshift-client.tar.gz" -C "$TMP"
[[ -x "$TMP/openshift-install" ]] || fail "openshift-install fehlt im Archiv."
[[ -x "$TMP/oc" ]] || fail "oc fehlt im Archiv."
install -m 0755 "$TMP/openshift-install" /usr/local/bin/openshift-install
install -m 0755 "$TMP/oc" /usr/local/bin/oc
[[ -x "$TMP/kubectl" ]] && install -m 0755 "$TMP/kubectl" /usr/local/bin/kubectl || true

STREAM_JSON="$HTTP_ROOT/linux/openshift/coreos-stream.json"
openshift-install coreos print-stream-json >"$STREAM_JSON"

kernel_url="$(jq -r ".architectures.\"$ARCH\".artifacts.metal.formats.pxe.kernel.location // empty" "$STREAM_JSON")"
initramfs_url="$(jq -r ".architectures.\"$ARCH\".artifacts.metal.formats.pxe.initramfs.location // empty" "$STREAM_JSON")"
rootfs_url="$(jq -r ".architectures.\"$ARCH\".artifacts.metal.formats.pxe.rootfs.location // empty" "$STREAM_JSON")"
[[ -n "$kernel_url" ]] || fail "RHCOS kernel URL nicht gefunden."
[[ -n "$initramfs_url" ]] || fail "RHCOS initramfs URL nicht gefunden."
[[ -n "$rootfs_url" ]] || fail "RHCOS rootfs URL nicht gefunden."

download "$kernel_url" "$TFTP_ROOT/linux/openshift/kernel"
download "$initramfs_url" "$TFTP_ROOT/linux/openshift/initramfs.img"
download "$rootfs_url" "$HTTP_ROOT/linux/openshift/rootfs.img"

PULL_SECRET_FILE="${PULL_SECRET_FILE:-/etc/lernvirt/pull-secret.json}"
SSH_KEY_FILE="${SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}"

if [[ -n "${PULL_SECRET:-}" ]]; then
    pull_secret="$PULL_SECRET"
else
    [[ -r "$PULL_SECRET_FILE" ]] || fail "Pull Secret fehlt: $PULL_SECRET_FILE"
    pull_secret="$(cat "$PULL_SECRET_FILE")"
fi
[[ -r "$SSH_KEY_FILE" ]] || fail "SSH Public Key fehlt: $SSH_KEY_FILE"
ssh_key="$(cat "$SSH_KEY_FILE")"

if [[ "$OCP_FORCE" == "1" || ! -s "$HTTP_ROOT/openshift/master.ign" || ! -s "$HTTP_ROOT/openshift/worker.ign" || ! -s "$HTTP_ROOT/openshift/bootstrap.ign" ]]; then
    log "OpenShift Manifeste und Ignition erzeugen"
    rm -rf "$OCP_DIR"
    mkdir -p "$OCP_DIR"
    cat >"$OCP_DIR/install-config.yaml" <<EOF_INSTALL
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 3
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
fips: false
pullSecret: '${pull_secret//\'/\'\'}'
sshKey: '${ssh_key//\'/\'\'}'
EOF_INSTALL
    cp "$OCP_DIR/install-config.yaml" "$OCP_DIR/install-config.yaml.bak"
    openshift-install create manifests --dir "$OCP_DIR"
    openshift-install create ignition-configs --dir "$OCP_DIR"
    install -m 0644 "$OCP_DIR/bootstrap.ign" "$HTTP_ROOT/openshift/bootstrap.ign"
    install -m 0644 "$OCP_DIR/master.ign" "$HTTP_ROOT/openshift/master.ign"
    install -m 0644 "$OCP_DIR/worker.ign" "$HTTP_ROOT/openshift/worker.ign"
else
    log "Ignition-Dateien bereits vorhanden. OCP_FORCE=1 würde sie neu erzeugen."
fi

cat >"$TFTP_ROOT/grub/stacks/openshift.cfg" <<'EOF_GRUB'
if [ -z "${variant}" ]; then
    set variant="master"
fi

menuentry "Install OpenShift / RHCOS - ${variant}" {
    linux /linux/openshift/kernel \
        ip=dhcp \
        rd.neednet=1 \
        coreos.live.rootfs_url=http://${pxe_server}/linux/openshift/rootfs.img \
        coreos.inst.install_dev=${install_disk} \
        coreos.inst.ignition_url=http://${pxe_server}/openshift/${variant}.ign
    initrd /linux/openshift/initramfs.img
}
EOF_GRUB
chmod 0644 "$TFTP_ROOT/grub/stacks/openshift.cfg"

"$TFTP_ROOT/bin/pxe-update"

log "OpenShift PXE Add-on vollständig eingerichtet."
echo "  RHCOS Kernel : $TFTP_ROOT/linux/openshift/kernel"
echo "  RHCOS initrd : $TFTP_ROOT/linux/openshift/initramfs.img"
echo "  RHCOS rootfs : http://$PXE_SERVER/linux/openshift/rootfs.img"
echo "  Ignition     : http://$PXE_SERVER/openshift/{master,worker,bootstrap}.ign"
echo "  Stack        : openshift"
echo
echo "HAProxy wird bewusst NICHT eingerichtet; dafür install-haproxy.sh verwenden."
