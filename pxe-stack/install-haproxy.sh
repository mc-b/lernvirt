#!/usr/bin/env bash
set -Eeuo pipefail

log()  { echo "[install-haproxy] $*"; }
warn() { echo "[install-haproxy] WARNUNG: $*" >&2; }
fail() { echo "[install-haproxy] FEHLER: $*" >&2; exit 1; }

MODE="${1:-bootstrap}"
case "$MODE" in
    bootstrap|final) ;;
    *) fail "Verwendung: $0 [bootstrap|final]" ;;
esac

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "install-haproxy.sh muss als root laufen."

OCP_CONFIG="${OCP_CONFIG:-/srv/tftp/config/openshift.conf}"
HAPROXY_CONFIG="${HAPROXY_CONFIG:-/etc/haproxy/haproxy.cfg}"
INGRESS_HAPROXY_CONFIG="${INGRESS_HAPROXY_CONFIG:-/etc/haproxy/openshift-ingress.cfg}"
INGRESS_NETNS="${INGRESS_NETNS:-ocp-ingress}"
INGRESS_NET_SERVICE="openshift-ingress-net.service"
INGRESS_HAPROXY_SERVICE="openshift-ingress-haproxy.service"
INGRESS_NET_SCRIPT="/usr/local/sbin/openshift-ingress-net"

[[ -r "$OCP_CONFIG" ]] || fail "OpenShift-Konfiguration fehlt: $OCP_CONFIG"
# shellcheck disable=SC1090
source "$OCP_CONFIG"

: "${TERRA1_IP:?TERRA1_IP fehlt in $OCP_CONFIG}"
: "${TERRA2_IP:?TERRA2_IP fehlt in $OCP_CONFIG}"
: "${TERRA3_IP:?TERRA3_IP fehlt in $OCP_CONFIG}"
: "${TERRA4_IP:?TERRA4_IP fehlt in $OCP_CONFIG}"
: "${BOOTSTRAP_IP:?BOOTSTRAP_IP fehlt in $OCP_CONFIG}"
: "${BOOTSTRAP_PREFIX:?BOOTSTRAP_PREFIX fehlt in $OCP_CONFIG}"
: "${BOOTSTRAP_BRIDGE:?BOOTSTRAP_BRIDGE fehlt in $OCP_CONFIG}"
: "${BOOTSTRAP_MAC:?BOOTSTRAP_MAC fehlt in $OCP_CONFIG}"

INGRESS_IP="${INGRESS_IP:-$BOOTSTRAP_IP}"
INGRESS_PREFIX="${INGRESS_PREFIX:-$BOOTSTRAP_PREFIX}"
INGRESS_BRIDGE="${INGRESS_BRIDGE:-$BOOTSTRAP_BRIDGE}"
INGRESS_MAC="${INGRESS_MAC:-$BOOTSTRAP_MAC}"
INGRESS_GATEWAY="${INGRESS_GATEWAY:-}"
if [[ -z "$INGRESS_GATEWAY" ]]; then
    INGRESS_GATEWAY="$(ip -4 route show default dev "$INGRESS_BRIDGE" 2>/dev/null | awk 'NR==1 {print $3}')"
fi
[[ -n "$INGRESS_GATEWAY" ]] || fail "Kein Default-Gateway über $INGRESS_BRIDGE gefunden."
ip link show "$INGRESS_BRIDGE" >/dev/null 2>&1 || fail "Bridge fehlt: $INGRESS_BRIDGE"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y haproxy iproute2 iputils-ping iputils-arping

