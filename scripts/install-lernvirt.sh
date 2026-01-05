#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then echo "Bitte als root/sudo ausführen." >&2; exit 1; fi
export DEBIAN_FRONTEND=noninteractive

HOSTNAME="$(hostname -s || hostname)"
IP_ADDR="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
if [ -z "$IP_ADDR" ]; then IP_ADDR="$(ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"; fi
if [ -z "$IP_ADDR" ]; then echo "Konnte IP-Adresse nicht automatisch ermitteln." >&2; exit 1; fi

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Nicht unterstützte Architektur: $ARCH_RAW" >&2; exit 1 ;;
esac

apt-get update -y
apt-get install -y nfs-kernel-server nginx git wget curl

mkdir -p /data /data/storage /data/config /data/templates /data/config/ssh
chown -R ubuntu:ubuntu /data || true
chmod 777 /data/storage

cat >/etc/exports <<EOF
# /etc/exports: NFS Export-Konfiguration
# Storage RW
/data/storage *(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
# Templates RO
/data/templates *(ro,sync,no_subtree_check)
# Config RO
/data/config *(ro,sync,no_subtree_check)
# microk8s Hostpath
/var/snap/microk8s/common/default-storage *(rw,sync,no_subtree_check,no_root_squash)
EOF

exportfs -ra
systemctl enable nfs-kernel-server nginx
systemctl restart nfs-kernel-server nginx

LINUX_BASE="/var/www/html/linux"
mkdir -p "$LINUX_BASE/ubuntu/noble/amd64" "$LINUX_BASE/ubuntu/noble/arm64" "$LINUX_BASE/alpine/edge/amd64" "$LINUX_BASE/alpine/edge/arm64"

wget -q -nc -P "$LINUX_BASE/ubuntu/noble/amd64" "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
wget -q -nc -P "$LINUX_BASE/ubuntu/noble/arm64" "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"

wget -q -nc -P "$LINUX_BASE/alpine/edge/amd64" "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/generic_alpine-3.23.0-x86_64-bios-cloudinit-r0.qcow2"
wget -q -nc -P "$LINUX_BASE/alpine/edge/arm64" "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/generic_alpine-3.23.2-aarch64-uefi-cloudinit-r0.qcow2"

LERNVIRT_DIR="/var/www/html/lernvirt"
if [ -d "$LERNVIRT_DIR/.git" ]; then
  git -C "$LERNVIRT_DIR" pull --ff-only || true
else
  rm -rf "$LERNVIRT_DIR" || true
  git clone https://github.com/mc-b/lernvirt.git "$LERNVIRT_DIR"
fi

HOSTS_DIR="$LERNVIRT_DIR/hosts"
mkdir -p "$HOSTS_DIR"

cat >"$HOSTS_DIR/$HOSTNAME.yaml" <<EOF
# Automatisch generierte Host-Konfiguration für lernvirt

vm:
  count: 3

wgClients:
  count: 3
  endpointNode: ${IP_ADDR}

mirror:
  enabled: true
  mirrorBaseUrl: http://${IP_ADDR}

datasource:
  serverIP: ${IP_ADDR}

os:
  architecture: ${ARCH}
EOF

echo "Fertig: ${HOSTS_DIR}/${HOSTNAME}.yaml (IP=${IP_ADDR}, Arch=${ARCH})"
