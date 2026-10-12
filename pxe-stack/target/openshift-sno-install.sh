#!/usr/bin/env bash
set -Eeuo pipefail

log()  { printf '[openshift-sno-target] %s\n' "$*"; }
warn() { printf '[openshift-sno-target] WARNUNG: %s\n' "$*" >&2; }
fail() { printf '[openshift-sno-target] FEHLER: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[openshift-sno-target] FEHLER: Zeile %s: %s (rc=%s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Muss als root laufen."

CMDLINE="${LERNVIRT_CMDLINE_OVERRIDE:-$(cat /proc/cmdline)}"
RUN_ROOT="${LERNVIRT_RUN_ROOT:-/run/lernvirt-openshift-sno}"
DRY_RUN="${LERNVIRT_DRY_RUN:-0}"
mkdir -p "$RUN_ROOT/bin" "$RUN_ROOT/work"
chmod 0700 "$RUN_ROOT" "$RUN_ROOT/work"

karg_value() {
    local key="$1" token
    for token in $CMDLINE; do
        case "$token" in
            "$key"=*) printf '%s\n' "${token#*=}"; return 0 ;;
        esac
    done
    return 1
}

PXE_SERVER="${PXE_SERVER_OVERRIDE:-$(karg_value lernvirt.pxe_server || true)}"
CLUSTER_NAME="${CLUSTER_NAME_OVERRIDE:-$(karg_value lernvirt.variant || true)}"

