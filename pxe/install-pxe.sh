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

IFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
if [ -z "${IFACE}" ]; then
  IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /lo/ {print $2; exit}')"
fi

[ -z "${IFACE}" ] && fail "Konnte aktives Netzwerkinterface nicht ermitteln."

PXE_IP="$(ip -4 addr show dev "${IFACE}" \
  | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"

[ -z "${PXE_IP}" ] && fail "Konnte keine IPv4-Adresse fuer ${IFACE} finden."

SUBNET_CIDR="$(ip -4 addr show dev "${IFACE}" | awk '/inet / {print $2; exit}')"
[ -z "${SUBNET_CIDR}" ] && fail "Konnte Subnetz fuer ${IFACE} nicht ermitteln."

### KONFIGURATION ###
BASE="/srv/tftp"
WWW="/var/www/html"
LOG="/var/log/dnsmasq-pxe.log"

UBUNTU_VER="24.04.3"
UBUNTU_URL="https://releases.ubuntu.com/noble"
ISO="ubuntu-${UBUNTU_VER}-live-server-amd64.iso"
ISO_DIR="${WWW}/linux/ubuntu/noble/amd64"

USERDATA_URL="https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/pxe/user-data"

log "Verwende Interface: ${IFACE}, IP: ${PXE_IP}, Netz: ${SUBNET_CIDR}"

log "APT Index aktualisieren"
apt-get update -y || fail "apt-get update fehlgeschlagen."

log "Pakete installieren"
for pkg in dnsmasq nginx wget unzip syslinux-common grub-common grub-efi-amd64-bin ipcalc; do
  dpkg -s "$pkg" >/dev/null 2>&1 || apt-get install -y "$pkg" || warn "Konnte Paket nicht installieren: $pkg"
done

NETWORK="$(ipcalc -n "${SUBNET_CIDR}" | awk -F= '/NETWORK/ {print $2}')"
NETMASK="$(ipcalc -m "${SUBNET_CIDR}" | awk -F= '/NETMASK/ {print $2}')"

[ -z "${NETWORK}" ] || [ -z "${NETMASK}" ] && fail "Subnetzberechnung fehlgeschlagen."

log "Ermitteltes PXE-Netz: ${NETWORK} ${NETMASK}"

log "Verzeichnisse anlegen"
mkdir -p "${BASE}/grub/x86_64-efi" "${WWW}/autoinstall" "${ISO_DIR}"
mkdir -p "$(dirname "${LOG}")" 2>/dev/null || true

log "dnsmasq stoppen (falls aktiv)"
systemctl stop dnsmasq >/dev/null 2>&1 || true

log "dnsmasq ProxyDHCP konfigurieren"
cat > /etc/dnsmasq.d/pxe.conf <<EOF || fail "Konnte dnsmasq Konfiguration nicht schreiben."
port=0

dhcp-range=${NETWORK},proxy,${NETMASK}

interface=${IFACE}
bind-interfaces

dhcp-match=set:pxe,option:vendor-class,PXEClient
pxe-service=tag:pxe,X86-64_EFI,"UEFI PXE Boot",grubx64.efi

dhcp-option-force=tag:pxe,66,${PXE_IP}

enable-tftp
tftp-root=${BASE}

log-dhcp
log-facility=${LOG}
EOF

log "Ubuntu ISO laden"
[ -f "${ISO_DIR}/${ISO}" ] || wget -nv -O "${ISO_DIR}/${ISO}" "${UBUNTU_URL}/${ISO}" || fail "ISO Download fehlgeschlagen"

log "Kernel & Initrd extrahieren"
TMP_ISO_DIR="/tmp/iso"
mkdir -p "${TMP_ISO_DIR}"

mountpoint -q "${TMP_ISO_DIR}" && umount "${TMP_ISO_DIR}" || true
mount -o loop "${ISO_DIR}/${ISO}" "${TMP_ISO_DIR}" || fail "ISO mount fehlgeschlagen"

cp "${TMP_ISO_DIR}/casper/vmlinuz" "${BASE}/vmlinuz" || fail "vmlinuz kopieren fehlgeschlagen"
cp "${TMP_ISO_DIR}/casper/initrd"  "${BASE}/initrd"  || fail "initrd kopieren fehlgeschlagen"

umount "${TMP_ISO_DIR}" || warn "Unmount fehlgeschlagen"
rmdir "${TMP_ISO_DIR}" 2>/dev/null || true

log "GRUB EFI Bootloader kopieren"
cp -r /usr/lib/grub/x86_64-efi/* "${BASE}/grub/x86_64-efi/" 2>/dev/null || true

GRUB_NET_EFI="/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed"
[ -f "${GRUB_NET_EFI}" ] && cp "${GRUB_NET_EFI}" "${BASE}/grubx64.efi" || warn "Signed GRUB EFI fehlt"

log "user-data von lernvirt holen"
wget -nv -O "${WWW}/autoinstall/user-data" "${USERDATA_URL}" || warn "user-data Download fehlgeschlagen"

log "GRUB PXE Menu erstellen"
cat > "${BASE}/grub/grub.cfg" <<EOF || fail "GRUB Config schreiben fehlgeschlagen"
set timeout=60
set default=0

menuentry "Ubuntu Server ${UBUNTU_VER} Autoinstall (lernvirt)" {
  linux /vmlinuz ip=dhcp \
    url=http://${PXE_IP}/linux/ubuntu/noble/amd64/${ISO} \
    autoinstall debug \
    cloud-config-url=http://${PXE_IP}/autoinstall/user-data \
    ---
  initrd /initrd
}
EOF

log "dnsmasq Autostart deaktivieren"
systemctl disable dnsmasq >/dev/null 2>&1 || true
systemctl stop dnsmasq >/dev/null 2>&1 || true

log "Fertig."
echo "PXE Server starten mit: sudo systemctl start dnsmasq"
echo "Logs: ${LOG}"
