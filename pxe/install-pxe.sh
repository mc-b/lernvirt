#!/usr/bin/env bash
set -o pipefail

log()  { echo "[$(date -Iseconds)] INFO:  $*" >&2; }
warn() { echo "[$(date -Iseconds)] WARN:  $*" >&2; }
fail() { echo "[$(date -Iseconds)] FEHLER: $*" >&2; exit 1; }

### ROOT CHECK ###
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  fail "Bitte als root/sudo ausfuehren."
fi

### AKTIVES NETZWERK-INTERFACE & IP ERMITTELN ###

# Aktives Interface ueber Default-Route bestimmen
IFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
if [ -z "${IFACE}" ]; then
  # Fallback: erstes nicht-lo Interface nehmen
  IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /lo/ {print $2; exit}')"
fi

if [ -z "${IFACE}" ]; then
  fail "Konnte aktives Netzwerkinterface nicht ermitteln."
fi

# IPv4-Adresse des Interfaces holen
PXE_IP="$(ip -4 addr show dev "${IFACE}" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
if [ -z "${PXE_IP}" ]; then
  fail "Konnte keine IPv4-Adresse fuer ${IFACE} finden."
fi

### KONFIGURATION ###
BASE="/srv/tftp"
WWW="/var/www/html"
LOG="/var/log/dnsmasq-pxe.log"

UBUNTU_VER="24.04.3"
UBUNTU_URL="https://releases.ubuntu.com/noble"
ISO="ubuntu-${UBUNTU_VER}-live-server-amd64.iso"
ISO_DIR="${WWW}/linux/ubuntu/noble/amd64"

USERDATA_URL="https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/pxe/user-data"

log "Verwende Interface: ${IFACE}, IP: ${PXE_IP}"

log "APT Index aktualisieren"
if ! apt-get update -y; then
  fail "apt-get update fehlgeschlagen."
fi

log "Pakete installieren"
for pkg in dnsmasq nginx wget unzip syslinux-common grub-common grub-efi-amd64-bin; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    log "Paket bereits installiert: $pkg"
  else
    log "Installiere Paket: $pkg"
    if ! apt-get install -y "$pkg"; then
      warn "Konnte Paket nicht installieren: $pkg"
    fi
  fi
done

log "Verzeichnisse anlegen"
mkdir -p "${BASE}/grub/x86_64-efi" "${WWW}/autoinstall" "${ISO_DIR}"
mkdir -p "$(dirname "${LOG}")" 2>/dev/null || true

log "dnsmasq stoppen (falls aktiv)"
systemctl stop dnsmasq >/dev/null 2>&1 || true

log "dnsmasq ProxyDHCP konfigurieren"
if ! cat > /etc/dnsmasq.d/pxe.conf <<EOF
# DNS aus
port=0

# ProxyDHCP fuer dein Netz (evtl. an eigenes Netz anpassen)
dhcp-range=192.168.1.0,proxy,255.255.255.0

# Interface
interface=${IFACE}
bind-interfaces

# PXE-Clients erkennen
dhcp-match=set:pxe,option:vendor-class,PXEClient

# PXE-Service
pxe-service=tag:pxe,X86-64_EFI,"UEFI PXE Boot",grubx64.efi

# Next-Server
dhcp-option-force=tag:pxe,66,${PXE_IP}

# TFTP
enable-tftp
tftp-root=${BASE}

# Logging
log-dhcp
log-facility=${LOG}
EOF
then
  fail "Konnte /etc/dnsmasq.d/pxe.conf nicht schreiben."
fi

log "Ubuntu ISO laden"
if [ ! -f "${ISO_DIR}/${ISO}" ]; then
  if ! wget -nv -O "${ISO_DIR}/${ISO}" "${UBUNTU_URL}/${ISO}"; then
    fail "Download der ISO fehlgeschlagen: ${UBUNTU_URL}/${ISO}"
  fi
else
  log "ISO bereits vorhanden: ${ISO_DIR}/${ISO}"
fi

log "Kernel & Initrd extrahieren"
TMP_ISO_DIR="/tmp/iso"
mkdir -p "${TMP_ISO_DIR}"

if mountpoint -q "${TMP_ISO_DIR}"; then
  warn "${TMP_ISO_DIR} ist bereits gemountet, versuche umount."
  umount "${TMP_ISO_DIR}" || fail "Konnte bestehendes Mount von ${TMP_ISO_DIR} nicht loesen."
fi

if ! mount -o loop "${ISO_DIR}/${ISO}" "${TMP_ISO_DIR}"; then
  fail "Konnte ISO nicht mounten: ${ISO_DIR}/${ISO}"
fi

if ! cp "${TMP_ISO_DIR}/casper/vmlinuz" "${BASE}/vmlinuz"; then
  umount "${TMP_ISO_DIR}" || warn "Konnte ${TMP_ISO_DIR} nicht unmounten."
  fail "Konnte vmlinuz aus ISO nicht kopieren."
fi

if ! cp "${TMP_ISO_DIR}/casper/initrd" "${BASE}/initrd"; then
  umount "${TMP_ISO_DIR}" || warn "Konnte ${TMP_ISO_DIR} nicht unmounten."
  fail "Konnte initrd aus ISO nicht kopieren."
fi

if ! umount "${TMP_ISO_DIR}"; then
  warn "Konnte ${TMP_ISO_DIR} nicht unmounten."
fi
rmdir "${TMP_ISO_DIR}" 2>/dev/null || true

log "GRUB EFI Bootloader kopieren"
mkdir -p "${BASE}/grub/x86_64-efi/"

if ! cp -r /usr/lib/grub/x86_64-efi/* "${BASE}/grub/x86_64-efi/" 2>/dev/null; then
  warn "Konnte GRUB-Module nicht nach ${BASE}/grub/x86_64-efi kopieren."
fi

GRUB_NET_EFI="/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed"
if [ -f "${GRUB_NET_EFI}" ]; then
  if ! cp "${GRUB_NET_EFI}" "${BASE}/grubx64.efi"; then
    warn "Konnte ${GRUB_NET_EFI} nicht nach ${BASE}/grubx64.efi kopieren."
  fi
else
  warn "Signed GRUB-Net-EFI nicht gefunden unter ${GRUB_NET_EFI}. Bitte Pfad pruefen."
fi

log "user-data von lernvirt holen"
if ! wget -nv -O "${WWW}/autoinstall/user-data" "${USERDATA_URL}"; then
  warn "Konnte user-data nicht laden von ${USERDATA_URL}. Autoinstall wird evtl. nicht funktionieren."
fi

log "GRUB PXE Menue erstellen"
if ! cat > "${BASE}/grub/grub.cfg" <<EOF
set timeout=60
set default=0

menuentry "Ubuntu Server ${UBUNTU_VER} Autoinstall (lernvirt)" {
        linux /vmlinuz \\
          ip=dhcp \\
          url=http://${PXE_IP}/linux/ubuntu/noble/amd64/${ISO} \\
          autoinstall debug \\
          cloud-config-url=http://${PXE_IP}/autoinstall/user-data \\
          ---
        initrd /initrd
}
EOF
then
  fail "Konnte ${BASE}/grub/grub.cfg nicht schreiben."
fi

log "dnsmasq fuer automatischen Start deaktivieren"
systemctl disable dnsmasq >/dev/null 2>&1 || warn "Konnte dnsmasq nicht deaktivieren (evtl. kein Systemd-Unit vorhanden)."
systemctl stop dnsmasq >/dev/null 2>&1 || true

log "Fertig."
echo "PXE Server starten mittels: sudo systemctl start dnsmasq"
echo "Logs: ${LOG}"
