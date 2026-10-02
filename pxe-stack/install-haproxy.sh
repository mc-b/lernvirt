#!/usr/bin/env bash
set -Eeuo pipefail

OCP_CONFIG="${OCP_CONFIG:-/srv/tftp/config/openshift.conf}"
HAPROXY_CONFIG="${HAPROXY_CONFIG:-/etc/haproxy/haproxy.cfg}"

[[ "$EUID" -eq 0 ]] || { echo "install-haproxy.sh muss als root laufen." >&2; exit 1; }
[[ -r "$OCP_CONFIG" ]] || {
    echo "OpenShift-Konfiguration fehlt: $OCP_CONFIG" >&2
    echo "Zuerst install-openshift.sh ausführen und openshift.conf anpassen." >&2
    exit 1
}

# shellcheck disable=SC1090
source "$OCP_CONFIG"

: "${BOOTSTRAP_IP:?BOOTSTRAP_IP fehlt in $OCP_CONFIG}"
: "${TERRA2_IP:?TERRA2_IP fehlt in $OCP_CONFIG}"
: "${TERRA3_IP:?TERRA3_IP fehlt in $OCP_CONFIG}"
: "${TERRA4_IP:?TERRA4_IP fehlt in $OCP_CONFIG}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y haproxy

cp -a "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

cat >"$HAPROXY_CONFIG" <<EOF_CFG
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 20000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 10s
    timeout client  1m
    timeout server  1m

# OpenShift Kubernetes API. Kein Konflikt mit nginx: Port 80 bleibt bei nginx.
frontend ocp_api
    bind *:6443
    default_backend ocp_api_backend

backend ocp_api_backend
    balance roundrobin
    server bootstrap ${BOOTSTRAP_IP}:6443 check
    server master0 ${TERRA2_IP}:6443 check
    server master1 ${TERRA3_IP}:6443 check
    server master2 ${TERRA4_IP}:6443 check

# Machine Config Server während Installation/Bootstrap.
frontend ocp_mcs
    bind *:22623
    default_backend ocp_mcs_backend

backend ocp_mcs_backend
    balance roundrobin
    server bootstrap ${BOOTSTRAP_IP}:22623 check
    server master0 ${TERRA2_IP}:22623 check
    server master1 ${TERRA3_IP}:22623 check
    server master2 ${TERRA4_IP}:22623 check
EOF_CFG

haproxy -c -f "$HAPROXY_CONFIG"
systemctl enable --now haproxy
systemctl restart haproxy

echo "HAProxy für OpenShift API (6443) und MCS (22623) installiert."
echo "Port 80/443 werden absichtlich nicht von HAProxy belegt; nginx bleibt auf Port 80."
