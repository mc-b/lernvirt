#!/usr/bin/env bash
set -euo pipefail

### KONFIGURATION ###
PXE_IP="10.1.0.10"
IFACE="eth0"
BASE="/opt/lernvirt/pxe"
BOOT="$BASE/boot"
WWW="$BASE/www/autoinstall"
LOG="/var/log/dnsmasq-pxe.log"

UBUNTU_VER="noble/ubuntu-24.04.3"
UBUNTU_URL="https://releases.ubuntu.com/${UBUNTU_VER}"
ISO="ubuntu-${UBUNTU_VER}-live-server-amd64.iso"

### ROOT CHECK ###
if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen"
  exit 1
fi

echo "==> Pakete installieren"
apt update
apt install -y dnsmasq nginx wget unzip syslinux-common

echo "==> Verzeichnisse anlegen"
mkdir -p "$BOOT" "$WWW"

echo "==> dnsmasq stoppen (falls aktiv)"
systemctl stop dnsmasq || true

echo "==> dnsmasq ProxyDHCP konfigurieren"
cat > /etc/dnsmasq.d/pxe.conf <<EOF
port=0
dhcp-range=::,proxy
interface=${IFACE}
bind-interfaces

domain-needed
bogus-priv
stop-dns-rebind

dhcp-match=set:efi64,option:client-arch,7
dhcp-boot=tag:efi64,grubx64.efi

enable-tftp
tftp-root=${BOOT}
tftp-secure

log-dhcp
log-queries
log-facility=${LOG}

dhcp-authoritative
dhcp-no-override
dhcp-ignore-names
EOF

echo "==> Ubuntu ISO laden"
wget -O /tmp/${ISO} ${UBUNTU_URL}/${ISO}

echo "==> Kernel & Initrd extrahieren"
mkdir -p /tmp/iso
mount -o loop /tmp/${ISO} /tmp/iso
cp /tmp/iso/casper/vmlinuz ${BOOT}/vmlinuz
cp /tmp/iso/casper/initrd ${BOOT}/initrd
umount /tmp/iso

echo "==> GRUB EFI Bootloader kopieren"
cp /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed \
   ${BOOT}/grubx64.efi

echo "==> GRUB PXE Menü erstellen"
cat > ${BOOT}/grub.cfg <<EOF
set timeout=5
set default=0

menuentry "Ubuntu Server 24.04 Autoinstall (lernvirt)" {
  linux /vmlinuz ip=dhcp autoinstall \
    ds=nocloud-net;s=http://${PXE_IP}/autoinstall/
  initrd /initrd
}
EOF

echo "==> nginx Autoinstall-Pfad aktivieren"
ln -sf ${BASE}/www /var/www/html/autoinstall
systemctl restart nginx

echo "==> dnsmasq starten"
systemctl enable dnsmasq
systemctl restart dnsmasq

echo "==> Status prüfen"
systemctl status dnsmasq --no-pager
ss -lun | grep :69 || echo "⚠️ TFTP Port 69 nicht offen"

echo "==> Fertig!"
echo "PXE Server aktiv unter IP ${PXE_IP}"
echo "Logs: ${LOG}"
