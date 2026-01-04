#!/usr/bin/env bash
set -euo pipefail

### AKTIVES NETZWERK-INTERFACE & IP ERMITTELN ###

# Aktives Interface ueber Default-Route bestimmen
IFACE=$(ip -4 route show default | awk '{print $5; exit}' || true)
if [[ -z "${IFACE}" ]]; then
  # Fallback: erstes nicht-lo Interface nehmen
  IFACE=$(ip -o link show | awk -F': ' '$2 !~ /lo/ {print $2; exit}' || true)
fi

if [[ -z "${IFACE}" ]]; then
  echo "Konnte aktives Netzwerkinterface nicht ermitteln." >&2
  exit 1
fi

# IPv4-Adresse des Interfaces holen
PXE_IP=$(ip -4 addr show dev "${IFACE}" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 || true)
if [[ -z "${PXE_IP}" ]]; then
  echo "Konnte keine IPv4-Adresse fuer ${IFACE} finden." >&2
  exit 1
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

### ROOT CHECK ###
if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausfuehren"
  exit 1
fi

echo "==> Verwende Interface: ${IFACE}, IP: ${PXE_IP}"

echo "==> Pakete installieren"
apt update
apt install -y dnsmasq nginx wget unzip syslinux-common grub-common grub-efi-amd64-bin

echo "==> Verzeichnisse anlegen"
mkdir -p "${BASE}/grub/x86_64-efi" "${WWW}/autoinstall"

echo "==> dnsmasq stoppen (falls aktiv)"
systemctl stop dnsmasq || true

echo "==> dnsmasq ProxyDHCP konfigurieren"

cat > /etc/dnsmasq.d/pxe.conf <<EOF
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

echo "==> Ubuntu ISO laden"
mkdir -p "${ISO_DIR}"
if [[ ! -f "${ISO_DIR}/${ISO}" ]]; then
  wget -O "${ISO_DIR}/${ISO}" "${UBUNTU_URL}/${ISO}"
else
  echo "ISO bereits vorhanden: ${ISO_DIR}/${ISO}"
fi

echo "==> Kernel & Initrd extrahieren"
mkdir -p /tmp/iso
mount -o loop "${ISO_DIR}/${ISO}" /tmp/iso
cp /tmp/iso/casper/vmlinuz "${BASE}/vmlinuz"
cp /tmp/iso/casper/initrd "${BASE}/initrd"
umount /tmp/iso
rmdir /tmp/iso

echo "==> GRUB EFI Bootloader kopieren"
mkdir -p "${BASE}/grub/x86_64-efi/"
cp /usr/lib/grub/x86_64-efi/* "${BASE}/grub/x86_64-efi/"

# grubx64.efi nach /srv/tftp kopieren
cp /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed \
   "${BASE}/grubx64.efi"

echo "==> user-data von lernvirt holen"
wget -O "${WWW}/autoinstall/user-data" "${USERDATA_URL}"

echo "==> GRUB PXE Menue erstellen"
cat > "${BASE}/grub/grub.cfg" <<EOF
set timeout=-1
set default=0

menuentry "Ubuntu Server 24.04 Autoinstall (lernvirt)" {
        linux /vmlinuz \\
          ip=dhcp \\
          url=http://${PXE_IP}/linux/ubuntu/noble/amd64/${ISO} \\
          autoinstall debug \\
          cloud-config-url=http://${PXE_IP}/autoinstall/user-data \\
          ---
        initrd /initrd
}
EOF

echo "==> dnsmasq starten"
systemctl enable dnsmasq
systemctl restart dnsmasq

echo "==> Status pruefen"
systemctl status dnsmasq --no-pager
ss -lun | grep :69 || echo "WARNUNG: TFTP Port 69 nicht offen"

echo "==> Fertig!"
echo "PXE Server aktiv unter IP ${PXE_IP} (Interface: ${IFACE})"
echo "Logs: ${LOG}"
