#!/usr/bin/env bash
set -Eeuo pipefail

STACK="${STACK:-ubuntu}"
VARIANT="${VARIANT:-}"

PXE_SERVER="${PXE_SERVER:-192.168.1.101}"
PXE_INTERFACE="${PXE_INTERFACE:-br0}"
PXE_NETWORK="${PXE_NETWORK:-192.168.1.0}"
PXE_NETMASK="${PXE_NETMASK:-255.255.255.0}"

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
PROVISION_HTTP_PORT="${PROVISION_HTTP_PORT:-8080}"
INSTALL_DISK="${INSTALL_DISK:-/dev/nvme0n1}"

UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.4}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
ALPINE_VERSION="${ALPINE_VERSION:-3.22}"

BOOT_TOOLS="${BOOT_TOOLS:-1}"
GRUB_TIMEOUT="${GRUB_TIMEOUT:-5}"
PREPARE_ASSETS="${PREPARE_ASSETS:-1}"
SSH_KEY_REQUIRED="${SSH_KEY_REQUIRED:-1}"
SSH_KEY_FILE="${SSH_KEY_FILE:-/etc/lernvirt/lerncloud.pub}"
SSH_PUBLIC_KEY_URL="${SSH_PUBLIC_KEY_URL:-}"

PXE_STACK_ARCHIVE_URL="${PXE_STACK_ARCHIVE_URL:-https://github.com/mc-b/lernvirt/archive/refs/heads/main.tar.gz}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "install-pxe.sh muss als root laufen." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Pakete installieren"
apt-get update
apt-get install -y \
    ca-certificates curl dnsmasq nginx git \
    grub-common grub-efi-amd64-bin \
    jq rsync xorriso openssh-client

mkdir -p \
    "$TFTP_ROOT/bin" \
    "$TFTP_ROOT/config" \
    "$TFTP_ROOT/grub/stacks" \
    "$HTTP_ROOT/autoinstall" \
    "$HTTP_ROOT/autoyast"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> pxe-stack Quellen laden"
curl -fsSL --retry 5 --retry-delay 3 \
    "$PXE_STACK_ARCHIVE_URL" -o "$tmp/lernvirt.tar.gz"
tar -xzf "$tmp/lernvirt.tar.gz" -C "$tmp"

src="$(find "$tmp" -mindepth 2 -maxdepth 2 -type d -name pxe-stack -print -quit)"
[[ -n "$src" && -d "$src" ]] || {
    echo "pxe-stack/ im Quellarchiv nicht gefunden: $PXE_STACK_ARCHIVE_URL" >&2
    exit 1
}
repo_root="$(dirname "$src")"

# GRUB UEFI Network Boot erzeugen. Danach werden unsere Konfigurationen darübergelegt.
echo "==> GRUB Network Boot erzeugen"
grub-mknetdir --net-directory="$TFTP_ROOT" --subdir=/grub >/dev/null

echo "==> pxe-stack Dateien installieren"
install -m 0644 "$src/grub/grub.cfg" "$TFTP_ROOT/grub/grub.cfg"
install -m 0644 "$src/grub/boot-tools.cfg" "$TFTP_ROOT/grub/boot-tools.cfg"

