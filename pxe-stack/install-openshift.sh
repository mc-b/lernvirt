#!/usr/bin/env bash
set -Eeuo pipefail

log()  { printf '\n=== %s ===\n' "$*"; }
warn() { echo "WARNUNG: $*" >&2; }
fail() { echo "FEHLER: $*" >&2; exit 1; }

MODE="${1:-install}"
case "$MODE" in
    install) ;;
    resume|--resume) MODE="resume" ;;
    -h|--help|help)
        cat <<'EOF_HELP'
Verwendung:
  sudo ./install-openshift.sh          Neue Installation
  sudo ./install-openshift.sh resume   Unterbrochene Installation fortsetzen

Ein Neuaufbau trotz vorhandener Cluster-Artefakte ist nur explizit mit
OCP_FORCE=1 vorgesehen. "resume" erzeugt keine neue Ignition/PKI.
EOF_HELP
        exit 0
        ;;
    *) fail "Unbekannter Modus: $MODE (erlaubt: install, resume)" ;;
esac

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "install-openshift.sh muss als root laufen."

RACK_CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
OCP_CONFIG="${OCP_CONFIG:-/srv/tftp/config/openshift.conf}"
[[ -r "$RACK_CONFIG" ]] || fail "PXE-Basis fehlt: $RACK_CONFIG. Zuerst install-pxe.sh ausführen."
# shellcheck disable=SC1090
source "$RACK_CONFIG"

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
OCP_FORCE="${OCP_FORCE:-0}"
HAPROXY_INSTALLER_URL="${HAPROXY_INSTALLER_URL:-https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-haproxy.sh}"
STATUS_SCRIPT_URL="${STATUS_SCRIPT_URL:-https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/bin/openshift-status}"
LOG="${OPENSHIFT_LOG:-/var/log/openshift-install.log}"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "FEHLER in Zeile $LINENO: $BASH_COMMAND" >&2' ERR

mkdir -p "$TFTP_ROOT/config" /etc/lernvirt
if [[ ! -e "$OCP_CONFIG" ]]; then
    cat >"$OCP_CONFIG" <<EOF_CFG
# lernvirt OpenShift compact cluster
OCP_CHANNEL="${OCP_CHANNEL:-stable-4.20}"
CLUSTER_NAME="${CLUSTER_NAME:-ocp}"
BASE_DOMAIN="${BASE_DOMAIN:-lernvirt.test}"
MACHINE_NETWORK_CIDR="${MACHINE_NETWORK_CIDR:-192.168.1.0/24}"

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

# Nach bootstrap-complete übernimmt der Ingress-HAProxy standardmässig die
# frei gewordene Bootstrap-IP in einem eigenen Network Namespace. Dadurch
# kann nginx auf terra1 unverändert auf Port 80 weiterlaufen.
INGRESS_IP="${INGRESS_IP:-${BOOTSTRAP_IP:-192.168.1.105}}"
INGRESS_PREFIX="${INGRESS_PREFIX:-${BOOTSTRAP_PREFIX:-24}}"
INGRESS_BRIDGE="${INGRESS_BRIDGE:-${BOOTSTRAP_BRIDGE:-br0}}"
INGRESS_MAC="${INGRESS_MAC:-${BOOTSTRAP_MAC:-52:54:00:00:01:05}}"

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
: "${MACHINE_NETWORK_CIDR:?MACHINE_NETWORK_CIDR fehlt}"
: "${TERRA1_IP:?TERRA1_IP fehlt}"
: "${TERRA2_IP:?TERRA2_IP fehlt}"
: "${TERRA3_IP:?TERRA3_IP fehlt}"
: "${TERRA4_IP:?TERRA4_IP fehlt}"
: "${TERRA2_MAC:?TERRA2_MAC fehlt}"
: "${TERRA3_MAC:?TERRA3_MAC fehlt}"
: "${TERRA4_MAC:?TERRA4_MAC fehlt}"
: "${INSTALL_DISK:?INSTALL_DISK fehlt}"
: "${BOOTSTRAP_NAME:?BOOTSTRAP_NAME fehlt}"
: "${BOOTSTRAP_MAC:?BOOTSTRAP_MAC fehlt}"
: "${BOOTSTRAP_IP:?BOOTSTRAP_IP fehlt}"
: "${BOOTSTRAP_PREFIX:?BOOTSTRAP_PREFIX fehlt}"
: "${BOOTSTRAP_BRIDGE:?BOOTSTRAP_BRIDGE fehlt}"
: "${OCP_DIR:?OCP_DIR fehlt}"

INGRESS_IP="${INGRESS_IP:-$BOOTSTRAP_IP}"
INGRESS_PREFIX="${INGRESS_PREFIX:-$BOOTSTRAP_PREFIX}"
INGRESS_BRIDGE="${INGRESS_BRIDGE:-$BOOTSTRAP_BRIDGE}"
PULL_SECRET_FILE="${PULL_SECRET_FILE:-/etc/lernvirt/pull-secret.json}"
SSH_KEY_FILE="${SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}"

BIN="${OCP_DIR}/bin"
INSTALL_DIR="${OCP_DIR}/install"
DEBUG_DIR="${OCP_DIR}/debug"
NODE_DIR="${OCP_DIR}/nodes"
HTTP_OCP="${HTTP_ROOT}/openshift"
TFTP_OCP="${TFTP_ROOT}/linux/openshift"
BOOTSTRAP_DISK="/var/lib/libvirt/images/${BOOTSTRAP_NAME}.qcow2"
BOOTSTRAP_IGN="${INSTALL_DIR}/bootstrap.ign"
OCP_VERSION=""
RHCOS_QEMU_IMAGE=""
MCS_URL=""
LAN_IF=""
BOOTSTRAP_GATEWAY=""
HAPROXY_INSTALLER=""

cluster_artifacts_exist() {
    [[ -s "${INSTALL_DIR}/master.ign" || -s "${INSTALL_DIR}/metadata.json" || -s "${INSTALL_DIR}/auth/kubeconfig" ]]
}

if [[ "$MODE" == "install" ]]; then
    if [[ -e "${OCP_DIR}/installed" && "$OCP_FORCE" != "1" ]]; then
        fail "OpenShift ist bereits als installiert markiert: ${OCP_DIR}/installed. Für einen Neuaufbau OCP_FORCE=1 setzen."
    fi
    if cluster_artifacts_exist && [[ "$OCP_FORCE" != "1" ]]; then
        fail "Vorhandene OpenShift-Installationsartefakte erkannt. Nicht neu erzeugen: mit '$0 resume' fortsetzen. Für einen bewussten Neuaufbau OCP_FORCE=1 setzen."
    fi
    if [[ "$OCP_FORCE" == "1" ]]; then
        rm -f "${OCP_DIR}/installed"
    fi
