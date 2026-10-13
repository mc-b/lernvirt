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

data_url_text_nl() {
    # Ignition-Dateien mit abschliessendem Newline erzeugen.
    printf 'data:text/plain;charset=utf-8;base64,%s' "$(printf '%s\n' "$1" | base64 -w0)"
}

# IPv4-only Lab: localhost absichtlich nur auf 127.0.0.1 aufloesen. OpenShift
# bindet den Bootstrap-API-Server hier an tcp4; damit vermeiden wir ::1-Zugriffe.
HOSTS_TEXT=$(cat <<EOF_HOSTS
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
::1 localhost6 localhost6.localdomain6
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
HOSTNAME_TEXT="${NODE_HOSTNAME}"
CLUSTER_ENV=$(cat <<EOF_CLUSTER_ENV
CLUSTER_NAME=${CLUSTER_NAME}
BASE_DOMAIN=${BASE_DOMAIN}
SNO_IP=${SNO_IP}
PXE_SERVER=${PXE_SERVER}
EOF_CLUSTER_ENV
)
PROFILE_TEXT=$(cat <<'EOF_PROFILE'
if [ "$(id -u)" -eq 0 ]; then
    if [ -r /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig ]; then
        export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
    elif [ -r /etc/kubernetes/bootstrap-secrets/kubeconfig ]; then
        export KUBECONFIG=/etc/kubernetes/bootstrap-secrets/kubeconfig
    fi
fi
EOF_PROFILE
)
BOOTKUBE_CONSOLE_DROPIN=$(cat <<'EOF_BOOTKUBE_DROPIN'
[Service]
StandardOutput=journal+console
StandardError=journal+console
EOF_BOOTKUBE_DROPIN
)

# Nach dem ersten Disk-Reboot richtet der Node selbst einen kleinen CoreDNS-Dienst
# fuer seine Cluster-Zone ein. Der OpenShift DNS Operator leitet nur diese Zone an
# diesen Dienst weiter. Dadurch funktionieren api/api-int und beliebige *.apps
# intern ohne externen Wildcard-DNS und ohne Aenderung am PXE-Server.
SNO_DNS_SCRIPT=$(cat <<'EOF_SNO_DNS_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[lernvirt-sno-dns] %s\n' "$*"; }

CLUSTER_ENV="${LERNVIRT_CLUSTER_ENV:-/var/lib/lernvirt/cluster.env}"
ADMIN_KUBECONFIG="${LERNVIRT_KUBECONFIG:-/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig}"
OC="${LERNVIRT_OC:-/bin/oc}"

[[ -r "$CLUSTER_ENV" ]] || { log "Fehlt: $CLUSTER_ENV"; exit 1; }
# shellcheck disable=SC1090
source "$CLUSTER_ENV"
: "${CLUSTER_NAME:?CLUSTER_NAME fehlt}"
: "${BASE_DOMAIN:?BASE_DOMAIN fehlt}"
: "${SNO_IP:?SNO_IP fehlt}"

export KUBECONFIG="$ADMIN_KUBECONFIG"

# Der Admin-Kubeconfig wird erst erzeugt, wenn die finale kube-apiserver-Revision
# vorhanden ist. Bis dahin laeuft dieser One-Shot parallel zum Bootstrap weiter.
ready=0
for _ in $(seq 1 360); do
    if [[ -x "$OC" && -r "$ADMIN_KUBECONFIG" ]] && \
       "$OC" get --raw=/readyz >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 10
done
[[ "$ready" == 1 ]] || { log "API/Admin-Kubeconfig nach 60 Minuten nicht bereit."; exit 1; }

ZONE="${CLUSTER_NAME}.${BASE_DOMAIN}"
NAMESPACE=lernvirt-sno-dns
SERVER_NAME=lernvirt-sno

# Exakt das CoreDNS-Image des laufenden OpenShift DNS verwenden. Damit wird kein
# zusaetzliches externes Image oder Binary benoetigt.
DNS_IMAGE=""
for _ in $(seq 1 360); do
    DNS_IMAGE="$("$OC" -n openshift-dns get daemonset dns-default \
        -o jsonpath='{.spec.template.spec.containers[?(@.name=="dns")].image}' 2>/dev/null || true)"
    [[ -n "$DNS_IMAGE" ]] && break
    sleep 10
done
[[ -n "$DNS_IMAGE" ]] || { log "CoreDNS-Image konnte nach 60 Minuten nicht ermittelt werden."; exit 1; }

log "Richte interne Zone ${ZONE} -> ${SNO_IP} ein."
"$OC" apply -f - <<EOF_DNS_OBJECTS
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: ${NAMESPACE}
data:
  Corefile: |
    ${ZONE}:5353 {
        errors
        template IN A {
            answer "{{ .Name }} 30 IN A ${SNO_IP}"
        }
        template IN AAAA {
            rcode NOERROR
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lernvirt-sno-dns
  template:
    metadata:
      labels:
        app: lernvirt-sno-dns
    spec:
      dnsPolicy: Default
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: coredns
        image: ${DNS_IMAGE}
        imagePullPolicy: IfNotPresent
        args:
        - -conf
        - /etc/coredns/Corefile
        ports:
        - name: dns-udp
          containerPort: 5353
          protocol: UDP
        - name: dns-tcp
          containerPort: 5353
          protocol: TCP
        resources:
          requests:
            cpu: 5m
            memory: 16Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: config
          mountPath: /etc/coredns
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: coredns
---
apiVersion: v1
kind: Service
metadata:
  name: coredns
  namespace: ${NAMESPACE}
spec:
  selector:
    app: lernvirt-sno-dns
  ports:
  - name: dns-udp
    port: 5353
    targetPort: 5353
    protocol: UDP
  - name: dns-tcp
    port: 5353
    targetPort: 5353
    protocol: TCP
EOF_DNS_OBJECTS

"$OC" -n "$NAMESPACE" rollout status deployment/coredns --timeout=5m
DNS_SERVICE_IP="$("$OC" -n "$NAMESPACE" get service coredns -o jsonpath='{.spec.clusterIP}')"
[[ -n "$DNS_SERVICE_IP" && "$DNS_SERVICE_IP" != None ]] || { log "DNS Service-IP fehlt."; exit 1; }
UPSTREAM="${DNS_SERVICE_IP}:5353"

# Idempotent und ohne fremde DNS-Server zu ueberschreiben. Ein vorhandener
# lernvirt-Eintrag wird auf die aktuelle Service-IP aktualisiert.
server_index="$("$OC" get dns.operator.openshift.io/default \
    -o go-template='{{range $i, $s := .spec.servers}}{{if eq $s.name "lernvirt-sno"}}{{$i}}{{end}}{{end}}' \
    2>/dev/null || true)"
entry=$(printf '{"name":"%s","zones":["%s"],"forwardPlugin":{"policy":"Sequential","upstreams":["%s"]}}' \
    "$SERVER_NAME" "$ZONE" "$UPSTREAM")

if [[ -n "$server_index" ]]; then
    patch=$(printf '[{"op":"replace","path":"/spec/servers/%s","value":%s}]' "$server_index" "$entry")
else
    first_server="$("$OC" get dns.operator.openshift.io/default \
        -o jsonpath='{.spec.servers[0].name}' 2>/dev/null || true)"
    if [[ -n "$first_server" ]]; then
        patch=$(printf '[{"op":"add","path":"/spec/servers/-","value":%s}]' "$entry")
    else
        patch=$(printf '[{"op":"add","path":"/spec/servers","value":[%s]}]' "$entry")
    fi
fi
"$OC" patch dns.operator.openshift.io/default --type=json -p "$patch"

# Die DNS-DaemonSet-Rollout wird vom DNS Operator ausgeloest. Ein Fehler hier
# beendet die Installation nicht; der Operator reconciliert weiter.
"$OC" -n openshift-dns rollout status daemonset/dns-default --timeout=10m || true
log "Interne OpenShift-Zone aktiv: ${ZONE} -> ${SNO_IP}"
EOF_SNO_DNS_SCRIPT
)
SNO_DNS_UNIT=$(cat <<'EOF_SNO_DNS_UNIT'
[Unit]
Description=lernvirt SNO internal DNS bootstrap
Wants=network-online.target
After=network-online.target kubelet.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lernvirt-openshift-dns
RemainAfterExit=yes
Restart=on-failure
RestartSec=30s
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF_SNO_DNS_UNIT
)

HOSTS_URL="$(data_url_text_nl "$HOSTS_TEXT")"
HOSTNAME_URL="$(data_url_text_nl "$HOSTNAME_TEXT")"
CLUSTER_ENV_URL="$(data_url_text_nl "$CLUSTER_ENV")"
PROFILE_URL="$(data_url_text_nl "$PROFILE_TEXT")"
SNO_DNS_SCRIPT_URL="$(data_url_text_nl "$SNO_DNS_SCRIPT")"

# Erste und zweite Live-Phase verwenden denselben Hostnamen.
if [[ "$DRY_RUN" != "1" ]]; then
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$NODE_HOSTNAME"
    else
        hostname "$NODE_HOSTNAME"
    fi
fi

ensure_local_hosts() {
    local hosts_file="${LERNVIRT_HOSTS_FILE_OVERRIDE:-/etc/hosts}"
    local tmp="${RUN_ROOT}/hosts.tmp"
    printf '%s\n' "$HOSTS_TEXT" > "$tmp"
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

# Persistente Anpassungen ausschliesslich als Day-1 MachineConfig. Das ist der
# vom Installer vorgesehene Weg; keine eigenen Abhaengigkeiten an
# install-to-disk.service oder bootkube.service erzeugen.
log "Erzeuge OpenShift-Manifeste fuer persistente SNO-Anpassungen."
"$INSTALLER" --dir "$WORK" create manifests --log-level=info
mkdir -p "$WORK/openshift"
cat > "$WORK/openshift/99-master-lernvirt-sno.yaml" <<EOF_MC
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-master-lernvirt-sno
  labels:
    machineconfiguration.openshift.io/role: master
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/hostname
        mode: 420
        overwrite: true
        contents:
          source: ${HOSTNAME_URL}
      - path: /etc/hosts
        mode: 420
        overwrite: true
        contents:
          source: ${HOSTS_URL}
      - path: /var/lib/lernvirt/cluster.env
        mode: 384
        overwrite: true
        contents:
          source: ${CLUSTER_ENV_URL}
      - path: /etc/profile.d/lernvirt-openshift.sh
        mode: 420
        overwrite: true
        contents:
          source: ${PROFILE_URL}
      - path: /usr/local/sbin/lernvirt-openshift-dns
        mode: 493
        overwrite: true
        contents:
          source: ${SNO_DNS_SCRIPT_URL}
    systemd:
      units:
      - name: bootkube.service
        dropins:
        - name: 10-lernvirt-console.conf
          contents: |
            [Service]
            StandardOutput=journal+console
            StandardError=journal+console
      - name: lernvirt-openshift-dns.service
        enabled: true
        contents: |
$(printf '%s\n' "$SNO_DNS_UNIT" | sed 's/^/          /')
EOF_MC
chmod 0600 "$WORK/openshift/99-master-lernvirt-sno.yaml"

log "Erzeuge cluster-spezifische SNO Ignition lokal auf dem Zielsystem."
"$INSTALLER" --dir "$WORK" create single-node-ignition-config --log-level=info

BIP="$WORK/bootstrap-in-place-for-live-iso.ign"
[[ -s "$BIP" ]] || fail "bootstrap-in-place-for-live-iso.ign fehlt."

# Die zweite Live-Phase braucht Hostname und /etc/hosts sofort. Wir erweitern
# nur die Live-Ignition und greifen nicht in die BIP-Service-Reihenfolge ein.
PATCHED="$WORK/bootstrap-in-place-for-live-iso-lernvirt.ign"
jq \
  --arg hostname "$HOSTNAME_URL" \
  --arg hosts "$HOSTS_URL" \
  --arg cenv "$CLUSTER_ENV_URL" \
  --arg profile "$PROFILE_URL" \
  --arg console "$BOOTKUBE_CONSOLE_DROPIN" \
  '.storage = (.storage // {}) |
   .storage.files = ([ (.storage.files // [])[] |
      select(.path != "/etc/hostname" and
             .path != "/etc/hosts" and
             .path != "/var/lib/lernvirt/cluster.env" and
             .path != "/etc/profile.d/lernvirt-openshift.sh")
    ] + [
      {"path":"/etc/hostname","mode":420,"overwrite":true,"contents":{"source":$hostname}},
      {"path":"/etc/hosts","mode":420,"overwrite":true,"contents":{"source":$hosts}},
      {"path":"/var/lib/lernvirt/cluster.env","mode":384,"overwrite":true,"contents":{"source":$cenv}},
      {"path":"/etc/profile.d/lernvirt-openshift.sh","mode":420,"overwrite":true,"contents":{"source":$profile}}
    ]) |
   .systemd = (.systemd // {}) |
   .systemd.units = ((.systemd.units // []) |
     map(if .name == "bootkube.service" then
       .dropins = ([ (.dropins // [])[] | select(.name != "10-lernvirt-console.conf") ] +
                   [{"name":"10-lernvirt-console.conf","contents":$console}])
     else . end))' "$BIP" > "$PATCHED"

jq -e '
  .ignition.version and
  any(.storage.files[]?; .path == "/etc/hostname") and
  any(.storage.files[]?; .path == "/etc/hosts") and
  any(.systemd.units[]?; .name == "bootkube.service" and any(.dropins[]?; .name == "10-lernvirt-console.conf"))
' "$PATCHED" >/dev/null || fail "Gepatchte Ignition ist ungueltig."

# Netzwerk des PXE-Live-Systems als statisches NM-Keyfile fuer Bootstrap und
# installiertes RHCOS uebernehmen. coreos-installer pxe customize uebernimmt
# dieses Profil in das cluster-spezifische Live-initramfs.
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
