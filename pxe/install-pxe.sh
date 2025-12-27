#!/usr/bin/env bash
set -euo pipefail

### KONFIGURATION ###
PXE_IP="192.168.1.56"
IFACE="enP7s7"
BASE="/srv/tftp"
WWW="/var/www/html"
LOG="/var/log/dnsmasq-pxe.log"

UBUNTU_VER="24.04.3"
UBUNTU_URL="https://releases.ubuntu.com/noble"
ISO="ubuntu-${UBUNTU_VER}-live-server-amd64.iso"

### ROOT CHECK ###
if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen"
  exit 1
fi

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

# ProxyDHCP für dein Netz
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
tftp-root=/srv/tftp

# Logging
log-dhcp
log-facility=/var/log/dnsmasq-pxe.log
EOF

echo "==> Ubuntu ISO laden"
mkdir ${WWW}/linux/ubuntu/noble/amd64/
wget -O ${WWW}/linux/ubuntu/noble/amd64/${ISO} ${UBUNTU_URL}"/"${ISO}

echo "==> Kernel & Initrd extrahieren"

mkdir -p /tmp/iso
mount -o loop /tmp/${ISO} /tmp/iso
cp /tmp/iso/casper/vmlinuz ${BASE}/vmlinuz
cp /tmp/iso/casper/initrd ${BASE}/initrd
umount /tmp/iso

echo "==> GRUB EFI Bootloader kopieren"

mkdir -p ${BASE}/grub/x86_64-efi/
cp /usr/lib/grub/x86_64-efi/* ${BASE}/grub/x86_64-efi/

cp /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed \
   ${BASE}/grubx64.efi

echo "==> GRUB PXE Menü erstellen"
cat > ${BASE}/grub/grub.cfg <<EOF
set timeout=3
set default=0

menuentry "Ubuntu Server 24.04 Autoinstall (PXE)" {
        linux /vmlinuz \
          ip=dhcp \
          url=http://192.168.1.56/linux/ubuntu/noble/amd64/ubuntu-24.04.3-live-server-amd64.iso \
          autoinstall debug \
          cloud-config-url=http://192.168.1.56/autoinstall/user-data \
      ---
    initrd /initrd
}
EOF

echo "==> dnsmasq starten"
systemctl enable dnsmasq
systemctl restart dnsmasq

echo "==> Status prüfen"
systemctl status dnsmasq --no-pager
ss -lun | grep :69 || echo "⚠️ TFTP Port 69 nicht offen"

echo "==> Fertig!"
echo "PXE Server aktiv unter IP ${PXE_IP}"
echo "Logs: ${LOG}"