else
    [[ -x "${BIN}/openshift-install" ]] || fail "Resume nicht möglich: ${BIN}/openshift-install fehlt."
    [[ -s "${INSTALL_DIR}/master.ign" ]] || fail "Resume nicht möglich: ${INSTALL_DIR}/master.ign fehlt."
    [[ -s "${INSTALL_DIR}/auth/kubeconfig" ]] || fail "Resume nicht möglich: ${INSTALL_DIR}/auth/kubeconfig fehlt."
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    ca-certificates curl jq tar gzip openssl dnsutils netcat-openbsd \
    podman qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virtinst \
    wakeonlan netplan.io iproute2 iputils-ping

require_cmds() {
    local cmd
    for cmd in curl jq awk sed grep tar gzip dnsmasq dig podman virsh virt-install qemu-img wakeonlan openssl nc ip netplan base64 ping; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Befehl fehlt: $cmd"
    done
}

valid_public_key() {
    [[ -s "$1" ]] || return 1
    grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-sha2-|sk-(ssh-ed25519|ecdsa-sha2-))' "$1"
}

require_inputs() {
    if [[ ! -r "$PULL_SECRET_FILE" && "$PULL_SECRET_FILE" == "/etc/lernvirt/pull-secret.json" && -r /etc/lernvirt/pull-secret ]]; then
        PULL_SECRET_FILE=/etc/lernvirt/pull-secret
        warn "Verwende vorhandenes altes Pull Secret: $PULL_SECRET_FILE"
    fi
    [[ -r "$PULL_SECRET_FILE" ]] || fail "Pull Secret fehlt: $PULL_SECRET_FILE"
    jq -e . "$PULL_SECRET_FILE" >/dev/null || fail "Ungültiges Pull Secret: $PULL_SECRET_FILE"
    valid_public_key "$SSH_KEY_FILE" || fail "SSH Public Key fehlt oder ist ungültig: $SSH_KEY_FILE"
}

prepare_dirs() {
    mkdir -p "$BIN" "$INSTALL_DIR" "$DEBUG_DIR" "$NODE_DIR" "$HTTP_OCP" "$TFTP_OCP"
    chmod 0700 "$DEBUG_DIR"
}

configure_host_bridge() {
    log "LAN-Bridge ${BOOTSTRAP_BRIDGE} für Bootstrap vorbereiten"

    if ip link show "$BOOTSTRAP_BRIDGE" >/dev/null 2>&1; then
        ip -4 addr show dev "$BOOTSTRAP_BRIDGE" | grep -q " ${TERRA1_IP}/" \
            || fail "${BOOTSTRAP_BRIDGE} existiert, hat aber nicht ${TERRA1_IP}"
        LAN_IF="$(ls -1 "/sys/class/net/${BOOTSTRAP_BRIDGE}/brif" 2>/dev/null | head -n1 || true)"
        BOOTSTRAP_GATEWAY="$(ip -4 route show default dev "$BOOTSTRAP_BRIDGE" | awk 'NR==1 {print $3}')"
        [[ -n "$BOOTSTRAP_GATEWAY" ]] || fail "Kein Default-Gateway über ${BOOTSTRAP_BRIDGE}"
        printf '%s\n' "$BOOTSTRAP_BRIDGE" >"${DEBUG_DIR}/bootstrap-bridge"
        printf '%s\n' "$LAN_IF" >"${DEBUG_DIR}/lan-interface"
        printf '%s\n' "$BOOTSTRAP_GATEWAY" >"${DEBUG_DIR}/bootstrap-gateway"
        return 0
    fi

    LAN_IF="$(ip -4 route get "$TERRA2_IP" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
    [[ -n "$LAN_IF" && "$LAN_IF" != "lo" ]] || fail "LAN-Interface konnte nicht bestimmt werden"

    local lan_mac netplan_file
    lan_mac="$(cat "/sys/class/net/${LAN_IF}/address")"
    netplan_file="/etc/netplan/99-lernvirt-openshift-bridge.yaml"
    cat >"$netplan_file" <<EOF_NETPLAN
network:
  version: 2
  ethernets:
    ${LAN_IF}:
      dhcp4: false
      dhcp6: false
  bridges:
    ${BOOTSTRAP_BRIDGE}:
      interfaces:
        - ${LAN_IF}
      macaddress: ${lan_mac}
      dhcp4: true
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
EOF_NETPLAN
    chmod 0600 "$netplan_file"
    netplan generate
    netplan apply

    local i
    for i in $(seq 1 60); do
        ip -4 addr show dev "$BOOTSTRAP_BRIDGE" | grep -q " ${TERRA1_IP}/" && break
        sleep 1
    done
    ip -4 addr show dev "$BOOTSTRAP_BRIDGE" | grep -q " ${TERRA1_IP}/" \
        || fail "${TERRA1_IP} wurde nicht auf ${BOOTSTRAP_BRIDGE} übernommen"

    BOOTSTRAP_GATEWAY="$(ip -4 route show default dev "$BOOTSTRAP_BRIDGE" | awk 'NR==1 {print $3}')"
    [[ -n "$BOOTSTRAP_GATEWAY" ]] || fail "Kein Default-Gateway über ${BOOTSTRAP_BRIDGE}"
    printf '%s\n' "$BOOTSTRAP_BRIDGE" >"${DEBUG_DIR}/bootstrap-bridge"
    printf '%s\n' "$LAN_IF" >"${DEBUG_DIR}/lan-interface"
    printf '%s\n' "$BOOTSTRAP_GATEWAY" >"${DEBUG_DIR}/bootstrap-gateway"
}

reverse_ipv4() {
    local ip="$1" a b c d
    IFS=. read -r a b c d <<<"$ip"
    printf '%s.%s.%s.%s.in-addr.arpa' "$d" "$c" "$b" "$a"
}