write_api_config() {
    local include_bootstrap="$1"
    mkdir -p "$(dirname "$HAPROXY_CONFIG")"
    cp -a "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

    cat >"$HAPROXY_CONFIG" <<EOF_CFG
global
    log /dev/log local0
    daemon
    maxconn 4000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 10s
    timeout client  5m
    timeout server  5m

frontend ocp_api
    bind ${TERRA1_IP}:6443
    default_backend ocp_api_backend

backend ocp_api_backend
    mode tcp
    option httpchk GET /readyz HTTP/1.0
    balance roundrobin
EOF_CFG

    if [[ "$include_bootstrap" == "1" ]]; then
        echo "    server bootstrap ${BOOTSTRAP_IP}:6443 check check-ssl verify none inter 5s rise 2 fall 3" >>"$HAPROXY_CONFIG"
    fi
    cat >>"$HAPROXY_CONFIG" <<EOF_CFG
    server terra2 ${TERRA2_IP}:6443 check check-ssl verify none inter 5s rise 2 fall 3
    server terra3 ${TERRA3_IP}:6443 check check-ssl verify none inter 5s rise 2 fall 3
    server terra4 ${TERRA4_IP}:6443 check check-ssl verify none inter 5s rise 2 fall 3

frontend ocp_mcs
    bind ${TERRA1_IP}:22623
    default_backend ocp_mcs_backend

backend ocp_mcs_backend
    mode tcp
    balance roundrobin
EOF_CFG
    if [[ "$include_bootstrap" == "1" ]]; then
        echo "    server bootstrap ${BOOTSTRAP_IP}:22623 check inter 2s rise 2 fall 3" >>"$HAPROXY_CONFIG"
    fi
    cat >>"$HAPROXY_CONFIG" <<EOF_CFG
    server terra2 ${TERRA2_IP}:22623 check inter 2s rise 2 fall 3
    server terra3 ${TERRA3_IP}:22623 check inter 2s rise 2 fall 3
    server terra4 ${TERRA4_IP}:22623 check inter 2s rise 2 fall 3
EOF_CFG

    haproxy -c -f "$HAPROXY_CONFIG"
    systemctl enable --now haproxy >/dev/null
    systemctl restart haproxy
    log "API/MCS HAProxy aktiv auf ${TERRA1_IP}:6443 und :22623 (bootstrap=${include_bootstrap})."
}

write_ingress_network_script() {
    cat >"$INGRESS_NET_SCRIPT" <<EOF_NET
#!/usr/bin/env bash
set -Eeuo pipefail
ACTION="\${1:-up}"
NETNS="$INGRESS_NETNS"
HOST_VETH="ocp-ing-host"
NS_VETH="ocp-ing-ns"
BRIDGE="$INGRESS_BRIDGE"
IP_CIDR="$INGRESS_IP/$INGRESS_PREFIX"
GATEWAY="$INGRESS_GATEWAY"
MAC="$INGRESS_MAC"

up() {
    ip link show "\$BRIDGE" >/dev/null 2>&1
    ip netns list | awk '{print \$1}' | grep -qx "\$NETNS" || ip netns add "\$NETNS"
    if ! ip link show "\$HOST_VETH" >/dev/null 2>&1; then
        ip link add "\$HOST_VETH" type veth peer name "\$NS_VETH"
        ip link set "\$NS_VETH" netns "\$NETNS"
    fi
    ip link set "\$HOST_VETH" master "\$BRIDGE"
    ip link set "\$HOST_VETH" up
    ip -n "\$NETNS" link set lo up
    ip -n "\$NETNS" link set "\$NS_VETH" name eth0 2>/dev/null || true
    ip -n "\$NETNS" link set eth0 address "\$MAC"
    ip -n "\$NETNS" addr flush dev eth0
    ip -n "\$NETNS" addr add "\$IP_CIDR" dev eth0
    ip -n "\$NETNS" link set eth0 up
    ip -n "\$NETNS" route replace default via "\$GATEWAY"
    ip netns exec "\$NETNS" arping -U -c 3 -I eth0 "${INGRESS_IP}" >/dev/null 2>&1 || true
}

down() {
    ip link del "\$HOST_VETH" 2>/dev/null || true
    ip netns del "\$NETNS" 2>/dev/null || true
}

case "\$ACTION" in
    up) up ;;
    down) down ;;
    *) echo "Verwendung: \$0 [up|down]" >&2; exit 2 ;;
esac
EOF_NET
    chmod 0755 "$INGRESS_NET_SCRIPT"
}