[[ -n "$PXE_SERVER" ]] || fail "Kernel-Argument lernvirt.pxe_server fehlt."
[[ -n "$CLUSTER_NAME" ]] || fail "rack.conf VARIANT fehlt. Erwartet: MAC|openshift-sno|hf01"
[[ "$CLUSTER_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || fail "Ungueltiger Clustername aus rack.conf: $CLUSTER_NAME"
(( ${#CLUSTER_NAME} <= 54 )) || fail "Clustername ist zu lang: $CLUSTER_NAME"

HTTP_BASE="http://${PXE_SERVER}/openshift-sno"
CONFIG_FILE="$RUN_ROOT/openshift-sno.conf"
PULL_SECRET="$RUN_ROOT/pull-secret.json"
SSH_KEY="$RUN_ROOT/ssh-key.pub"
INSTALLER="$RUN_ROOT/bin/openshift-install"
OC_BIN="$RUN_ROOT/bin/oc"

fetch() {
    local src="$1" dst="$2" mode="${3:-0644}"
    if [[ -n "${LERNVIRT_FIXTURE_ROOT:-}" ]]; then
        local rel="${src#${HTTP_BASE}/}"
        install -m "$mode" "${LERNVIRT_FIXTURE_ROOT}/${rel}" "$dst"
    else
        curl -fL --retry 12 --retry-delay 5 --retry-all-errors "$src" -o "$dst"
        chmod "$mode" "$dst"
    fi
}

log "Cluster: ${CLUSTER_NAME}"
log "PXE:     ${PXE_SERVER}"

fetch "$HTTP_BASE/config/openshift-sno.conf" "$CONFIG_FILE" 0600
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${BASE_DOMAIN:?BASE_DOMAIN fehlt}"
: "${MACHINE_NETWORK_CIDR:?MACHINE_NETWORK_CIDR fehlt}"
: "${CLUSTER_NETWORK_CIDR:?CLUSTER_NETWORK_CIDR fehlt}"
: "${CLUSTER_HOST_PREFIX:?CLUSTER_HOST_PREFIX fehlt}"
: "${SERVICE_NETWORK_CIDR:?SERVICE_NETWORK_CIDR fehlt}"
: "${INSTALL_DISK:?INSTALL_DISK fehlt}"
: "${DNS_SERVER:?DNS_SERVER fehlt}"

fetch "$HTTP_BASE/config/pull-secret.json" "$PULL_SECRET" 0600
fetch "$HTTP_BASE/config/ssh-key.pub" "$SSH_KEY" 0600
fetch "$HTTP_BASE/bin/openshift-install" "$INSTALLER" 0755
fetch "$HTTP_BASE/bin/oc" "$OC_BIN" 0755
export PATH="$RUN_ROOT/bin:$PATH"

jq -e '.auths and (.auths|type=="object")' "$PULL_SECRET" >/dev/null || fail "Pull Secret ist ungueltig."
grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-sha2-|sk-(ssh-ed25519|ecdsa-sha2-))' "$SSH_KEY" || fail "SSH Public Key ist ungueltig."

# Primaere IPv4-Verbindung aus dem Live-System uebernehmen.
IFACE="${LERNVIRT_IFACE_OVERRIDE:-$(ip -4 route show default | awk '$1=="default" {print $5; exit}')}"
[[ -n "$IFACE" ]] || fail "Kein IPv4-Default-Interface gefunden."
CIDR="${LERNVIRT_CIDR_OVERRIDE:-$(ip -o -4 addr show dev "$IFACE" scope global | awk '{print $4; exit}')}"
[[ -n "$CIDR" ]] || fail "Keine globale IPv4-Adresse auf $IFACE gefunden."
SNO_IP="${CIDR%/*}"
PREFIX="${CIDR#*/}"
GATEWAY="${LERNVIRT_GATEWAY_OVERRIDE:-$(ip -4 route show default dev "$IFACE" | awk '$1=="default" {print $3; exit}')}"
[[ -n "$GATEWAY" ]] || fail "Kein IPv4-Gateway auf $IFACE gefunden."
MAC="${LERNVIRT_MAC_OVERRIDE:-$(cat "/sys/class/net/${IFACE}/address")}"
NODE_HOSTNAME="sno-${CLUSTER_NAME}"

if [[ -n "${LERNVIRT_DNS_OVERRIDE:-}" ]]; then
    DNS_SERVER="$LERNVIRT_DNS_OVERRIDE"
elif command -v nmcli >/dev/null 2>&1; then
    detected_dns="$(nmcli -g IP4.DNS device show "$IFACE" 2>/dev/null | awk 'NF {print; exit}' || true)"
    [[ -n "$detected_dns" ]] && DNS_SERVER="$detected_dns"
fi

prefix_to_netmask() {
    local prefix="$1" mask=0 i octet out=""
    [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix >= 0 && prefix <= 32 )) || fail "Ungueltiges IPv4-Prefix: $prefix"
    if (( prefix > 0 )); then
        mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    fi
    for i in 24 16 8 0; do
        octet=$(( (mask >> i) & 255 ))
        out+="${out:+.}${octet}"
    done
    printf '%s' "$out"
}

ipv4_to_int() {
    local a b c d
    IFS=. read -r a b c d <<<"$1"
    [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ && "$d" =~ ^[0-9]+$ ]] || return 1
    (( a<=255 && b<=255 && c<=255 && d<=255 )) || return 1
    printf '%u' $(( (a<<24) | (b<<16) | (c<<8) | d ))
}

ip_in_cidr() {
    local ip="$1" cidr="$2" network prefix ipi neti mask
    network="${cidr%/*}"
    prefix="${cidr#*/}"
    ipi="$(ipv4_to_int "$ip")" || return 1
    neti="$(ipv4_to_int "$network")" || return 1
    [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix>=0 && prefix<=32 )) || return 1
    if (( prefix == 0 )); then mask=0; else mask=$(( (0xFFFFFFFF << (32-prefix)) & 0xFFFFFFFF )); fi
    (( (ipi & mask) == (neti & mask) ))
}

ip_in_cidr "$SNO_IP" "$MACHINE_NETWORK_CIDR" || fail "${SNO_IP} liegt nicht in MACHINE_NETWORK_CIDR=${MACHINE_NETWORK_CIDR}."
NETMASK="$(prefix_to_netmask "$PREFIX")"

log "Netz:    ${IFACE} ${SNO_IP}/${PREFIX}, GW ${GATEWAY}, DNS ${DNS_SERVER}"
log "Node:    ${NODE_HOSTNAME}"
log "Disk:    ${INSTALL_DISK}"

if [[ "$DRY_RUN" != "1" ]]; then
    [[ -b "$INSTALL_DISK" ]] || fail "Installationsdisk existiert nicht: $INSTALL_DISK"
    command -v coreos-installer >/dev/null 2>&1 || fail "coreos-installer fehlt im RHCOS Live-System."
    command -v kexec >/dev/null 2>&1 || fail "kexec fehlt im RHCOS Live-System."
fi

ensure_local_hosts() {
    local hosts_file="${LERNVIRT_HOSTS_FILE_OVERRIDE:-/etc/hosts}"
    local begin="# BEGIN lernvirt-openshift-sno"
    local end="# END lernvirt-openshift-sno"
    local fqdn="${NODE_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    local tmp="${RUN_ROOT}/hosts.tmp"

    [[ -e "$hosts_file" ]] || touch "$hosts_file"

    awk -v begin="$begin" -v end="$end" '
        $0 == begin {skip=1; next}
        $0 == end   {skip=0; next}
        !skip       {print}
    ' "$hosts_file" > "$tmp"

    cat >> "$tmp" <<EOF_HOSTS
$begin
${SNO_IP} ${NODE_HOSTNAME} ${fqdn}
${SNO_IP} api.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} api-int.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} oauth-openshift.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} downloads-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} canary-openshift-ingress-canary.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
$end
EOF_HOSTS

    install -m 0644 "$tmp" "$hosts_file"
    log "Lokale OpenShift-Namen in ${hosts_file} eingetragen."
}
ensure_local_hosts

