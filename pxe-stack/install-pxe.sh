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
    openssh-client

mkdir -p \
    "$TFTP_ROOT/bin" \
    "$TFTP_ROOT/config" \
    "$TFTP_ROOT/grub/stacks" \
    "$HTTP_ROOT/autoinstall"

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

echo "==> GRUB Network Boot erzeugen"
grub-mknetdir --net-directory="$TFTP_ROOT" --subdir=/grub >/dev/null

echo "==> PXE Basis installieren"
install -m 0644 "$src/grub/grub.cfg" "$TFTP_ROOT/grub/grub.cfg"
install -m 0644 "$src/grub/boot-tools.cfg" "$TFTP_ROOT/grub/boot-tools.cfg"

# Nur Basis-Stacks und Basis-Hilfsscripts installieren. Optionale Add-ons wie
# SUSE und OpenShift liegen unter addons/ und werden hier bewusst nicht kopiert.
shopt -s nullglob
stack_files=("$src"/grub/stacks/*.cfg)
bin_files=("$src"/bin/*)
config_files=("$src"/config/*)
shopt -u nullglob

((${#stack_files[@]} > 0)) || { echo "Keine GRUB-Basis-Stacks gefunden" >&2; exit 1; }
((${#bin_files[@]} > 0)) || { echo "Keine PXE-Hilfsscripts gefunden" >&2; exit 1; }

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

if [[ ! -e "$TFTP_ROOT/config/rack.conf" ]]; then
    cat >"$TFTP_ROOT/config/rack.conf" <<EOF_RACK
PXE_SERVER="${PXE_SERVER}"
PXE_INTERFACE="${PXE_INTERFACE}"
PXE_NETWORK="${PXE_NETWORK}"
PXE_NETMASK="${PXE_NETMASK}"

TFTP_ROOT="${TFTP_ROOT}"
HTTP_ROOT="${HTTP_ROOT}"

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
EOF_RACK
else
    echo "==> Bestehendes $TFTP_ROOT/config/rack.conf bleibt unverändert"
fi

echo "==> SSH Public Key vorbereiten"
if ! PXE_STACK_REPO_ROOT="$repo_root" SSH_KEY_FILE="$SSH_KEY_FILE" SSH_PUBLIC_KEY_URL="$SSH_PUBLIC_KEY_URL" \
    "$TFTP_ROOT/bin/prepare-ssh-key"; then
    if [[ "$SSH_KEY_REQUIRED" == "1" ]]; then
        exit 1
    fi
    echo "WARNUNG: SSH Public Key wurde nicht eingerichtet." >&2
fi

# Basis- und Reset-Autoinstallation nur anlegen, wenn noch nichts existiert.
mkdir -p "$HTTP_ROOT/autoinstall"
for profile in user-data user-data-reset; do
    if [[ ! -e "$HTTP_ROOT/autoinstall/$profile" ]]; then
        sed -e "s/__PXE_SERVER__/${PXE_SERVER}/g" \
            "$src/autoinstall/$profile" >"$HTTP_ROOT/autoinstall/$profile"
        chmod 0644 "$HTTP_ROOT/autoinstall/$profile"
    fi
done

echo "==> dnsmasq konfigurieren"
cat >/etc/dnsmasq.d/pxe-stack.conf <<EOF_DNSMASQ
port=0
interface=${PXE_INTERFACE}
bind-dynamic

log-dhcp

dhcp-range=${PXE_NETWORK},proxy,${PXE_NETMASK}
dhcp-no-override

enable-tftp
tftp-root=${TFTP_ROOT}

dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9
dhcp-boot=tag:efi64,grub/x86_64-efi/core.efi,,${PXE_SERVER}

pxe-prompt="lernvirt PXE",0
pxe-service=BC_EFI,"lernvirt PXE",grub/x86_64-efi/core.efi,${PXE_SERVER}
pxe-service=X86-64_EFI,"lernvirt PXE",grub/x86_64-efi/core.efi,${PXE_SERVER}
EOF_DNSMASQ

dnsmasq --test

# nginx ist Teil der PXE-Basis und bleibt auf Port 80. HAProxy wird von
# install-haproxy.sh separat eingerichtet und verändert diese Konfiguration nicht.
echo "==> nginx auf Port 80 konfigurieren"
cat >/etc/nginx/sites-available/pxe-stack <<EOF_NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;
    root ${HTTP_ROOT};

    location / {
        try_files \$uri \$uri/ =404;
        autoindex on;
    }
}
EOF_NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/pxe-stack /etc/nginx/sites-enabled/pxe-stack
nginx -t

echo "==> GRUB Host-/Runtime-Konfiguration rendern"
"$TFTP_ROOT/bin/pxe-render"

if [[ "$PREPARE_ASSETS" == "1" ]]; then
    echo "==> Images/Assets für aktive Basis-Stacks vorbereiten"
    PXE_STACK_REPO_ROOT="$repo_root" "$TFTP_ROOT/bin/pxe-prepare"
fi

systemctl enable --now dnsmasq nginx
systemctl restart dnsmasq nginx

echo
echo "PXE Basis installiert."
echo "  Stack : $STACK ${VARIANT:+($VARIANT)}"
echo "  TFTP  : $TFTP_ROOT"
echo "  HTTP  : http://${PXE_SERVER}/"
echo
"$TFTP_ROOT/bin/pxe-show"
