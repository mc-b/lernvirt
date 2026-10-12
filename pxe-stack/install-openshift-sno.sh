#!/usr/bin/env bash
set -Eeuo pipefail

# lernvirt PXE Add-on: OpenShift Single Node (SNO)
#
# Erzeugt einen eigenstaendigen Agent-based SNO PXE-Stack. Kein separater
# Bootstrap-Host, kein HAProxy und keine Aenderung an nginx.
#
# Standard fuer dieses Lab:
#   PXE/DNS : 10.31.20.11
#   SNO     : 10.31.20.15
#
# Danach wird der Zielrechner ausschliesslich ueber rack.conf zugeordnet:
#   "AA:BB:CC:DD:EE:FF|openshift-sno|"

log()  { printf '[install-openshift-sno] %s\n' "$*"; }
warn() { printf '[install-openshift-sno] WARNUNG: %s\n' "$*" >&2; }
fail() { printf '[install-openshift-sno] FEHLER: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Muss als root laufen."

RACK_CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
SNO_CONFIG="${SNO_CONFIG:-/srv/tftp/config/openshift-sno.conf}"
[[ -r "$RACK_CONFIG" ]] || fail "PXE-Basis fehlt: $RACK_CONFIG. Zuerst install-pxe.sh ausfuehren."

# shellcheck disable=SC1090
source "$RACK_CONFIG"
RACK_PXE_SERVER="${PXE_SERVER:-}"

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
OCP_FORCE="${OCP_FORCE:-0}"

[[ -x "$TFTP_ROOT/bin/pxe-update" ]] || fail "pxe-update fehlt: $TFTP_ROOT/bin/pxe-update"
[[ -f /etc/dnsmasq.d/pxe.conf ]] || fail "PXE dnsmasq-Konfiguration fehlt: /etc/dnsmasq.d/pxe.conf"

mkdir -p "$TFTP_ROOT/config"
if [[ ! -e "$SNO_CONFIG" ]]; then
    cat >"$SNO_CONFIG" <<EOF_CFG
OCP_CHANNEL="stable-4.20"
CLUSTER_NAME="ocp"
BASE_DOMAIN="lernvirt.test"

PXE_SERVER="10.31.20.11"
SNO_IP="10.31.20.15"
MACHINE_NETWORK_CIDR="10.31.20.0/24"
SNO_HOSTNAME="sno"

SNO_NETWORK_MODE="dhcp"
SNO_DNS="10.31.20.11"

# Fuer statische Agent-Netzwerkkonfiguration setzen:
# SNO_NETWORK_MODE="static"
# SNO_INTERFACE="eno1"
# SNO_MAC="80:EE:73:EF:0D:E9"
# SNO_PREFIX="24"
# SNO_GATEWAY="10.31.20.1"

INSTALL_DISK="${INSTALL_DISK:-/dev/nvme0n1}"
OCP_DIR="/opt/openshift-sno"
PULL_SECRET_FILE="/etc/lernvirt/pull-secret.json"
SSH_KEY_FILE="/etc/lernvirt/lerncloud.pub"
EOF_CFG
    chmod 0600 "$SNO_CONFIG"
    log "Konfiguration erzeugt: $SNO_CONFIG"
fi

# shellcheck disable=SC1090
source "$SNO_CONFIG"

: "${OCP_CHANNEL:?OCP_CHANNEL fehlt}"
: "${CLUSTER_NAME:?CLUSTER_NAME fehlt}"
: "${BASE_DOMAIN:?BASE_DOMAIN fehlt}"
: "${PXE_SERVER:?PXE_SERVER fehlt}"
: "${SNO_IP:?SNO_IP fehlt}"
: "${MACHINE_NETWORK_CIDR:?MACHINE_NETWORK_CIDR fehlt}"
: "${SNO_HOSTNAME:?SNO_HOSTNAME fehlt}"
: "${SNO_NETWORK_MODE:?SNO_NETWORK_MODE fehlt}"
: "${SNO_DNS:?SNO_DNS fehlt}"
: "${INSTALL_DISK:?INSTALL_DISK fehlt}"
: "${OCP_DIR:?OCP_DIR fehlt}"
: "${PULL_SECRET_FILE:?PULL_SECRET_FILE fehlt}"
: "${SSH_KEY_FILE:?SSH_KEY_FILE fehlt}"

if [[ -n "$RACK_PXE_SERVER" && "$PXE_SERVER" != "$RACK_PXE_SERVER" ]]; then
    fail "PXE_SERVER in openshift-sno.conf (${PXE_SERVER}) stimmt nicht mit rack.conf (${RACK_PXE_SERVER}) ueberein."
fi
if [[ "${PXE_SERVER}" != "10.31.20.11" ]]; then
    warn "PXE_SERVER ist ${PXE_SERVER}; fuer dieses Lab wurde 10.31.20.11 angegeben."
fi
if [[ "${SNO_IP}" != "10.31.20.15" ]]; then
    warn "SNO_IP ist ${SNO_IP}; fuer dieses Lab wurde 10.31.20.15 angegeben."
fi

case "$SNO_NETWORK_MODE" in
    dhcp|static) ;;
    *) fail "SNO_NETWORK_MODE muss dhcp oder static sein." ;;