WORK="$RUN_ROOT/work"
rm -rf "$WORK"
mkdir -p "$WORK"
chmod 0700 "$WORK"
pull_secret="$(jq -c . "$PULL_SECRET")"
ssh_key="$(tr -d '\r\n' < "$SSH_KEY")"
yaml_sq() { printf '%s' "$1" | sed "s/'/''/g"; }

cat > "$WORK/install-config.yaml" <<EOF_INSTALL
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 1
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: ${CLUSTER_NETWORK_CIDR}
    hostPrefix: ${CLUSTER_HOST_PREFIX}
  machineNetwork:
  - cidr: ${MACHINE_NETWORK_CIDR}
  networkType: OVNKubernetes
  serviceNetwork:
  - ${SERVICE_NETWORK_CIDR}
platform:
  none: {}
bootstrapInPlace:
  installationDisk: ${INSTALL_DISK}
pullSecret: '$(yaml_sq "$pull_secret")'
sshKey: '$(yaml_sq "$ssh_key")'
EOF_INSTALL
chmod 0600 "$WORK/install-config.yaml"

log "Erzeuge cluster-spezifische SNO Ignition lokal auf dem Zielsystem."
"$INSTALLER" --dir "$WORK" create single-node-ignition-config --log-level=info

BIP="$WORK/bootstrap-in-place-for-live-iso.ign"
KUBECONFIG_FILE="$WORK/auth/kubeconfig"
KUBEADMIN_FILE="$WORK/auth/kubeadmin-password"
[[ -s "$BIP" ]] || fail "bootstrap-in-place-for-live-iso.ign fehlt."
[[ -s "$KUBECONFIG_FILE" ]] || fail "auth/kubeconfig fehlt."
[[ -s "$KUBEADMIN_FILE" ]] || fail "auth/kubeadmin-password fehlt."

# Die BIP-Logik nimmt die urspruengliche Live-Ignition in die finale Master-
# Ignition auf. Deshalb legen wir lokale Admin-Artefakte und einen kleinen
# Client-Downloader in dieselbe Ignition. Auf dem installierten SNO stehen damit
# /root/.kube/config und /root/kubeadmin-password zur Verfuegung.
data_url_file() {
    printf 'data:text/plain;charset=utf-8;base64,%s' "$(base64 -w0 < "$1")"
}
data_url_text() {
    printf 'data:text/plain;charset=utf-8;base64,%s' "$(printf '%s' "$1" | base64 -w0)"
}

KCFG_URL="$(data_url_file "$KUBECONFIG_FILE")"
KPASS_URL="$(data_url_file "$KUBEADMIN_FILE")"
CLUSTER_ENV=$(cat <<EOF_CLUSTER_ENV
CLUSTER_NAME=${CLUSTER_NAME}
BASE_DOMAIN=${BASE_DOMAIN}
SNO_IP=${SNO_IP}
PXE_SERVER=${PXE_SERVER}
EOF_CLUSTER_ENV
)
CLUSTER_ENV_URL="$(data_url_text "$CLUSTER_ENV")"
PROFILE_TEXT=$(cat <<'EOF_PROFILE'
if [ "$(id -u)" -eq 0 ]; then
    if [ -r /root/.kube/config ]; then
        export KUBECONFIG=/root/.kube/config
    fi
    if [ -d /var/lib/lernvirt/bin ]; then
        export PATH=/var/lib/lernvirt/bin:$PATH
    fi
fi
EOF_PROFILE
)
PROFILE_URL="$(data_url_text "$PROFILE_TEXT")"
FETCH_OC=$(cat <<EOF_FETCH
#!/usr/bin/env bash
set -Eeuo pipefail
install -d -m 0755 /var/lib/lernvirt/bin
if [ ! -x /var/lib/lernvirt/bin/oc ]; then
    curl -fL --retry 30 --retry-delay 10 http://${PXE_SERVER}/openshift-sno/bin/oc -o /var/lib/lernvirt/bin/oc.tmp
    chmod 0755 /var/lib/lernvirt/bin/oc.tmp
    mv -f /var/lib/lernvirt/bin/oc.tmp /var/lib/lernvirt/bin/oc
fi
EOF_FETCH
)
FETCH_OC_URL="$(data_url_text "$FETCH_OC")"
HOSTS_TEXT=$(cat <<EOF_HOSTS
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain localhost6 localhost6.localdomain6
${SNO_IP} ${NODE_HOSTNAME} ${NODE_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} api.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} api-int.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} oauth-openshift.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} downloads-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} canary-openshift-ingress-canary.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
EOF_HOSTS
)
HOSTS_URL="$(data_url_text "$HOSTS_TEXT")"
CLIENT_UNIT=$(cat <<'EOF_UNIT'
[Unit]
Description=lernvirt OpenShift CLI
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lernvirt-fetch-oc
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_UNIT
)

