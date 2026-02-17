#!/usr/bin/env bash
set -o pipefail
set -e

log()  { echo "[$(date -Iseconds)] INFO:  $*" >&2; }
warn() { echo "[$(date -Iseconds)] WARN:  $*" >&2; }
fail() { echo "[$(date -Iseconds)] FEHLER: $*" >&2; exit 1; }

### ROOT CHECK ###
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  fail "Bitte als root/sudo ausfuehren."
fi

### KONFIG ###
BASE="/srv/tftp"
WWW="/var/www/html"
ALPINE_VER="3.23.3"
ALPINE_MAJOR="v3.23"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-netboot-${ALPINE_VER}-x86_64.tar.gz"

TFTP_ALPINE="${BASE}/alpine"
WWW_ALPINE="${WWW}/alpine"
TMP="/tmp/alpine-netboot"

### IP ERMITTELN (für grub.cfg) ###
IFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
CIDR="$(ip -4 addr show dev "${IFACE}" | awk '/inet / {print $2; exit}')"
PXE_IP="${CIDR%%/*}"

log "Server-IP: ${PXE_IP}"

### VERZEICHNISSE ###
mkdir -p "${TFTP_ALPINE}" "${WWW_ALPINE}" "${TMP}"

### DOWNLOAD ###
TARBALL="${TMP}/alpine-netboot.tar.gz"

if [ ! -f "${TARBALL}" ]; then
  log "Lade Alpine Netboot ${ALPINE_VER}"
  wget -O "${TARBALL}" "${ALPINE_URL}" || fail "Download fehlgeschlagen."
else
  log "Tarball bereits vorhanden."
fi

### ENTPACKEN ###
log "Entpacke Alpine Netboot"
tar -xzf "${TARBALL}" -C "${TMP}" || fail "Entpacken fehlgeschlagen."

# Kernel + initramfs nach TFTP
cp "${TMP}/boot/vmlinuz-lts" "${TFTP_ALPINE}/vmlinuz-lts"
cp "${TMP}/boot/initramfs-lts" "${TFTP_ALPINE}/initramfs-lts"

# modloop nach HTTP
cp "${TMP}/boot/modloop-lts" "${WWW_ALPINE}/modloop-lts"

# Optional auch virt-Variante
if [ -f "${TMP}/boot/vmlinuz-virt" ]; then
  cp "${TMP}/boot/vmlinuz-virt" "${TFTP_ALPINE}/vmlinuz-virt"
  cp "${TMP}/boot/initramfs-virt" "${TFTP_ALPINE}/initramfs-virt"
  cp "${TMP}/boot/modloop-virt" "${WWW_ALPINE}/modloop-virt"
  chmod +r ${TFTP_ALPINE}/*
fi

### GRUB EINTRAG ERGAENZEN ###
GRUB_CFG="${BASE}/grub/grub.cfg"

if ! grep -q "Alpine Linux PXE (lts)" "${GRUB_CFG}"; then
  log "Erweitere GRUB-Konfiguration um Alpine-Eintrag"

cat >> "${GRUB_CFG}" <<EOF

menuentry "Alpine Linux PXE (lts)" {
    set root=(tftp)
    linux /alpine/vmlinuz-lts \\
        ip=dhcp \\
        alpine_repo=https://dl-cdn.alpinelinux.org/alpine/${ALPINE_MAJOR}/main \\
        modloop=http://${PXE_IP}/alpine/modloop-lts \\
        modules=loop,squashfs,sd-mod,usb-storage,nvme,nvme-core \\
        overlaytmpfs=yes
    initrd /alpine/initramfs-lts
}

EOF

else
  log "Alpine-Eintrag existiert bereits, ueberspringe."
fi

log "Fertig."
