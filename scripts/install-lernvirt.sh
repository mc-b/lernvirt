#!/usr/bin/env bash
set -o pipefail

# Einfache Logging-Funktionen
log()  { echo "[$(date -Iseconds)] INFO:  $*" >&2; }
warn() { echo "[$(date -Iseconds)] WARN:  $*" >&2; }
fail() { echo "[$(date -Iseconds)] FEHLER: $*" >&2; exit 1; }

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  fail "Bitte als root/sudo ausführen."
fi

export DEBIAN_FRONTEND=noninteractive

HOSTNAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)"
IP_ADDR="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
if [ -z "$IP_ADDR" ]; then
  IP_ADDR="$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
fi
if [ -z "$IP_ADDR" ]; then
  fail "Konnte IP-Adresse nicht automatisch ermitteln."
fi

ARCH_RAW="$(uname -m 2>/dev/null || echo unknown)"
case "$ARCH_RAW" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) fail "Nicht unterstützte Architektur: $ARCH_RAW" ;;
esac

# Hilfsfunktion für Downloads (nicht fatal)
download() {
  local url="$1"
  local destdir="$2"
  mkdir -p "$destdir"
  if ! wget -q -nc -P "$destdir" "$url"; then
    warn "Download fehlgeschlagen: $url"
  else
    log "Download ok: $url"
  fi
}

log "APT-Index aktualisieren…"
if ! apt-get update -y; then
  fail "apt-get update fehlgeschlagen."
fi

# Pakete einzeln installieren, Fehler nur loggen
for pkg in nfs-kernel-server nginx git wget curl; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    log "Paket bereits installiert: $pkg"
  else
    log "Installiere Paket: $pkg"
    if ! apt-get install -y "$pkg"; then
      warn "Paket konnte nicht installiert werden: $pkg"
    fi
  fi
done

# Basisverzeichnisse
mkdir -p /data /data/storage /data/config /data/templates /data/config/ssh
# chown kann fehlschlagen, wenn es den User nicht gibt -> nur warnen
if ! chown -R ubuntu:ubuntu /data 2>/dev/null; then
  warn "Konnte /data nicht auf Benutzer 'ubuntu' setzen (User existiert evtl. nicht)."
fi
chmod 777 /data/storage || warn "Konnte Berechtigungen für /data/storage nicht setzen."

