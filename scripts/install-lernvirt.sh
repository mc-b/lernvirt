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

WWW_ROOT="/var/www/html"
mkdir -p "$WWW_ROOT"

cat >"$WWW_ROOT/index.html" <<EOF
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <title>lernvirt Host ${HOSTNAME}</title>
  <style>
    body { font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 960px; margin: 2rem auto; line-height: 1.5; }
    pre { background: #f5f5f5; padding: .75rem; overflow-x: auto; }
    code { font-family: SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }
    h1, h2, h3 { font-weight: 600; }
  </style>
</head>
<body>
<h1>lernvirt / KubeVirt Modulumgebung</h1>

<h2>Erstellen einer Modulumgebung für eine Klasse</h2>
<p>Beispiel:</p>
<pre><code>helm install m122 oci://ghcr.io/mc-b/lernvirt -n ap21a --create-namespace</code></pre>
<p>Dieses Chart stellt die KubeVirt-Umgebung bereit und liest das passende <code>cloud-init</code>-Script über <code>vm.userdata</code> ein (siehe <a href="https://github.com/mc-b/lernvirt/blob/main/CONFIG.md">CONFIG.md</a>).</p>
<p><code>vm.userdata</code> kann entweder eine einzelne URL oder eine Liste von Fallback-URLs sein; es wird jeweils die erste erreichbare (HTTP 200) verwendet. Standardmässig werden folgende Fallback-URLs verwendet:</p>
<pre><code>vm:
  userdata:
    - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/master/cloud-init.yaml
    - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/main/cloud-init.yaml
    - https://raw.githubusercontent.com/mc-b/lernmaas/master/gns3/cloud-init.yaml</code></pre>
<p>Für das Modul <code>m122</code> wird somit zuerst nach <code>https://raw.githubusercontent.com/tbz-it/m122/refs/heads/master/cloud-init.yaml</code>, danach im <code>main</code>-Branch und anschliessend nach der <a href="https://github.com/mc-b/lernmaas">lernmaas</a>-Logik über deren <a href="https://github.com/mc-b/lernmaas/blob/master/config.yaml">config.yaml</a> gesucht.</p>
<p>Die VMs verwenden per Default 2 Cores und 2&nbsp;GiB Memory. Diese Werte können z.B. so überschrieben werden:</p>
<pre><code>helm install m169k3s oci://ghcr.io/mc-b/lernmaas -n ap21a --create-namespace -f hosts/gx10.yaml --set vm.memory=4Gi</code></pre>
<h3>Host-spezifische Konfiguration (<code>hosts/${HOSTNAME}.yaml</code>)</h3>
<p>Auf diesem Host wurde folgende Datei generiert:</p>
<ul>
  <li><a href="/lernvirt/hosts/${HOSTNAME}.yaml">/lernvirt/hosts/${HOSTNAME}.yaml</a></li>
</ul>
<p>Diese Datei kann als zusätzliche Values-Datei verwendet werden, z.B.:</p>
<pre><code>helm install m122 oci://ghcr.io/mc-b/lernvirt -n ap21a --create-namespace -f hosts/${HOSTNAME}.yaml</code></pre>
<p>Weitere Informationen zu Host-Anpassungen wie Image Mirror, ARM64 etc. finden sich im <a href="https://github.com/mc-b/lernvirt/blob/main/hosts/README.md">hosts/README.md</a>.</p>
</body>
</html>
EOF

echo "Fertig: ${HOSTS_DIR}/${HOSTNAME}.yaml (IP=${IP_ADDR}, Arch=${ARCH})"