PATCHED="$WORK/bootstrap-in-place-for-live-iso-lernvirt.ign"
jq \
  --arg kcfg "$KCFG_URL" \
  --arg kpass "$KPASS_URL" \
  --arg cenv "$CLUSTER_ENV_URL" \
  --arg profile "$PROFILE_URL" \
  --arg fetchoc "$FETCH_OC_URL" \
  --arg unit "$CLIENT_UNIT" \
  --arg hosts "$HOSTS_URL" \
  '.storage = (.storage // {}) |
   .storage.files = ((.storage.files // []) + [
     {"path":"/etc/hosts","mode":420,"overwrite":true,"contents":{"source":$hosts}},
     {"path":"/root/.kube/config","mode":384,"overwrite":true,"contents":{"source":$kcfg}},
     {"path":"/root/kubeadmin-password","mode":384,"overwrite":true,"contents":{"source":$kpass}},
     {"path":"/var/lib/lernvirt/cluster.env","mode":384,"overwrite":true,"contents":{"source":$cenv}},
     {"path":"/etc/profile.d/lernvirt-openshift.sh","mode":420,"overwrite":true,"contents":{"source":$profile}},
     {"path":"/usr/local/sbin/lernvirt-fetch-oc","mode":493,"overwrite":true,"contents":{"source":$fetchoc}}
   ]) |
   .systemd = (.systemd // {}) |
   .systemd.units = ((.systemd.units // []) + [
     {"name":"lernvirt-openshift-client.service","enabled":true,"contents":$unit}
   ])' "$BIP" > "$PATCHED"
jq -e '.ignition.version and (.storage.files|length > 0)' "$PATCHED" >/dev/null || fail "Gepatchte Ignition ist ungueltig."

# Netzwerk des PXE-Live-Systems als statisches NM-Keyfile fuer Bootstrap und
# installiertes RHCOS uebernehmen. coreos-installer --network-keyfile traegt
# dieses Profil in Live- und Zielsystem ein.
NMFILE="$WORK/openshift-sno.nmconnection"
cat > "$NMFILE" <<EOF_NM
[connection]
id=openshift-sno-${CLUSTER_NAME}
type=ethernet
interface-name=${IFACE}
autoconnect=true

[ethernet]
mac-address=${MAC}

[ipv4]
address1=${SNO_IP}/${PREFIX},${GATEWAY}
dns=${DNS_SERVER};
method=manual
may-fail=false

[ipv6]
method=disabled
EOF_NM
chmod 0600 "$NMFILE"

BASE_INITRD="$RUN_ROOT/rhcos-live-initramfs.img"
KERNEL="$RUN_ROOT/rhcos-live-kernel"
CUSTOM_INITRD="$RUN_ROOT/rhcos-sno-${CLUSTER_NAME}-initramfs.img"
fetch "$HTTP_BASE/rhcos-live-initramfs.img" "$BASE_INITRD" 0644
fetch "$HTTP_BASE/rhcos-live-kernel" "$KERNEL" 0644

if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN: wuerde coreos-installer pxe customize ausfuehren."
    cp "$BASE_INITRD" "$CUSTOM_INITRD"
else
    coreos-installer pxe customize \
        "$BASE_INITRD" \
        --live-ignition "$PATCHED" \
        --network-keyfile "$NMFILE" \
        -o "$CUSTOM_INITRD"
fi
[[ -s "$CUSTOM_INITRD" ]] || fail "Custom initramfs wurde nicht erzeugt."

SECOND_CMDLINE="rd.neednet=1 ignition.firstboot ignition.platform.id=metal coreos.live.rootfs_url=${HTTP_BASE}/rhcos-live-rootfs.img ip=${SNO_IP}::${GATEWAY}:${NETMASK}:${NODE_HOSTNAME}:${IFACE}:none nameserver=${DNS_SERVER} random.trust_cpu=on rd.luks.options=discard"

log "Bootstrap-in-Place ist vorbereitet. Wechsel in cluster-spezifisches RHCOS Live-System."
if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s\n' "$SECOND_CMDLINE" > "$RUN_ROOT/kexec.cmdline"
    log "DRY-RUN abgeschlossen: $RUN_ROOT"
    exit 0
fi

kexec -l "$KERNEL" --initrd="$CUSTOM_INITRD" --command-line="$SECOND_CMDLINE"
sync
log "Starte zweite RHCOS-Phase via kexec. Ab hier bootstrappt und installiert sich ${CLUSTER_NAME} selbst."
sleep 2
if ! systemctl kexec; then
    kexec -e
fi