# NFS-Exports schreiben
cat >/etc/exports <<EOF
# /etc/exports: NFS Export-Konfiguration
# Storage RW
/data/storage *(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
# Templates RO
/data/templates *(ro,sync,no_subtree_check)
# Config RO
/data/config *(ro,sync,no_subtree_check)
EOF

if ! exportfs -ra; then
  warn "exportfs -ra fehlgeschlagen. NFS-Exports bitte manuell prüfen."
fi

# Dienste aktivieren/neu starten; Fehler nur warnen
for svc in nfs-kernel-server nginx; do
  if systemctl enable "$svc" >/dev/null 2>&1; then
    log "Dienst aktiviert: $svc"
  else
    warn "Konnte Dienst nicht aktivieren: $svc"
  fi

  if systemctl restart "$svc" >/dev/null 2>&1; then
    log "Dienst neu gestartet: $svc"
  else
    warn "Konnte Dienst nicht neu starten: $svc"
  fi
done

LINUX_BASE="/var/www/html/linux"
mkdir -p \
  "$LINUX_BASE/ubuntu/noble/amd64" \
  "$LINUX_BASE/ubuntu/noble/arm64" \
  "$LINUX_BASE/alpine/edge/amd64" \
  "$LINUX_BASE/alpine/edge/arm64"

# Ubuntu-Images
download "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" \
         "$LINUX_BASE/ubuntu/noble/amd64"
download "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img" \
         "$LINUX_BASE/ubuntu/noble/arm64"

# Alpine-Images
download "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/generic_alpine-3.23.0-x86_64-bios-cloudinit-r0.qcow2" \
         "$LINUX_BASE/alpine/edge/amd64"
download "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/generic_alpine-3.23.2-aarch64-uefi-cloudinit-r0.qcow2" \
         "$LINUX_BASE/alpine/edge/arm64"

LERNVIRT_DIR="/var/www/html/lernvirt"
if [ -d "$LERNVIRT_DIR/.git" ]; then
  log "Aktualisiere bestehendes lernvirt-Repository…"
  if ! git -C "$LERNVIRT_DIR" pull --ff-only; then
    warn "git pull fehlgeschlagen, verwende bestehenden Stand."
  fi
else
  log "Klonen von lernvirt-Repository…"
  rm -rf "$LERNVIRT_DIR" 2>/dev/null || true
  if ! git clone https://github.com/mc-b/lernvirt.git "$LERNVIRT_DIR"; then
    warn "git clone fehlgeschlagen, lernvirt steht evtl. nicht vollständig zur Verfügung."
  fi
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
<h1>lernvirt Modulumgebung</h1>

<h2>Voraussetzungen</h2>
<p>
Für die Arbeit mit <em>lernvirt</em> werden <code>kubectl</code> und <code>helm</code> benötigt.
Beide Werkzeuge sind lokal zu installieren.
</p>
<ul>
  <li>
    kubectl:
    <a href="https://kubernetes.io/docs/tasks/tools/">https://kubernetes.io/docs/tasks/tools/</a>
  </li>
  <li>
    helm:
    <a href="https://helm.sh/docs/intro/install/">https://helm.sh/docs/intro/install/</a>
  </li>
</ul>
<p>
Zusätzlich sind die Zugriffsinformationen auf den Kubernetes-Cluster erforderlich.
Diese werden durch die Administration bereitgestellt (KUBECONFIG).
</p>

<h2>Host-spezifische Konfiguration</h2>
<p>
Für jeden Host existiert eine spezifische Values-Datei.
Diese ist vor der Installation herunterzuladen:
</p>
<ul>
  <li><a href="/lernvirt/hosts/${HOSTNAME}.yaml">hosts/${HOSTNAME}.yaml</a></li>
</ul>

<h2>Installation einer Modulumgebung</h2>
<p>
Die Modulumgebung wird mit <code>helm</code> installiert.
Dabei wird die host-spezifische Konfiguration explizit eingebunden:
</p>
<pre><code>helm install m122 oci://ghcr.io/mc-b/lernvirt -n ap21a --create-namespace -f ${HOSTNAME}.yaml</code></pre>

<p>
Während der Installation gibt <code>helm</code> den Status der erstellten Ressourcen aus.
Diese Ausgaben sind Bestandteil des normalen Installationsablaufs.
</p>

<h2>Ressourcenanpassungen</h2>
<p>
Standardmässig werden virtuelle Maschinen mit 2 vCPU und 2&nbsp;GiB Arbeitsspeicher erstellt.
Diese Werte können bei Bedarf überschrieben werden, zum Beispiel:
</p>
<pre><code>helm install m122 oci://ghcr.io/mc-b/lernvirt -n ap21a --create-namespace -f ${HOSTNAME}.yaml --set vm.memory=4Gi</code></pre>

<h2>cloud-init und Fallback-Mechanismus</h2>
<p>
Das Chart lädt das <code>cloud-init</code>-Script über <code>vm.userdata</code>.
Dabei können mehrere URLs definiert werden.
Es wird jeweils die erste erreichbare Quelle (HTTP&nbsp;200) verwendet.
</p>

<p>
Die standardmässig konfigurierten Fallback-URLs lauten:
</p>
<pre><code>vm:
  userdata:
    - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/master/cloud-init.yaml
    - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/main/cloud-init.yaml
    - https://raw.githubusercontent.com/mc-b/lernmaas/master/gns3/cloud-init.yaml</code></pre>

<p>
Für das Modul <code>m122</code> wird somit zuerst im <code>master</code>-Branch,
anschliessend im <code>main</code>-Branch und zuletzt gemäss der
lernmaas-Logik nach einem passenden <code>cloud-init.yaml</code> gesucht.
</p>

<p>
Details zur Konfiguration sind in
<a href="https://github.com/mc-b/lernvirt/blob/main/CONFIG.md">CONFIG.md</a>
und zu host-spezifischen Anpassungen in
<a href="https://github.com/mc-b/lernvirt/blob/main/hosts/README.md">hosts/README.md</a>
dokumentiert.
</p>

<h2>Hinweis für Administratoren</h2>
<p>
<h3>KUBECONFIG</h3>
Für die Administration existiert ein Hilfsskript zur Erstellung von
<code>KUBECONFIG</code>-Dateien für eine oder mehrere Lehrpersonen:
</p>
<ul>
  <li>
    <a href="https://github.com/mc-b/lernvirt/blob/main/scripts/gen-kubeconfig.sh">
      lernvirt/scripts/gen-kubeconfig.sh
    </a>
  </li>
</ul>

<p>
Das Skript erzeugt eine dedizierte <code>KUBECONFIG</code> basierend auf einem
Lehrpersonen-Kürzel, zum Beispiel:
</p>
<pre><code>gen-kubeconfig.sh &lt;Kürzel Lehrperson&gt;</code></pre>

<h3>PXE Boot (dnsmsaq)</h3>
<p>
Zusätzlich ist auf dem Host <code>dnsmasq</code> installiert.
Dieser Dienst erlaubt es, weitere Worker Nodes automatisiert per PXE-Boot
zu installieren.
</p>

<p>
Aus Sicherheitsgründen ist <code>dnsmasq</code> standardmässig deaktiviert.
Die Aktivierung erfolgt explizit durch die Administration:
</p>
<pre><code>sudo systemctl start dnsmasq</code></pre>

<h3>Weitere Worker Nodes anbinden</h3>
<p>
Zusätzliche Worker Nodes werden über <code>microk8s add-node</code>
am Control Node registriert.
Der Join-Token ist zeitlich begrenzt gültig.
</p>

<p>
Auf dem Control Node:
</p>
<pre><code>ssh -i ~/.ssh/lerncloud ubuntu@kv-control
microk8s add-node --token-ttl 3600 | grep worker | tail -1
exit</code></pre>

<p>
Der ausgegebene Join-Befehl ist anschliessend auf dem jeweiligen Worker Node
auszuführen:
</p>
<pre><code>ssh -i ~/.ssh/lerncloud ubuntu@kv-worker-01
# Ausgabe von microk8s add-node</code></pre>

<p>
Nach erfolgreichem Join erscheint der Worker Node im Cluster
und kann für weitere Workloads verwendet werden.
</p>


</body>

</html>
EOF

log "Fertig: ${HOSTS_DIR}/${HOSTNAME}.yaml (IP=${IP_ADDR}, Arch=${ARCH})"
echo "OK"