shopt -s nullglob
stack_files=("$src"/grub/stacks/*.cfg)
bin_files=("$src"/bin/*)
config_files=("$src"/config/*)
shopt -u nullglob

((${#stack_files[@]} > 0)) || { echo "Keine GRUB-Stacks im Quellarchiv gefunden" >&2; exit 1; }
((${#bin_files[@]} > 0)) || { echo "Keine Hilfsscripts im Quellarchiv gefunden" >&2; exit 1; }

for f in "${stack_files[@]}"; do
    install -m 0644 "$f" "$TFTP_ROOT/grub/stacks/$(basename "$f")"
done

for f in "${bin_files[@]}"; do
    [[ -f "$f" ]] || continue
    install -m 0755 "$f" "$TFTP_ROOT/bin/$(basename "$f")"
done

for f in "${config_files[@]}"; do
    [[ -f "$f" ]] || continue
    install -m 0644 "$f" "$TFTP_ROOT/config/$(basename "$f")"
done

if [[ ! -e "$TFTP_ROOT/config/openshift.conf" ]]; then
    cp "$TFTP_ROOT/config/openshift.conf.example" "$TFTP_ROOT/config/openshift.conf"
fi

if [[ ! -e "$TFTP_ROOT/config/rack.conf" ]]; then
    cat >"$TFTP_ROOT/config/rack.conf" <<EOF
PXE_SERVER="${PXE_SERVER}"
PXE_INTERFACE="${PXE_INTERFACE}"
PXE_NETWORK="${PXE_NETWORK}"
PXE_NETMASK="${PXE_NETMASK}"

TFTP_ROOT="${TFTP_ROOT}"
HTTP_ROOT="${HTTP_ROOT}"
PROVISION_HTTP_PORT="${PROVISION_HTTP_PORT}"

INSTALL_DISK="${INSTALL_DISK}"

UBUNTU_VERSION="${UBUNTU_VERSION}"
UBUNTU_CODENAME="${UBUNTU_CODENAME}"

ALPINE_VERSION="${ALPINE_VERSION}"
BOOT_TOOLS="${BOOT_TOOLS}"

GRUB_TIMEOUT="${GRUB_TIMEOUT}"

SSH_KEY_FILE="${SSH_KEY_FILE}"
SSH_PUBLIC_KEY_URL="${SSH_PUBLIC_KEY_URL}"

HOSTS=(
    "*|${STACK}|${VARIANT}"
)
EOF
else
    echo "==> Bestehendes $TFTP_ROOT/config/rack.conf bleibt unverändert"
fi

# SSH Public Key wie im bisherigen pxe/-Setup bereitstellen. Vorhandene Keys
# werden nicht überschrieben. Der Helper kann zusätzlich die .pub-Quelle aus
# dem bisherigen pxe/install-pxe.sh im heruntergeladenen Repository ableiten.
echo "==> SSH Public Key vorbereiten"
if ! PXE_STACK_REPO_ROOT="$repo_root" SSH_KEY_FILE="$SSH_KEY_FILE" SSH_PUBLIC_KEY_URL="$SSH_PUBLIC_KEY_URL" \
    "$TFTP_ROOT/bin/prepare-ssh-key"; then
    if [[ "$SSH_KEY_REQUIRED" == "1" ]]; then
        exit 1
    fi
    echo "WARNUNG: SSH Public Key wurde nicht eingerichtet." >&2
fi

# Minimale Basis- und Reset-Autoinstallation nur anlegen, wenn noch nichts existiert.
# Die Vorlagen enthalten bewusst Platzhalter, damit ein anderer PXE_SERVER/Port
# auch bei cloud-init-Aufrufen korrekt in die late-commands gelangt.
mkdir -p "$HTTP_ROOT/autoinstall"
for profile in user-data user-data-reset; do
    if [[ ! -e "$HTTP_ROOT/autoinstall/$profile" ]]; then
        sed \
            -e "s/__PXE_SERVER__/${PXE_SERVER}/g" \
            -e "s/__HTTP_PORT__/${PROVISION_HTTP_PORT}/g" \
            "$src/autoinstall/$profile" >"$HTTP_ROOT/autoinstall/$profile"
        chmod 0644 "$HTTP_ROOT/autoinstall/$profile"
    fi
done

# dnsmasq läuft als Proxy-DHCP. Der vorhandene Router/DHCP verteilt weiterhin IP-Adressen.
echo "==> dnsmasq konfigurieren"
cat >/etc/dnsmasq.d/pxe-stack.conf <<EOF
port=0
interface=${PXE_INTERFACE}
bind-dynamic

log-dhcp

dhcp-range=${PXE_NETWORK},proxy,${PXE_NETMASK}
dhcp-no-override

enable-tftp
tftp-root=${TFTP_ROOT}

# UEFI x86_64. Firmware verwendet je nach Hersteller Arch 7 oder 9.
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9
dhcp-boot=tag:efi64,grub/x86_64-efi/core.efi,,${PXE_SERVER}

# In Proxy-DHCP ist pxe-service für UEFI wichtig.
pxe-prompt="lernvirt PXE",0
pxe-service=BC_EFI,"lernvirt PXE",grub/x86_64-efi/core.efi,${PXE_SERVER}
pxe-service=X86-64_EFI,"lernvirt PXE",grub/x86_64-efi/core.efi,${PXE_SERVER}
EOF

dnsmasq --test

# Provisionierungs-HTTP bewusst auf 8080 (oder PROVISION_HTTP_PORT),
# damit 80/443 für OpenShift/HAProxy frei bleiben können.
echo "==> nginx Provisionierungs-HTTP konfigurieren"
cat >/etc/nginx/sites-available/pxe-stack <<EOF
server {
    listen ${PROVISION_HTTP_PORT} default_server;
    listen [::]:${PROVISION_HTTP_PORT} default_server;

    server_name _;
    root ${HTTP_ROOT};

    location / {
        try_files \$uri \$uri/ =404;
        autoindex on;
    }
}
EOF

ln -sfn /etc/nginx/sites-available/pxe-stack /etc/nginx/sites-enabled/pxe-stack

# Falls zufällig ein anderer Default-Server auf demselben Port existiert,
# liefert nginx -t hier absichtlich einen Fehler statt eine kaputte Installation.
nginx -t

echo "==> GRUB Host-/Runtime-Konfiguration rendern"
"$TFTP_ROOT/bin/pxe-render"

if [[ "$PREPARE_ASSETS" == "1" ]]; then
    echo "==> Images/Assets für aktive PXE-Stacks vorbereiten"
    PXE_STACK_REPO_ROOT="$repo_root" "$TFTP_ROOT/bin/pxe-prepare"
fi

systemctl enable --now dnsmasq nginx
systemctl restart dnsmasq nginx

echo
echo "PXE Stack installiert."
echo "  Stack : $STACK ${VARIANT:+($VARIANT)}"
echo "  TFTP  : $TFTP_ROOT"
echo "  HTTP  : http://${PXE_SERVER}:${PROVISION_HTTP_PORT}/"
echo
"$TFTP_ROOT/bin/pxe-show"