configure_dnsmasq() {
    log "OpenShift DNS als Add-on zu pxe-stack konfigurieren"
    [[ -f /etc/dnsmasq.d/pxe.conf ]] || fail "Fehlt: /etc/dnsmasq.d/pxe.conf"

    # pxe-stack betreibt denselben dnsmasq für Proxy-DHCP/TFTP mit port=0.
    # OpenShift benötigt zusätzlich DNS. "port" darf in dnsmasq nur einmal
    # definiert sein, deshalb wird die bestehende Einstellung umgeschaltet.
    if grep -Eq '^[[:space:]]*port[[:space:]]*=[[:space:]]*0[[:space:]]*$' /etc/dnsmasq.d/pxe.conf; then
        sed -i -E 's/^[[:space:]]*port[[:space:]]*=[[:space:]]*0[[:space:]]*$/port=53/' /etc/dnsmasq.d/pxe.conf
    elif ! grep -Eq '^[[:space:]]*port[[:space:]]*=[[:space:]]*53[[:space:]]*$' /etc/dnsmasq.d/pxe.conf; then
        fail "Unerwartete dnsmasq-port-Einstellung in /etc/dnsmasq.d/pxe.conf"
    fi

    local resolver_file=/run/systemd/resolve/resolv.conf
    [[ -r "$resolver_file" ]] || resolver_file=/etc/resolv.conf

    cat >/etc/dnsmasq.d/zz-openshift.conf <<EOF_DNS
# OpenShift DNS Add-on. nginx bleibt unverändert.
listen-address=${TERRA1_IP}
resolv-file=${resolver_file}

host-record=api.${CLUSTER_NAME}.${BASE_DOMAIN},${TERRA1_IP}
host-record=api-int.${CLUSTER_NAME}.${BASE_DOMAIN},${TERRA1_IP}
host-record=bootstrap.${CLUSTER_NAME}.${BASE_DOMAIN},${BOOTSTRAP_IP}
host-record=terra2.${CLUSTER_NAME}.${BASE_DOMAIN},${TERRA2_IP}
host-record=terra3.${CLUSTER_NAME}.${BASE_DOMAIN},${TERRA3_IP}
host-record=terra4.${CLUSTER_NAME}.${BASE_DOMAIN},${TERRA4_IP}
address=/.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/${INGRESS_IP}

ptr-record=$(reverse_ipv4 "$TERRA2_IP"),terra2.${CLUSTER_NAME}.${BASE_DOMAIN}
ptr-record=$(reverse_ipv4 "$TERRA3_IP"),terra3.${CLUSTER_NAME}.${BASE_DOMAIN}
ptr-record=$(reverse_ipv4 "$TERRA4_IP"),terra4.${CLUSTER_NAME}.${BASE_DOMAIN}
EOF_DNS

    # Kann von libvirt angelegt werden und mit bind-dynamic kollidieren.
    rm -f /etc/dnsmasq.d/libvirt-daemon

    # Auf Ubuntu prüft systemd den kompletten Debian/Ubuntu-Konfigurationssatz
    # über systemd-helper. Ein blosses "dnsmasq --test" kann dabei Dateien
    # aus /etc/dnsmasq.d übersehen.
    if [[ -x /usr/share/dnsmasq/systemd-helper ]]; then
        /usr/share/dnsmasq/systemd-helper checkconfig
    else
        dnsmasq --test
    fi
    systemctl restart dnsmasq

    dig +short @"${TERRA1_IP}" "api.${CLUSTER_NAME}.${BASE_DOMAIN}" | grep -qx "$TERRA1_IP" || fail "DNS api fehlgeschlagen"
    dig +short @"${TERRA1_IP}" "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}" | grep -qx "$TERRA1_IP" || fail "DNS api-int fehlgeschlagen"
    dig +short @"${TERRA1_IP}" "test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}" | grep -qx "$INGRESS_IP" || fail "DNS *.apps fehlgeschlagen"
}

configure_terra1_hosts() {
    log "/etc/hosts auf terra1 für OpenShift"
    sed -i '/^# BEGIN LERNVIRT OPENSHIFT$/,/^# END LERNVIRT OPENSHIFT$/d' /etc/hosts
    cat >>/etc/hosts <<EOF_HOSTS
# BEGIN LERNVIRT OPENSHIFT
${TERRA1_IP} api.${CLUSTER_NAME}.${BASE_DOMAIN} api-int.${CLUSTER_NAME}.${BASE_DOMAIN}
${INGRESS_IP} console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN} oauth-openshift.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${BOOTSTRAP_IP} bootstrap.${CLUSTER_NAME}.${BASE_DOMAIN} bootstrap
${TERRA2_IP} terra2.${CLUSTER_NAME}.${BASE_DOMAIN} terra2
${TERRA3_IP} terra3.${CLUSTER_NAME}.${BASE_DOMAIN} terra3
${TERRA4_IP} terra4.${CLUSTER_NAME}.${BASE_DOMAIN} terra4
# END LERNVIRT OPENSHIFT
EOF_HOSTS
}

download_tools() {
    log "OpenShift Release und Tools bestimmen"
    local release_txt client_url installer_url
    release_txt="$(curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_CHANNEL}/release.txt")"
    OCP_VERSION="$(awk '/^Name:/ {print $2; exit}' <<<"$release_txt")"
    [[ -n "$OCP_VERSION" ]] || fail "OpenShift Release konnte nicht bestimmt werden"
    printf '%s\n' "$OCP_VERSION" >"${DEBUG_DIR}/openshift-version"

    client_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz"
    installer_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz"
    local tmp
    tmp="$(mktemp -d)"
    curl -fL --retry 5 "$client_url" -o "$tmp/client.tgz"
    curl -fL --retry 5 "$installer_url" -o "$tmp/installer.tgz"
    tar -xzf "$tmp/client.tgz" -C "$BIN" oc kubectl
    tar -xzf "$tmp/installer.tgz" -C "$BIN" openshift-install
    chmod 0755 "$BIN/oc" "$BIN/kubectl" "$BIN/openshift-install"
    install -m 0755 "$BIN/oc" /usr/local/bin/oc
    install -m 0755 "$BIN/kubectl" /usr/local/bin/kubectl
    install -m 0755 "$BIN/openshift-install" /usr/local/bin/openshift-install
    rm -rf "$tmp"

    "$BIN/oc" version --client
    "$BIN/openshift-install" version
}