write_ingress_units() {
    cat >/etc/systemd/system/${INGRESS_NET_SERVICE} <<EOF_UNIT
[Unit]
Description=OpenShift Ingress network namespace
After=network-online.target
Wants=network-online.target
Before=${INGRESS_HAPROXY_SERVICE}

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${INGRESS_NET_SCRIPT} up
ExecStop=${INGRESS_NET_SCRIPT} down

[Install]
WantedBy=multi-user.target
EOF_UNIT

    cat >/etc/systemd/system/${INGRESS_HAPROXY_SERVICE} <<EOF_UNIT
[Unit]
Description=OpenShift Ingress HAProxy in network namespace
Requires=${INGRESS_NET_SERVICE}
After=${INGRESS_NET_SERVICE}

[Service]
Type=simple
ExecStart=/usr/sbin/ip netns exec ${INGRESS_NETNS} /usr/sbin/haproxy -db -f ${INGRESS_HAPROXY_CONFIG}
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF_UNIT
}

write_ingress_config() {
    cat >"$INGRESS_HAPROXY_CONFIG" <<EOF_CFG
global
    log stdout format raw local0
    maxconn 4000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 10s
    timeout client  5m
    timeout server  5m

frontend ocp_http
    bind ${INGRESS_IP}:80
    default_backend ocp_http_backend

backend ocp_http_backend
    mode tcp
    balance source
    server terra2 ${TERRA2_IP}:80 check inter 2s rise 2 fall 3
    server terra3 ${TERRA3_IP}:80 check inter 2s rise 2 fall 3
    server terra4 ${TERRA4_IP}:80 check inter 2s rise 2 fall 3

frontend ocp_https
    bind ${INGRESS_IP}:443
    default_backend ocp_https_backend

backend ocp_https_backend
    mode tcp
    balance source
    server terra2 ${TERRA2_IP}:443 check inter 2s rise 2 fall 3
    server terra3 ${TERRA3_IP}:443 check inter 2s rise 2 fall 3
    server terra4 ${TERRA4_IP}:443 check inter 2s rise 2 fall 3
EOF_CFG
    haproxy -c -f "$INGRESS_HAPROXY_CONFIG"
}

start_ingress() {
    # Eine bereits von diesem Script erzeugte Namespace-Instanz zuerst sauber
    # entfernen. Dadurch bleibt "final" wiederholbar.
    systemctl stop "$INGRESS_HAPROXY_SERVICE" "$INGRESS_NET_SERVICE" >/dev/null 2>&1 || true
    if [[ -x "$INGRESS_NET_SCRIPT" ]]; then
        "$INGRESS_NET_SCRIPT" down >/dev/null 2>&1 || true
    else
        ip link del ocp-ing-host >/dev/null 2>&1 || true
        ip netns del "$INGRESS_NETNS" >/dev/null 2>&1 || true
    fi

    # Die Ingress-IP ist standardmässig die nach bootstrap-complete frei gewordene
    # Bootstrap-IP. Sie darf hier nicht mehr von der Bootstrap-VM benutzt werden.
    if ping -c1 -W1 "$INGRESS_IP" >/dev/null 2>&1; then
        fail "Ingress-IP ${INGRESS_IP} antwortet bereits. Bootstrap-VM zuerst entfernen oder INGRESS_IP ändern."
    fi

    write_ingress_network_script
    write_ingress_config
    write_ingress_units
    systemctl daemon-reload
    systemctl enable "$INGRESS_NET_SERVICE" "$INGRESS_HAPROXY_SERVICE" >/dev/null
    systemctl restart "$INGRESS_NET_SERVICE"
    systemctl restart "$INGRESS_HAPROXY_SERVICE"

    ip netns exec "$INGRESS_NETNS" ss -lnt | grep -Eq ':(80|443)[[:space:]]' \
        || fail "Ingress HAProxy lauscht nicht auf 80/443 im Namespace."
    log "Ingress HAProxy aktiv auf ${INGRESS_IP}:80 und :443; nginx auf terra1 bleibt unverändert."
}

case "$MODE" in
    bootstrap)
        write_api_config 1
        log "Ingress 80/443 wird erst nach bootstrap-complete mit '$0 final' aktiviert."
        ;;
    final)
        write_api_config 0
        start_ingress
        ;;
esac
