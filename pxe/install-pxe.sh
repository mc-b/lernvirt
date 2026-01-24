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

# IPv4-Adresse und Praefix des Interfaces holen
CIDR="$(ip -4 addr show dev "${IFACE}" 2>/dev/null | awk '/inet / {print $2}' | head -n1)"
if [ -z "${CIDR}" ]; then
  fail "Konnte keine IPv4-Adresse fuer ${IFACE} finden."
fi

PXE_IP="${CIDR%%/*}"
PREFIX="${CIDR##*/}"

# Subnetz-Adresse und Netzmaske berechnen
IFS='.' read -r o1 o2 o3 o4 <<< "${PXE_IP}"
IP_INT=$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))
MASK_INT=$(( (0xFFFFFFFF << (32 - PREFIX)) & 0xFFFFFFFF ))
NET_INT=$(( IP_INT & MASK_INT ))

NET1=$(( (NET_INT >> 24) & 255 ))
NET2=$(( (NET_INT >> 16) & 255 ))
NET3=$(( (NET_INT >> 8) & 255 ))
NET4=$(( NET_INT & 255 ))
SUBNET="${NET1}.${NET2}.${NET3}.${NET4}"

M1=$(( (MASK_INT >> 24) & 255 ))
M2=$(( (MASK_INT >> 16) & 255 ))
M3=$(( (MASK_INT >> 8) & 255 ))
M4=$(( MASK_INT & 255 ))
NETMASK="${M1}.${M2}.${M3}.${M4}"

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
dhcp-range=${SUBNET},proxy,${NETMASK}

# Interface
#interface=${IFACE}
#bind-interfaces
bind-dynamic

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

# .ssh/config
cat <<EOF >/home/ubuntu/.ssh/config
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
LogLevel error
User ubuntu
IdentityFile ~/.ssh/id_rsa_lernvirt
EOF
chown ubuntu:ubuntu /home/ubuntu/.ssh/config
chmod 400 /home/ubuntu/.ssh/config

# 1. SSH-Key für den User 'ubuntu' erzeugen (falls noch nicht vorhanden)
# -N "" setzt kein Passwort, -f definiert den Pfad
SSH_KEY_FILE="/home/ubuntu/.ssh/id_rsa_lernvirt"
if [ ! -f "$SSH_KEY_FILE" ]; then
    log "Erzeuge neuen SSH-Key für Ubuntu-User..."
    ssh-keygen -t rsa -b 4096 -N "" -f "$SSH_KEY_FILE" -C "ubuntu@lernvirt-$(date +%F)"
    chown ubuntu:ubuntu "$SSH_KEY_FILE" "${SSH_KEY_FILE}.pub"
    chmod 400 "$SSH_KEY_FILE" "${SSH_KEY_FILE}.pub"
fi

# Public Key in eine Variable laden
PUB_KEY=$(cat "${SSH_KEY_FILE}.pub")

# 2. user-data herunterladen
log "user-data von lernvirt holen"
TEMP_USERDATA="/tmp/user-data.tmp"
if wget -nv -O "$TEMP_USERDATA" "${USERDATA_URL}"; then
    
    # 3. Den alten Key durch den neuen ersetzen
    # Wir suchen nach der Zeile mit 'ssh-rsa' und ersetzen die komplette Zeile
    log "Injektiere neuen SSH-Key in user-data"
    sed -i "s|ssh-rsa .* insecure@lerncloud|$PUB_KEY|" "$TEMP_USERDATA"
    
    # Datei an Zielort verschieben
    mv "$TEMP_USERDATA" "${WWW}/autoinstall/user-data"
else
    warn "Konnte user-data nicht laden von ${USERDATA_URL}. Autoinstall wird evtl. nicht funktionieren."
fi

log "GRUB PXE Menue erstellen"
if ! cat > "${BASE}/grub/grub.cfg" <<EOF
set timeout=5
set default=1

# WICHTIG: Erlaubt GRUB den Zugriff auf lokale Festplatten
insmod part_gpt
insmod ext2       # Deckt auch ext3/ext4 ab
# Falls die Datei auf einer FAT32/EFI-Partition liegt, zusätzlich:
insmod fat

# Suche nach der Datei und setze root
if search --no-floppy --file --set=root /boot/lernvirt-installed; then
    set default="0"
fi

menuentry "Local boot (lernvirt)" {
    # laedt die lokale Konfiguration von der gefundenen Partition
    configfile (\$root)/boot/grub/grub.cfg
}
menuentry "Ubuntu Server ${UBUNTU_VER} Autoinstall (lernvirt)" {
        set root=(tftp)
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

systemctl restart dnsmasq >/dev/null 2>&1 || true

log "Fertig."
echo "Logs: ${LOG}"