create_install_config() {
    log "OpenShift Install-Konfiguration erzeugen"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    rm -rf "${DEBUG_DIR}/manifests" "${DEBUG_DIR}/openshift"

    local pull sshkey
    pull="$(jq -c . "$PULL_SECRET_FILE")"
    sshkey="$(tr -d '\r\n' < "$SSH_KEY_FILE")"
    cat >"${INSTALL_DIR}/install-config.yaml" <<EOF_INSTALL
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 0
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: ${MACHINE_NETWORK_CIDR}
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '${pull}'
sshKey: '${sshkey}'
EOF_INSTALL
    install -m 0600 "${INSTALL_DIR}/install-config.yaml" "${DEBUG_DIR}/install-config.yaml"

    "$BIN/openshift-install" create manifests --dir="$INSTALL_DIR"
    local scheduler="${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml"
    [[ -f "$scheduler" ]] || fail "Scheduler-Manifest fehlt: $scheduler"
    sed -i 's/mastersSchedulable: false/mastersSchedulable: true/' "$scheduler"
    grep -q 'mastersSchedulable: true' "$scheduler" || fail "Control Plane wurde nicht schedulable gesetzt"

    cp -a "${INSTALL_DIR}/manifests" "${DEBUG_DIR}/manifests"
    cp -a "${INSTALL_DIR}/openshift" "${DEBUG_DIR}/openshift"
    "$BIN/openshift-install" create ignition-configs --dir="$INSTALL_DIR"

    for f in bootstrap.ign master.ign worker.ign metadata.json; do
        [[ -f "${INSTALL_DIR}/${f}" ]] && cp -a "${INSTALL_DIR}/${f}" "${DEBUG_DIR}/${f}"
    done
    install -m 0644 "${INSTALL_DIR}/master.ign" "$HTTP_OCP/master.ign"
    install -m 0644 "${INSTALL_DIR}/bootstrap.ign" "$HTTP_OCP/bootstrap.ign"

    MCS_URL="$(jq -r '[.ignition.config.merge[]?.source, .ignition.config.replace.source?] | map(select(. != null)) | .[0] // empty' "${INSTALL_DIR}/master.ign")"
    [[ -n "$MCS_URL" ]] || fail "MCS URL konnte aus master.ign nicht bestimmt werden"
    printf '%s\n' "$MCS_URL" >"${DEBUG_DIR}/mcs-url"
}