esac

# Falls rack.conf bereits genau einen Host auf openshift-sno zeigt, kann dessen
# MAC fuer Host-Matching/rootDeviceHints verwendet werden. rack.conf bleibt
# trotzdem die zentrale PXE-Zuordnung und wird hier nie automatisch veraendert.
discover_sno_mac() {
    [[ -n "${SNO_MAC:-}" ]] && return 0
    declare -p HOSTS >/dev/null 2>&1 || return 0

    local rule selector stack variant found=""
    for rule in "${HOSTS[@]}"; do
        IFS='|' read -r selector stack variant <<<"$rule"
        selector="${selector//[[:space:]]/}"
        stack="${stack//[[:space:]]/}"
        [[ "$stack" == "openshift-sno" && "$selector" != "*" ]] || continue
        if [[ -n "$found" && "${selector,,}" != "${found,,}" ]]; then
            warn "Mehrere openshift-sno Hosts in rack.conf; SNO_MAC wird nicht automatisch gewaehlt."
            return 0
        fi
        found="$selector"
    done
    [[ -n "$found" ]] && SNO_MAC="$found"
}
discover_sno_mac

if [[ -n "${SNO_MAC:-}" && ! "${SNO_MAC,,}" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
    fail "Ungueltige SNO_MAC: $SNO_MAC"
fi

if [[ "$SNO_NETWORK_MODE" == "static" ]]; then
    : "${SNO_MAC:?SNO_MAC ist fuer static erforderlich}"
    : "${SNO_INTERFACE:?SNO_INTERFACE ist fuer static erforderlich}"
    : "${SNO_PREFIX:?SNO_PREFIX ist fuer static erforderlich}"
    : "${SNO_GATEWAY:?SNO_GATEWAY ist fuer static erforderlich}"
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

if [[ "$SNO_NETWORK_MODE" == "static" ]]; then
    SNO_NETMASK="$(prefix_to_netmask "$SNO_PREFIX")"
    BOOT_NET_ARGS="ip=${SNO_IP}::${SNO_GATEWAY}:${SNO_NETMASK}:${SNO_HOSTNAME}:${SNO_INTERFACE}:none nameserver=${SNO_DNS} rd.neednet=1 ai.ip_cfg_override=1"
else
    BOOT_NET_ARGS="ip=dhcp rd.neednet=1 nameserver=${SNO_DNS}"
fi

export DEBIAN_FRONTEND=noninteractive
missing=()
for cmd_pkg in \
    "curl:curl" \
    "jq:jq" \
    "tar:tar" \
    "sha256sum:coreutils" \
    "dig:dnsutils" \
    "dnsmasq:dnsmasq"; do
    cmd="${cmd_pkg%%:*}"
    pkg="${cmd_pkg##*:}"
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
    apt-get update -y
    apt-get install -y ca-certificates "${missing[@]}"
fi

BIN="$OCP_DIR/bin"
INSTALL_DIR="$OCP_DIR/install"
CONFIG_BACKUP="$OCP_DIR/config"
CACHE_DIR="${PXE_CACHE_DIR:-/var/cache/pxe-stack}/openshift-sno"
TFTP_SNO="$TFTP_ROOT/linux/openshift-sno"
HTTP_SNO="$HTTP_ROOT/openshift-sno"
STACK_FILE="$TFTP_ROOT/grub/stacks/openshift-sno.cfg"
WAIT_TOOL="$TFTP_ROOT/bin/openshift-sno-wait"

install -d -m 0755 "$BIN" "$CACHE_DIR" "$TFTP_SNO" "$HTTP_SNO" "$TFTP_ROOT/grub/stacks" "$TFTP_ROOT/bin"
install -d -m 0700 "$OCP_DIR" "$CONFIG_BACKUP"

[[ -r "$PULL_SECRET_FILE" ]] || fail "Pull Secret fehlt: $PULL_SECRET_FILE"
[[ -r "$SSH_KEY_FILE" ]] || fail "SSH Public Key fehlt: $SSH_KEY_FILE"
jq -e '.auths and (.auths|type=="object")' "$PULL_SECRET_FILE" >/dev/null || fail "Pull Secret ist kein gueltiges Docker auth JSON: $PULL_SECRET_FILE"
grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-sha2-|sk-(ssh-ed25519|ecdsa-sha2-))' "$SSH_KEY_FILE" || fail "Ungueltiger SSH Public Key: $SSH_KEY_FILE"

CLIENT_BASE="${OCP_CLIENT_BASE:-https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_CHANNEL}}"
INSTALLER_URL="${OPENSHIFT_INSTALL_URL:-${CLIENT_BASE}/openshift-install-linux.tar.gz}"
OC_URL="${OC_URL:-${CLIENT_BASE}/openshift-client-linux.tar.gz}"

# Download mit Cache, damit ein erneuter Lauf nicht wieder grosse Archive zieht.
download_file() {
    local url="$1" dst="$2" part="${2}.part"
    if [[ -s "$dst" && "$OCP_FORCE" != "1" ]]; then
        return 0
    fi
    [[ "$OCP_FORCE" == "1" ]] && rm -f "$dst" "$part"
    log "Download: $url"
    curl -fL --retry 8 --retry-delay 4 --retry-all-errors --continue-at - "$url" -o "$part"
    [[ -s "$part" ]] || fail "Leerer Download: $url"
    mv -f "$part" "$dst"
}

install_clients() {
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    download_file "$INSTALLER_URL" "$CACHE_DIR/openshift-install-linux.tar.gz"
    download_file "$OC_URL" "$CACHE_DIR/openshift-client-linux.tar.gz"

    tar -xzf "$CACHE_DIR/openshift-install-linux.tar.gz" -C "$tmp"
    tar -xzf "$CACHE_DIR/openshift-client-linux.tar.gz" -C "$tmp"
    [[ -x "$tmp/openshift-install" ]] || fail "openshift-install fehlt im Archiv."
    [[ -x "$tmp/oc" ]] || fail "oc fehlt im Archiv."

    install -m 0755 "$tmp/openshift-install" "$BIN/openshift-install"
    install -m 0755 "$tmp/oc" "$BIN/oc"
    [[ -x "$tmp/kubectl" ]] && install -m 0755 "$tmp/kubectl" "$BIN/kubectl" || true
    rm -rf "$tmp"
    trap - RETURN
}
install_clients

log "Verwende $("$BIN/openshift-install" version | head -n1)"

reverse_ipv4() {
    local ip="$1" a b c d
    IFS=. read -r a b c d <<<"$ip"
    printf '%s.%s.%s.%s.in-addr.arpa' "$d" "$c" "$b" "$a"
}

configure_dns() {
    log "DNS fuer SNO konfigurieren"

    if grep -Eq '^[[:space:]]*port[[:space:]]*=[[:space:]]*0[[:space:]]*$' /etc/dnsmasq.d/pxe.conf; then
        sed -i -E 's/^[[:space:]]*port[[:space:]]*=[[:space:]]*0[[:space:]]*$/port=53/' /etc/dnsmasq.d/pxe.conf
    elif ! grep -Eq '^[[:space:]]*port[[:space:]]*=[[:space:]]*53[[:space:]]*$' /etc/dnsmasq.d/pxe.conf; then
        fail "Unerwartete port=-Einstellung in /etc/dnsmasq.d/pxe.conf"
    fi

    # Gleiche Cluster-Domain darf nicht gleichzeitig von einem anderen
    # OpenShift-dnsmasq-Fragment auf eine andere Umgebung zeigen.
    local f
    for f in /etc/dnsmasq.d/*.conf; do
        [[ -e "$f" ]] || continue
        [[ "$f" == "/etc/dnsmasq.d/zz-openshift-sno.conf" ]] && continue
        if grep -Fq "api.${CLUSTER_NAME}.${BASE_DOMAIN}" "$f" 2>/dev/null; then
            fail "DNS-Konflikt: ${f} enthaelt bereits api.${CLUSTER_NAME}.${BASE_DOMAIN}. Cluster-Namen aendern oder alte OpenShift-DNS-Datei entfernen."
        fi
    done

    local resolver_file=/run/systemd/resolve/resolv.conf
    [[ -r "$resolver_file" ]] || resolver_file=/etc/resolv.conf

    cat >/etc/dnsmasq.d/zz-openshift-sno.conf <<EOF_DNS
# lernvirt OpenShift SNO DNS Add-on. nginx bleibt unveraendert.
listen-address=${PXE_SERVER}
resolv-file=${resolver_file}

host-record=api.${CLUSTER_NAME}.${BASE_DOMAIN},${SNO_IP}
host-record=api-int.${CLUSTER_NAME}.${BASE_DOMAIN},${SNO_IP}
host-record=${SNO_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN},${SNO_IP}
address=/.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/${SNO_IP}
ptr-record=$(reverse_ipv4 "$SNO_IP"),${SNO_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}
EOF_DNS

    if [[ -x /usr/share/dnsmasq/systemd-helper ]]; then
        /usr/share/dnsmasq/systemd-helper checkconfig
    else
        dnsmasq --test
    fi
    systemctl restart dnsmasq

    dig +short @"$PXE_SERVER" "api.${CLUSTER_NAME}.${BASE_DOMAIN}" | grep -qx "$SNO_IP" || fail "DNS api fehlgeschlagen"
    dig +short @"$PXE_SERVER" "test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}" | grep -qx "$SNO_IP" || fail "DNS *.apps fehlgeschlagen"
}
configure_dns

configure_local_hosts() {
    sed -i '/^# BEGIN LERNVIRT OPENSHIFT SNO$/,/^# END LERNVIRT OPENSHIFT SNO$/d' /etc/hosts
    cat >>/etc/hosts <<EOF_HOSTS
# BEGIN LERNVIRT OPENSHIFT SNO
${SNO_IP} api.${CLUSTER_NAME}.${BASE_DOMAIN} api-int.${CLUSTER_NAME}.${BASE_DOMAIN}
${SNO_IP} ${SNO_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${SNO_HOSTNAME}
${SNO_IP} console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN} oauth-openshift.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
# END LERNVIRT OPENSHIFT SNO
EOF_HOSTS
}
configure_local_hosts

# Die beiden YAMLs werden zuerst ausserhalb des Installationsverzeichnisses
# erzeugt, damit ein Konfigurationswechsel sicher erkannt wird. Der Installer
# darf install-config.yaml anschliessend konsumieren.
TMP_CFG="$(mktemp -d)"
trap 'rm -rf "$TMP_CFG"' EXIT

pull_secret="$(jq -c . "$PULL_SECRET_FILE")"
ssh_key="$(tr -d '\r\n' < "$SSH_KEY_FILE")"
yaml_sq() { printf '%s' "$1" | sed "s/'/''/g"; }

cat >"$TMP_CFG/install-config.yaml" <<EOF_INSTALL
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 1
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: ${MACHINE_NETWORK_CIDR}
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
fips: false
pullSecret: '$(yaml_sq "$pull_secret")'
sshKey: '$(yaml_sq "$ssh_key")'
EOF_INSTALL

cat >"$TMP_CFG/agent-config.yaml" <<EOF_AGENT
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: ${CLUSTER_NAME}
rendezvousIP: ${SNO_IP}
bootArtifactsBaseURL: http://${PXE_SERVER}/openshift-sno
EOF_AGENT

# Optionaler Hostblock: noetig fuer statische Netzwerkkonfiguration und
# nuetzlich fuer einen expliziten rootDeviceHint.
if [[ -n "${SNO_MAC:-}" ]]; then
    SNO_INTERFACE="${SNO_INTERFACE:-eno1}"
    cat >>"$TMP_CFG/agent-config.yaml" <<EOF_HOST
hosts:
- hostname: ${SNO_HOSTNAME}
  interfaces:
  - name: ${SNO_INTERFACE}
    macAddress: ${SNO_MAC}
  rootDeviceHints:
    deviceName: ${INSTALL_DISK}
EOF_HOST

    if [[ "$SNO_NETWORK_MODE" == "static" ]]; then
        cat >>"$TMP_CFG/agent-config.yaml" <<EOF_STATIC
  networkConfig:
    interfaces:
    - name: ${SNO_INTERFACE}
      type: ethernet
      state: up
      mac-address: ${SNO_MAC}
      ipv4:
        enabled: true
        address:
        - ip: ${SNO_IP}
          prefix-length: ${SNO_PREFIX}
        dhcp: false
      ipv6:
        enabled: false
    dns-resolver:
      config:
        server:
        - ${SNO_DNS}
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: ${SNO_GATEWAY}
        next-hop-interface: ${SNO_INTERFACE}
        table-id: 254
EOF_STATIC
    fi
elif [[ "$SNO_NETWORK_MODE" == "static" ]]; then
    fail "Static networking benoetigt SNO_MAC."
fi

CONFIG_SHA="$(cat "$TMP_CFG/install-config.yaml" "$TMP_CFG/agent-config.yaml" | sha256sum | awk '{print $1}')"
OLD_SHA="$(cat "$OCP_DIR/.config.sha256" 2>/dev/null || true)"

assets_complete() {
    [[ -s "$INSTALL_DIR/boot-artifacts/agent.x86_64-vmlinuz" ]] &&
    [[ -s "$INSTALL_DIR/boot-artifacts/agent.x86_64-initrd.img" ]] &&
    [[ -s "$INSTALL_DIR/boot-artifacts/agent.x86_64-rootfs.img" ]] &&
    [[ -s "$INSTALL_DIR/auth/kubeconfig" ]]
}

if assets_complete && [[ "$CONFIG_SHA" == "$OLD_SHA" && "$OCP_FORCE" != "1" ]]; then
    log "Agent-PXE-Artefakte sind bereits passend erzeugt."
elif [[ -d "$INSTALL_DIR" && -n "$OLD_SHA" && "$CONFIG_SHA" != "$OLD_SHA" && "$OCP_FORCE" != "1" ]]; then
    fail "SNO-Konfiguration wurde geaendert. OCP_FORCE=1 verwenden, wenn der bestehende Cluster/PKI wirklich neu erzeugt werden soll."
else
    log "Agent-based SNO PXE-Artefakte erzeugen"
    rm -rf "$INSTALL_DIR"
    install -d -m 0700 "$INSTALL_DIR"
    install -m 0600 "$TMP_CFG/install-config.yaml" "$INSTALL_DIR/install-config.yaml"
    install -m 0600 "$TMP_CFG/agent-config.yaml" "$INSTALL_DIR/agent-config.yaml"

    install -m 0600 "$TMP_CFG/install-config.yaml" "$CONFIG_BACKUP/install-config.yaml"
    install -m 0600 "$TMP_CFG/agent-config.yaml" "$CONFIG_BACKUP/agent-config.yaml"

    "$BIN/openshift-install" --dir "$INSTALL_DIR" agent create pxe-files --log-level=info
    assets_complete || fail "openshift-install hat keine vollstaendigen PXE-Artefakte erzeugt."
    printf '%s\n' "$CONFIG_SHA" >"$OCP_DIR/.config.sha256"
    chmod 0600 "$OCP_DIR/.config.sha256"
fi

log "PXE-Artefakte installieren"
for f in agent.x86_64-vmlinuz agent.x86_64-initrd.img; do
    install -m 0644 "$INSTALL_DIR/boot-artifacts/$f" "$TFTP_SNO/$f"
    install -m 0644 "$INSTALL_DIR/boot-artifacts/$f" "$HTTP_SNO/$f"
done
install -m 0644 "$INSTALL_DIR/boot-artifacts/agent.x86_64-rootfs.img" "$HTTP_SNO/agent.x86_64-rootfs.img"
[[ -s "$INSTALL_DIR/boot-artifacts/agent.x86_64.ipxe" ]] && \
    install -m 0644 "$INSTALL_DIR/boot-artifacts/agent.x86_64.ipxe" "$HTTP_SNO/agent.x86_64.ipxe" || true

# Eigener Stack: nach erfolgreicher Installation wird ein vorhandener RHCOS
# EFI-Bootloader erkannt und direkt gebootet. Damit wird beim naechsten PXE-Boot
# nicht erneut installiert, ohne die globale grub.cfg veraendern zu muessen.
cat >"$STACK_FILE" <<EOF_GRUB
set sno_efi=""
if search --no-floppy --file --set=sno_efi /EFI/redhat/shimx64.efi; then
    set default="openshift-sno-local"
fi

if [ -n "\${sno_efi}" ]; then
    menuentry "Local OpenShift SNO" --id openshift-sno-local {
        insmod chain
        set root="\${sno_efi}"
        chainloader /EFI/redhat/shimx64.efi
        boot
    }
fi

menuentry "Install OpenShift SNO" --id openshift-sno-install {
    linux /linux/openshift-sno/agent.x86_64-vmlinuz \\
        ${BOOT_NET_ARGS} \\
        coreos.live.rootfs_url=http://\${pxe_server}/openshift-sno/agent.x86_64-rootfs.img \\
        random.trust_cpu=on \\
        rd.luks.options=discard \\
        ignition.firstboot \\
        ignition.platform.id=metal
    initrd /linux/openshift-sno/agent.x86_64-initrd.img
}
EOF_GRUB
chmod 0644 "$STACK_FILE"

# Kleines Betriebswerkzeug direkt in die laufende PXE-Umgebung schreiben.
cat >"$WAIT_TOOL" <<'EOF_WAIT'
#!/usr/bin/env bash
set -Eeuo pipefail
fail() { echo "[openshift-sno-wait] FEHLER: $*" >&2; exit 1; }
RACK_CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
SNO_CONFIG="${SNO_CONFIG:-/srv/tftp/config/openshift-sno.conf}"
[[ -r "$RACK_CONFIG" ]] || fail "Fehlt: $RACK_CONFIG"
[[ -r "$SNO_CONFIG" ]] || fail "Fehlt: $SNO_CONFIG"
# shellcheck disable=SC1090
source "$RACK_CONFIG"
# shellcheck disable=SC1090
source "$SNO_CONFIG"
OCP_DIR="${OCP_DIR:-/opt/openshift-sno}"
BIN="$OCP_DIR/bin"
INSTALL_DIR="$OCP_DIR/install"
case "${1:-install}" in
  bootstrap) exec "$BIN/openshift-install" --dir "$INSTALL_DIR" agent wait-for bootstrap-complete --log-level=info ;;
  install)   exec "$BIN/openshift-install" --dir "$INSTALL_DIR" agent wait-for install-complete --log-level=info ;;
  status)
    echo "Cluster : ${CLUSTER_NAME}.${BASE_DOMAIN}"
    echo "SNO     : ${SNO_IP}"
    echo "API     : https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
    echo "Console : https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
    echo
    if [[ -r "$INSTALL_DIR/auth/kubeconfig" && -x "$BIN/oc" ]]; then
      export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
      "$BIN/oc" get nodes -o wide || true
      echo
      "$BIN/oc" get co || true
    else
      echo "Kubeconfig noch nicht verfuegbar: $INSTALL_DIR/auth/kubeconfig"
    fi
    ;;
  *) fail "Aufruf: $0 [bootstrap|install|status]" ;;
esac
EOF_WAIT
chmod 0755 "$WAIT_TOOL"

# nginx wird bewusst nicht veraendert.
if command -v nginx >/dev/null 2>&1; then
    nginx -t || fail "Bestehende nginx-Konfiguration ist ungueltig."
fi

"$TFTP_ROOT/bin/pxe-update"

# HTTP nur pruefen, nicht konfigurieren.
curl -fsI --connect-timeout 5 "http://${PXE_SERVER}/openshift-sno/agent.x86_64-rootfs.img" >/dev/null || \
    fail "rootfs ist ueber den bestehenden nginx nicht erreichbar."

log "OpenShift SNO Stack ist bereit."
echo "  Stack      : openshift-sno"
echo "  PXE/DNS    : ${PXE_SERVER}"
echo "  SNO        : ${SNO_IP}"
echo "  API        : api.${CLUSTER_NAME}.${BASE_DOMAIN} -> ${SNO_IP}"
echo "  Apps       : *.apps.${CLUSTER_NAME}.${BASE_DOMAIN} -> ${SNO_IP}"
echo "  Kubeconfig : ${INSTALL_DIR}/auth/kubeconfig"
echo "  Console    : https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
echo
echo "rack.conf:"
echo '  "AA:BB:CC:DD:EE:FF|openshift-sno|"'
echo "Danach: sudo ${TFTP_ROOT}/bin/pxe-update"
echo
echo "Installation beobachten:"
echo "  sudo ${WAIT_TOOL} install"
if [[ "$SNO_NETWORK_MODE" == "dhcp" ]]; then
    echo
    echo "DHCP-Hinweis: ${SNO_IP} muss dem Zielrechner zugeteilt werden."
    echo "Fuer den installierten Cluster muss ${SNO_DNS} (oder ein gleichwertiger DNS) die OpenShift-Zonen aufloesen."
fi