prepare_bootstrap_ignition() {
    log "Bootstrap-Ignition für LAN und Diagnose erweitern"
    [[ -n "$BOOTSTRAP_GATEWAY" ]] || fail "Bootstrap-Gateway ist nicht gesetzt"

    local sshkey core_password_hash nm_file nm_source hostname_source tmp
    sshkey="$(tr -d '\r\n' < "$SSH_KEY_FILE")"
    core_password_hash="$(openssl passwd -6 "$CORE_PASSWORD")"
    nm_file="${DEBUG_DIR}/bootstrap.nmconnection"
    cat >"$nm_file" <<EOF_NM
[connection]
id=openshift-bootstrap
type=ethernet
autoconnect=true
autoconnect-priority=999

[ethernet]
mac-address=${BOOTSTRAP_MAC}

[ipv4]
method=manual
address1=${BOOTSTRAP_IP}/${BOOTSTRAP_PREFIX},${BOOTSTRAP_GATEWAY}
dns=${TERRA1_IP};
ignore-auto-dns=true
route-metric=10

[ipv6]
method=disabled
EOF_NM
    chmod 0600 "$nm_file"

    nm_source="data:text/plain;charset=utf-8;base64,$(base64 -w0 < "$nm_file")"
    hostname_source="data:text/plain;charset=utf-8;base64,$(printf 'bootstrap.%s.%s\n' "$CLUSTER_NAME" "$BASE_DOMAIN" | base64 -w0)"
    tmp="$(mktemp)"
    jq --arg key "$sshkey" --arg password "$core_password_hash" --arg nm "$nm_source" --arg hostname "$hostname_source" '
      .storage = (.storage // {}) |
      .storage.files = ([ (.storage.files // [])[] |
        select(.path != "/etc/NetworkManager/system-connections/openshift-bootstrap.nmconnection" and .path != "/etc/hostname")
      ] + [
        {path:"/etc/NetworkManager/system-connections/openshift-bootstrap.nmconnection",mode:384,overwrite:true,contents:{source:$nm}},
        {path:"/etc/hostname",mode:420,overwrite:true,contents:{source:$hostname}}
      ]) |
      .passwd = (.passwd // {}) |
      .passwd.users = ([ (.passwd.users // [])[] | select(.name != "core") ] + [
        (([(.passwd.users // [])[] | select(.name == "core")][0] // {name:"core"})
          | .name="core" | .passwordHash=$password
          | .sshAuthorizedKeys=(((.sshAuthorizedKeys // []) + [$key]) | unique))
      ])
    ' "$BOOTSTRAP_IGN" >"$tmp"
    jq -e . "$tmp" >/dev/null || fail "Bootstrap-Ignition ist ungültig"
    install -m 0600 "$tmp" "$BOOTSTRAP_IGN"
    install -m 0644 "$BOOTSTRAP_IGN" "$HTTP_OCP/bootstrap.ign"
    cp -a "$BOOTSTRAP_IGN" "${DEBUG_DIR}/bootstrap-final.ign"
    rm -f "$tmp"
}

download_rhcos() {
    log "RHCOS für OpenShift ${OCP_VERSION} laden"
    local stream kernel_url initramfs_url rootfs_url qemu_url
    stream="$("$BIN/openshift-install" coreos print-stream-json)"
    printf '%s\n' "$stream" >"${DEBUG_DIR}/coreos-stream.json"

    kernel_url="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.kernel.location // empty' <<<"$stream")"
    initramfs_url="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.initramfs.location // empty' <<<"$stream")"
    rootfs_url="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.rootfs.location // empty' <<<"$stream")"
    qemu_url="$(jq -r '.architectures.x86_64.artifacts.qemu.formats."qcow2.gz".disk.location // empty' <<<"$stream")"
    for u in "$kernel_url" "$initramfs_url" "$rootfs_url" "$qemu_url"; do
        [[ "$u" == http* ]] || fail "Ungültige RHCOS URL: $u"
    done

    curl -fL --retry 5 "$kernel_url" -o "$TFTP_OCP/rhcos-live-kernel-x86_64"
    curl -fL --retry 5 "$initramfs_url" -o "$OCP_DIR/rhcos-live-initramfs.x86_64.img"
    curl -fL --retry 5 "$rootfs_url" -o "$HTTP_OCP/rhcos-live-rootfs.x86_64.img"

    RHCOS_QEMU_IMAGE="/var/lib/libvirt/images/rhcos-${OCP_VERSION}.qcow2"
    mkdir -p /var/lib/libvirt/images
    if [[ ! -s "$RHCOS_QEMU_IMAGE" || "$OCP_FORCE" == "1" ]]; then
        curl -fL --retry 5 "$qemu_url" -o "${RHCOS_QEMU_IMAGE}.gz"
        gzip -d -f "${RHCOS_QEMU_IMAGE}.gz"
    fi
}

create_node_ignition() {
    local fqdn="$1" out="$2"
    local sshkey core_password_hash ignition_version hostname_b64
    sshkey="$(tr -d '\r\n' < "$SSH_KEY_FILE")"
    core_password_hash="$(openssl passwd -6 "$CORE_PASSWORD")"
    ignition_version="$(jq -r '.ignition.version' "${INSTALL_DIR}/master.ign")"
    hostname_b64="$(printf '%s\n' "$fqdn" | base64 -w0)"
    jq -n --arg version "$ignition_version" --arg key "$sshkey" --arg password "$core_password_hash" \
      --arg hostname "data:text/plain;base64,${hostname_b64}" '{
        ignition:{version:$version},
        passwd:{users:[{name:"core",passwordHash:$password,sshAuthorizedKeys:[$key]}]},
        storage:{files:[{path:"/etc/hostname",mode:420,overwrite:true,contents:{source:$hostname}}]}
      }' >"$out"
}

create_node_network() {
    local node="$1" mac="$2" fqdn="$3" out="$4"
    cat >"$out" <<EOF_NM
[connection]
id=openshift-${node}
type=ethernet
autoconnect=true
autoconnect-priority=100

[ethernet]
mac-address=${mac}

[ipv4]
method=auto
ignore-auto-dns=true
dns=${TERRA1_IP};
dhcp-hostname=${fqdn}

[ipv6]
method=disabled
EOF_NM
    chmod 0600 "$out"
}

create_node_post_install() {
    local node="$1" out="$2"
    cat >"$out" <<EOF_POST
#!/usr/bin/env bash
set -Eeuo pipefail
BOOT_DEV="\$(blkid -L boot || true)"
[[ -n "\$BOOT_DEV" ]] || { echo "RHCOS boot partition nicht gefunden" >&2; exit 1; }
mkdir -p /mnt/lernvirt-boot
mount -o rw "\$BOOT_DEV" /mnt/lernvirt-boot
cat >/mnt/lernvirt-boot/lernvirt-installed <<'MARKER'
node=${node}
cluster=${CLUSTER_NAME}.${BASE_DOMAIN}
MARKER
sync
umount /mnt/lernvirt-boot
EOF_POST
    chmod 0755 "$out"
}

customize_node_pxe() {
    local node="$1" mac="$2" ipaddr="$3"
    local fqdn="${node}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    local dir="${NODE_DIR}/${node}" tftp_dir="${TFTP_OCP}/${node}"
    local node_ign="${dir}/node.ign" node_nm="${dir}/network.nmconnection"
    local post="${dir}/post-install.sh" output="${dir}/rhcos-live-initramfs.x86_64.img"

    log "RHCOS PXE für ${node} (${ipaddr}, ${mac}) erzeugen"
    rm -rf "$dir" "$tftp_dir"
    mkdir -p "$dir" "$tftp_dir"
    create_node_ignition "$fqdn" "$node_ign"
    create_node_network "$node" "$mac" "$fqdn" "$node_nm"
    create_node_post_install "$node" "$post"

    podman run --pull=always --rm \
        -v "${OCP_DIR}:${OCP_DIR}:Z" \
        quay.io/coreos/coreos-installer:release \
        pxe customize \
        --dest-device "$INSTALL_DISK" \
        --dest-ignition "${INSTALL_DIR}/master.ign" \
        --dest-ignition "$node_ign" \
        --network-keyfile "$node_nm" \
        --post-install "$post" \
        -o "$output" \
        "${OCP_DIR}/rhcos-live-initramfs.x86_64.img"

    install -m 0644 "$output" "${tftp_dir}/rhcos-live-initramfs.x86_64.img"
}

create_all_node_pxe() {
    customize_node_pxe terra2 "$TERRA2_MAC" "$TERRA2_IP"
    customize_node_pxe terra3 "$TERRA3_MAC" "$TERRA3_IP"
    customize_node_pxe terra4 "$TERRA4_MAC" "$TERRA4_IP"
}

install_openshift_stack() {
    log "OpenShift Stack in pxe-stack integrieren"
    cat >"${TFTP_ROOT}/grub/stacks/openshift.cfg" <<'EOF_GRUB'
set ocp_initrd=""
if [ "${variant}" = "terra2" ]; then
    set ocp_initrd="/linux/openshift/terra2/rhcos-live-initramfs.x86_64.img"
fi
if [ "${variant}" = "terra3" ]; then
    set ocp_initrd="/linux/openshift/terra3/rhcos-live-initramfs.x86_64.img"
fi
if [ "${variant}" = "terra4" ]; then
    set ocp_initrd="/linux/openshift/terra4/rhcos-live-initramfs.x86_64.img"
fi

menuentry "Install OpenShift RHCOS (${variant})" {
    if [ -z "${ocp_initrd}" ]; then
        echo "ERROR: OpenShift variant muss terra2, terra3 oder terra4 sein"
        sleep 10
    else
        linux /linux/openshift/rhcos-live-kernel-x86_64 \
          ip=dhcp \
          rd.neednet=1 \
          ignition.firstboot \
          ignition.platform.id=metal \
          coreos.live.rootfs_url=http://${pxe_server}/openshift/rhcos-live-rootfs.x86_64.img
        initrd ${ocp_initrd}
    fi
}
EOF_GRUB
    chmod 0644 "${TFTP_ROOT}/grub/stacks/openshift.cfg"
}

ensure_rhcos_marker_compat() {
    local grub="${TFTP_ROOT}/grub/grub.cfg"
    [[ -r "$grub" ]] || fail "GRUB Basis fehlt: $grub"

    # Ältere pxe-stack-Versionen kennen nur den Ubuntu-Marker unter
    # /boot/lernvirt-installed. Auf RHCOS ist /boot eine eigene Partition;
    # aus Sicht von PXE-GRUB liegt der Marker dort als /lernvirt-installed.
    if ! grep -Fq 'search --no-floppy --file --set=localroot /lernvirt-installed' "$grub"; then
        local tmp_marker
        tmp_marker="$(mktemp)"
        awk '
          /if search --no-floppy --file --set=localroot \/boot\/lernvirt-installed; then/ {
            print "if search --no-floppy --file --set=localroot /boot/lernvirt-installed; then"
            print "    set lernvirt_installed=\"1\""
            print "    set default=\"0\""
            print "elif search --no-floppy --file --set=localroot /lernvirt-installed; then"
            print "    # RHCOS verwendet eine eigene boot-Partition; dort liegt der Marker im Partitions-Root."
            print "    set lernvirt_installed=\"1\""
            print "    set default=\"0\""
            skip=1
            next
          }
          skip && /fi/ { print "fi"; skip=0; next }
          skip { next }
          { print }
        ' "$grub" >"$tmp_marker"
        grep -Fq '/lernvirt-installed' "$tmp_marker" || fail "RHCOS Marker-Fallback konnte nicht ergänzt werden"
        install -m 0644 "$tmp_marker" "$grub"
        rm -f "$tmp_marker"
    fi

    # Beim zweiten Boot darf PXE-GRUB nicht nur mit 'exit' an die Firmware
    # zurückgeben. Einige Rechner landen dabei im Firmware-Bootmenü. Stattdessen
    # wird der lokal installierte EFI-Bootloader direkt gechainloadet.
    if ! grep -Fq '/EFI/redhat/shimx64.efi' "$grub"; then
        local tmp_boot
        tmp_boot="$(mktemp)"
        awk '
          BEGIN { skip=0 }
          !skip && /^menuentry "Local boot \(lernvirt\)" \{/ {
            print "menuentry \"Local boot (lernvirt)\" {"
            print "    if [ -z \"${localroot}\" ]; then"
            print "        echo \"Keine lokale lernvirt-Installation gefunden\""
            print "        sleep 2"
            print "        exit"
            print "    fi"
            print ""
            print "    insmod chain"
            print "    if search --no-floppy --file --set=efiroot /EFI/redhat/shimx64.efi; then"
            print "        set root=\"${efiroot}\""
            print "        chainloader /EFI/redhat/shimx64.efi"
            print "        boot"
            print "    fi"
            print "    if search --no-floppy --file --set=efiroot /EFI/redhat/grubx64.efi; then"
            print "        set root=\"${efiroot}\""
            print "        chainloader /EFI/redhat/grubx64.efi"
            print "        boot"
            print "    fi"
            print "    if search --no-floppy --file --set=efiroot /EFI/ubuntu/shimx64.efi; then"
            print "        set root=\"${efiroot}\""
            print "        chainloader /EFI/ubuntu/shimx64.efi"
            print "        boot"
            print "    fi"
            print "    if search --no-floppy --file --set=efiroot /EFI/BOOT/BOOTX64.EFI; then"
            print "        set root=\"${efiroot}\""
            print "        chainloader /EFI/BOOT/BOOTX64.EFI"
            print "        boot"
            print "    fi"
            print ""
            print "    set root=\"${localroot}\""
            print "    if [ -f /grub2/grub.cfg ]; then"
            print "        set prefix=\"(${localroot})/grub2\""
            print "        configfile /grub2/grub.cfg"
            print "    fi"
            print "    if [ -f /grub/grub.cfg ]; then"
            print "        set prefix=\"(${localroot})/grub\""
            print "        configfile /grub/grub.cfg"
            print "    fi"
            print "    if [ -f /boot/grub/grub.cfg ]; then"
            print "        set prefix=\"(${localroot})/boot/grub\""
            print "        configfile /boot/grub/grub.cfg"
            print "    fi"
            print "    if [ -f /boot/grub2/grub.cfg ]; then"
            print "        set prefix=\"(${localroot})/boot/grub2\""
            print "        configfile /boot/grub2/grub.cfg"
            print "    fi"
            print "    echo \"Lokaler Bootloader wurde nicht gefunden\""
            print "    sleep 3"
            print "    exit"
            print "}"
            print ""
            skip=1
            next
          }
          skip && /^source \(tftp/ { skip=0; print; next }
          skip { next }
          { print }
        ' "$grub" >"$tmp_boot"
        grep -Fq '/EFI/redhat/shimx64.efi' "$tmp_boot" || fail "RHCOS Local-Boot-Fallback konnte nicht ergänzt werden"
        install -m 0644 "$tmp_boot" "$grub"
        rm -f "$tmp_boot"
    fi
}

update_rack_host_rules() {
    log "rack.conf für terra2-4 auf OpenShift setzen"
    local m2="${TERRA2_MAC,,}" m3="${TERRA3_MAC,,}" m4="${TERRA4_MAC,,}" tmp
    tmp="$(mktemp)"
    awk -v m2="$m2" -v m3="$m3" -v m4="$m4" '
      BEGIN { inhosts=0; saw=0 }
      /^[[:space:]]*HOSTS[[:space:]]*=\(/ { inhosts=1; saw=1; print; next }
      inhosts && /^[[:space:]]*\)[[:space:]]*(#.*)?$/ {
        print "    \"" m2 "|openshift|terra2\""
        print "    \"" m3 "|openshift|terra3\""
        print "    \"" m4 "|openshift|terra4\""
        print
        inhosts=0
        next
      }
      inhosts {
        line=tolower($0)
        if (index(line,m2)>0 || index(line,m3)>0 || index(line,m4)>0) next
      }
      { print }
      END { if (!saw || inhosts) exit 42 }
    ' "$RACK_CONFIG" >"$tmp" || fail "HOSTS-Block in $RACK_CONFIG konnte nicht aktualisiert werden"
    install -m 0644 "$tmp" "$RACK_CONFIG"
    rm -f "$tmp"
    "${TFTP_ROOT}/bin/pxe-update"
}

validate_nginx_unchanged() {
    log "PXE-nginx unverändert verwenden"
    systemctl is-active --quiet nginx || fail "nginx läuft nicht. pxe-stack Basis prüfen."
    [[ -r /etc/nginx/sites-available/pxe-stack ]] || warn "pxe-stack nginx Site nicht gefunden; nginx wird trotzdem nicht verändert."
    curl -fsS "http://${TERRA1_IP}/openshift/master.ign" | jq -e . >/dev/null || fail "master.ign ist über bestehenden nginx nicht lesbar"
    curl -fsSI "http://${TERRA1_IP}/openshift/rhcos-live-rootfs.x86_64.img" >/dev/null || fail "RHCOS rootfs ist über bestehenden nginx nicht lesbar"
}

validate_generated_artifacts() {
    log "Generierte PXE-/Ignition-Artefakte prüfen"
    local sshkey node fqdn dir
    sshkey="$(tr -d '\r\n' < "$SSH_KEY_FILE")"
    grep -R -F -l -- "$sshkey" "${DEBUG_DIR}/manifests" "${DEBUG_DIR}/openshift" \
        >"${DEBUG_DIR}/ssh-key-locations" 2>/dev/null || true

    for node in terra2 terra3 terra4; do
        fqdn="${node}.${CLUSTER_NAME}.${BASE_DOMAIN}"
        dir="${NODE_DIR}/${node}"
        jq -e --arg key "$sshkey" '.passwd.users[] | select(.name=="core") | (.sshAuthorizedKeys | index($key)) != null' \
          "${dir}/node.ign" >/dev/null || fail "SSH-Key fehlt in ${node}/node.ign"
        jq -e '.passwd.users[] | select(.name=="core") | (.passwordHash | length) > 20' \
          "${dir}/node.ign" >/dev/null || fail "Core-Passwort fehlt in ${node}/node.ign"
        grep -Fqx "dns=${TERRA1_IP};" "${dir}/network.nmconnection" || fail "DNS fehlt für ${node}"
        grep -Fqx "dhcp-hostname=${fqdn}" "${dir}/network.nmconnection" || fail "Hostname fehlt für ${node}"
        [[ -s "${TFTP_OCP}/${node}/rhcos-live-initramfs.x86_64.img" ]] || fail "Custom initramfs fehlt für ${node}"
    done

    jq -e --arg key "$sshkey" '.passwd.users[] | select(.name=="core") | (.sshAuthorizedKeys | index($key)) != null' \
      "$BOOTSTRAP_IGN" >/dev/null || fail "SSH-Key fehlt in Bootstrap-Ignition"
    [[ -s "${DEBUG_DIR}/bootstrap.nmconnection" ]] || fail "Bootstrap NetworkManager-Keyfile fehlt"
    grep -Fq '/lernvirt-installed' "${TFTP_ROOT}/grub/grub.cfg" || fail "RHCOS Marker-Fallback fehlt in grub.cfg"
    grep -Fq 'menuentry "Install OpenShift RHCOS' "${TFTP_ROOT}/grub/stacks/openshift.cfg" || fail "OpenShift Stack fehlt"
    ip link show "$BOOTSTRAP_BRIDGE" >/dev/null 2>&1 || fail "Bootstrap-Bridge ${BOOTSTRAP_BRIDGE} fehlt"
}

configure_libvirt() {
    log "libvirt für Bootstrap vorbereiten"
    if grep -qE '^[[:space:]]*security_driver[[:space:]]*=' /etc/libvirt/qemu.conf; then
        sed -i -E 's|^[[:space:]]*security_driver[[:space:]]*=.*|security_driver = "none"|' /etc/libvirt/qemu.conf
    else
        printf '\nsecurity_driver = "none"\n' >>/etc/libvirt/qemu.conf
    fi
    systemctl restart libvirtd 2>/dev/null || true
    systemctl restart virtqemud 2>/dev/null || true
}

resolve_companion_scripts() {
    local script_source="${BASH_SOURCE[0]:-}" script_dir="" tmp
    if [[ -n "$script_source" && "$script_source" != "-" ]]; then
        script_dir="$(cd "$(dirname "$script_source")" 2>/dev/null && pwd || true)"
    fi

    if [[ -n "$script_dir" && -x "$script_dir/install-haproxy.sh" ]]; then
        install -m 0755 "$script_dir/install-haproxy.sh" /usr/local/sbin/lernvirt-install-haproxy
    else
        tmp="$(mktemp)"
        curl -fsSL "$HAPROXY_INSTALLER_URL" -o "$tmp"
        bash -n "$tmp"
        install -m 0755 "$tmp" /usr/local/sbin/lernvirt-install-haproxy
        rm -f "$tmp"
    fi
    HAPROXY_INSTALLER=/usr/local/sbin/lernvirt-install-haproxy

    if [[ -n "$script_dir" && -r "$script_dir/bin/openshift-status" ]]; then
        install -m 0755 "$script_dir/bin/openshift-status" /usr/local/sbin/openshift-status
    else
        tmp="$(mktemp)"
        curl -fsSL "$STATUS_SCRIPT_URL" -o "$tmp"
        bash -n "$tmp"
        install -m 0755 "$tmp" /usr/local/sbin/openshift-status
        rm -f "$tmp"
    fi
}

create_bootstrap_vm() {
    log "Bootstrap-VM erzeugen"
    local bootstrap_ign_libvirt="/var/lib/libvirt/images/${BOOTSTRAP_NAME}.ign"
    virsh destroy "$BOOTSTRAP_NAME" >/dev/null 2>&1 || true
    virsh undefine "$BOOTSTRAP_NAME" --nvram >/dev/null 2>&1 || true
    rm -f "$BOOTSTRAP_DISK" "$bootstrap_ign_libvirt"

    if ping -c1 -W1 "$BOOTSTRAP_IP" >/dev/null 2>&1; then
        fail "Bootstrap-IP ${BOOTSTRAP_IP} ist bereits belegt"
    fi

    qemu-img create -q -f qcow2 -F qcow2 -b "$RHCOS_QEMU_IMAGE" "$BOOTSTRAP_DISK" "${BOOTSTRAP_DISK_GIB}G"
    cp "$BOOTSTRAP_IGN" "$bootstrap_ign_libvirt"
    if id libvirt-qemu >/dev/null 2>&1; then
        chown libvirt-qemu:kvm "$bootstrap_ign_libvirt" 2>/dev/null || chown libvirt-qemu:libvirt "$bootstrap_ign_libvirt" 2>/dev/null || true
    fi
    chmod 0640 "$bootstrap_ign_libvirt"

    virt-install \
        --name "$BOOTSTRAP_NAME" \
        --memory "$BOOTSTRAP_RAM_MIB" \
        --vcpus "$BOOTSTRAP_VCPUS" \
        --disk "path=${BOOTSTRAP_DISK},format=qcow2,bus=virtio" \
        --network "bridge=${BOOTSTRAP_BRIDGE},model=virtio,mac=${BOOTSTRAP_MAC}" \
        --os-variant fedora-coreos-stable \
        --import \
        --graphics none \
        --noautoconsole \
        --qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=${bootstrap_ign_libvirt}"
}

wait_for_bootstrap_ports() {
    log "Bootstrap-Dienste direkt prüfen"
    local i
    for i in $(seq 1 450); do
        if nc -z -w1 "$BOOTSTRAP_IP" 22623 >/dev/null 2>&1 && nc -z -w1 "$BOOTSTRAP_IP" 6443 >/dev/null 2>&1; then
            echo "Bootstrap 22623/6443 erreichbar"
            return 0
        fi
        sleep 2
    done
    fail "Bootstrap-Dienste 22623/6443 nicht rechtzeitig erreichbar"
}

wait_for_mcs() {
    log "Machine Config Server vor Start der Masters prüfen"
    local i
    for i in $(seq 1 180); do
        if curl -kfsS --connect-timeout 3 "$MCS_URL" >/dev/null 2>&1; then
            echo "MCS erreichbar: $MCS_URL"
            return 0
        fi
        sleep 2
    done
    fail "MCS nicht erreichbar: $MCS_URL"
}

wake_nodes() {
    log "terra2-4 per Wake-on-LAN starten"
    wakeonlan "$TERRA2_MAC"
    wakeonlan "$TERRA3_MAC"
    wakeonlan "$TERRA4_MAC"
}

remove_bootstrap_vm() {
    log "Bootstrap-VM entfernen"
    local had_domain=0 i
    if virsh dominfo "$BOOTSTRAP_NAME" >/dev/null 2>&1; then
        had_domain=1
        virsh destroy "$BOOTSTRAP_NAME" >/dev/null 2>&1 || true
        virsh undefine "$BOOTSTRAP_NAME" --nvram >/dev/null 2>&1 || \
            virsh undefine "$BOOTSTRAP_NAME" >/dev/null 2>&1 || true
    else
        echo "Bootstrap-VM ist bereits entfernt."
    fi
    rm -f "$BOOTSTRAP_DISK" "/var/lib/libvirt/images/${BOOTSTRAP_NAME}.ign"

    # Bei einem wiederholten Resume kann die frühere Bootstrap-IP bereits
    # korrekt vom Ingress-Namespace übernommen worden sein. Nur nach dem
    # tatsächlichen Entfernen einer Bootstrap-VM auf das Freiwerden warten.
    [[ "$had_domain" == "1" ]] || return 0
    for i in $(seq 1 30); do
        ping -c1 -W1 "$BOOTSTRAP_IP" >/dev/null 2>&1 || return 0
        sleep 1
    done
    fail "Bootstrap-IP ${BOOTSTRAP_IP} ist nach Entfernen der VM noch belegt"
}

print_access_info() {
    cat <<EOF_INFO

Diagnose:
  openshift-status
  tail -f ${LOG}
  Kubeconfig: ${INSTALL_DIR}/auth/kubeconfig
  Bootstrap: ${BOOTSTRAP_IP} via ${BOOTSTRAP_BRIDGE}
  Ingress LB: ${INGRESS_IP} (nach bootstrap-complete)

RHCOS Konsole:
  Benutzer: core
  Passwort: ${CORE_PASSWORD}

SSH:
  ssh -i ~/.ssh/lerncloud core@${TERRA2_IP}
  ssh -i ~/.ssh/lerncloud core@${TERRA3_IP}
  ssh -i ~/.ssh/lerncloud core@${TERRA4_IP}
EOF_INFO
}

resume_hint() {
    cat >&2 <<EOF_RESUME

Die OpenShift-Installation kann weiterlaufen, auch wenn openshift-install ein
Zeitlimit erreicht. Vorhandene Ignition-/PKI-Artefakte NICHT neu erzeugen.
Fortsetzen mit:
  sudo $0 resume
EOF_RESUME
}

wait_bootstrap_complete() {
    log "Auf bootstrap-complete warten"
    if "$BIN/openshift-install" wait-for bootstrap-complete --dir="$INSTALL_DIR" --log-level=info; then
        return 0
    fi
    warn "bootstrap-complete wurde noch nicht erreicht oder der Wait ist abgelaufen."
    resume_hint
    exit 2
}

wait_install_complete() {
    log "Auf install-complete warten"
    if "$BIN/openshift-install" wait-for install-complete --dir="$INSTALL_DIR" --log-level=info; then
        return 0
    fi
    warn "install-complete wurde noch nicht erreicht oder der Wait ist abgelaufen."
    resume_hint
    exit 2
}

finish_after_bootstrap() {
    remove_bootstrap_vm
    "$HAPROXY_INSTALLER" final

    wait_install_complete

    touch "${OCP_DIR}/installed"
    log "OpenShift Installation abgeschlossen"
    echo "Console: https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
    echo "Kubeconfig: ${INSTALL_DIR}/auth/kubeconfig"
    echo "Kubeadmin: $(cat "${INSTALL_DIR}/auth/kubeadmin-password" 2>/dev/null || true)"
}

resume_installation() {
    log "OpenShift Installation fortsetzen"
    resolve_companion_scripts

    if [[ -e "${OCP_DIR}/installed" ]]; then
        echo "OpenShift ist bereits als vollständig installiert markiert: ${OCP_DIR}/installed"
        echo "Console: https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
        echo "Kubeconfig: ${INSTALL_DIR}/auth/kubeconfig"
        return 0
    fi

    # Solange die Bootstrap-VM noch existiert, API/MCS weiterhin mit dem
    # Bootstrap-Backend betreiben. Dies verändert keine Ignition-/PKI-Dateien.
    if virsh dominfo "$BOOTSTRAP_NAME" >/dev/null 2>&1; then
        "$HAPROXY_INSTALLER" bootstrap
    fi

    wait_bootstrap_complete
    finish_after_bootstrap
}

install_new_cluster() {
    require_inputs
    prepare_dirs
    configure_host_bridge
    configure_dnsmasq
    configure_terra1_hosts
    download_tools
    create_install_config
    prepare_bootstrap_ignition
    download_rhcos
    create_all_node_pxe
    install_openshift_stack
    ensure_rhcos_marker_compat
    update_rack_host_rules
    validate_nginx_unchanged
    validate_generated_artifacts
    configure_libvirt
    resolve_companion_scripts

    "$HAPROXY_INSTALLER" bootstrap
    create_bootstrap_vm
    wait_for_bootstrap_ports
    wait_for_mcs
    print_access_info
    wake_nodes

    wait_bootstrap_complete
    finish_after_bootstrap
}

main() {
    require_cmds
    case "$MODE" in
        install) install_new_cluster ;;
        resume)  resume_installation ;;
    esac
}

main "$@"
