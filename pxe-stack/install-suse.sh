#!/usr/bin/env bash
set -Eeuo pipefail

# lernvirt PXE Add-on: SUSE / openSUSE Leap
#
# Voraussetzung:
#   pxe-stack/install-pxe.sh wurde bereits ausgeführt.
#
# Standard:
#   openSUSE Leap 15.6 DVD x86_64 wird automatisch von download.opensuse.org
#   heruntergeladen, per SHA256 geprüft und als HTTP-Installationsquelle
#   aufbereitet.
#
# Wichtige Overrides:
#   SUSE_VERSION=15.6
#   SUSE_ARCH=x86_64
#   SUSE_ISO=/pfad/zur.iso
#   SUSE_ISO_URL=https://server/image.iso
#   SUSE_SHA256=<sha256>
#   SUSE_SHA256_URL=https://server/image.iso.sha256
#   SUSE_FORCE=1
#   KEEP_ISO=1
#
# Beispiel:
#   curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-suse.sh | bash -

log()  { printf '[install-suse] %s\n' "$*"; }
warn() { printf '[install-suse] WARNUNG: %s\n' "$*" >&2; }
fail() { printf '[install-suse] FEHLER: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "install-suse.sh muss als root laufen."

CONFIG="${CONFIG:-/srv/tftp/config/rack.conf}"
[[ -r "$CONFIG" ]] || fail "PXE-Basis fehlt: $CONFIG. Zuerst install-pxe.sh ausführen."

# Environment-Werte sollen rack.conf übersteuern können.
ENV_TFTP_ROOT="${TFTP_ROOT-}"
ENV_HTTP_ROOT="${HTTP_ROOT-}"
ENV_CACHE_DIR="${PXE_CACHE_DIR-}"

# shellcheck disable=SC1090
source "$CONFIG"

[[ -n "$ENV_TFTP_ROOT" ]] && TFTP_ROOT="$ENV_TFTP_ROOT"
[[ -n "$ENV_HTTP_ROOT" ]] && HTTP_ROOT="$ENV_HTTP_ROOT"

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
PXE_CACHE_DIR="${ENV_CACHE_DIR:-${PXE_CACHE_DIR:-/var/cache/pxe-stack}}"

SUSE_VERSION="${SUSE_VERSION:-15.6}"
SUSE_ARCH="${SUSE_ARCH:-x86_64}"
SUSE_FORCE="${SUSE_FORCE:-0}"
KEEP_ISO="${KEEP_ISO:-0}"

# Optional vom Benutzer gesetzt. SUSE_ISO kann lokale Datei oder URL sein.
SUSE_ISO="${SUSE_ISO:-}"
SUSE_ISO_URL="${SUSE_ISO_URL:-}"
SUSE_SHA256="${SUSE_SHA256:-}"
SUSE_SHA256_URL="${SUSE_SHA256_URL:-}"

[[ -x "$TFTP_ROOT/bin/pxe-render" ]] || fail "pxe-render fehlt. Zuerst install-pxe.sh ausführen."
[[ -d "$TFTP_ROOT/grub/stacks" ]] || fail "GRUB-Stack-Verzeichnis fehlt: $TFTP_ROOT/grub/stacks"

case "$SUSE_ARCH" in
    x86_64|aarch64) ;;
    *) fail "Nicht unterstützte SUSE_ARCH: $SUSE_ARCH (unterstützt: x86_64, aarch64)" ;;
esac

# Nur wenn keine eigene Quelle angegeben wurde, wird die offizielle Leap-15.x-
# DVD automatisch verwendet. Leap 16 verwendet einen anderen Installer-Aufbau
# und soll deshalb explizit über SUSE_ISO_URL/SUSE_ISO eingebunden werden.
DEFAULT_SOURCE=0
if [[ -n "$SUSE_ISO" ]]; then
    ISO_SOURCE="$SUSE_ISO"
elif [[ -n "$SUSE_ISO_URL" ]]; then
    ISO_SOURCE="$SUSE_ISO_URL"
else
    if [[ "$SUSE_VERSION" != 15.* ]]; then
        fail "Für SUSE_VERSION=$SUSE_VERSION bitte SUSE_ISO_URL oder SUSE_ISO angeben."
    fi
    DEFAULT_SOURCE=1
    ISO_SOURCE="https://download.opensuse.org/distribution/leap/${SUSE_VERSION}/iso/openSUSE-Leap-${SUSE_VERSION}-DVD-${SUSE_ARCH}-Current.iso"
    SUSE_SHA256_URL="${ISO_SOURCE}.sha256"
fi

export DEBIAN_FRONTEND=noninteractive
missing=()
for cmd_pkg in "curl:curl" "rsync:rsync" "sha256sum:coreutils" "mount:mount"; do
    cmd="${cmd_pkg%%:*}"
    pkg="${cmd_pkg##*:}"
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$pkg")
done

if ((${#missing[@]})); then
    log "Installiere benötigte Pakete: ${missing[*]}"
    apt-get update -y
    apt-get install -y ca-certificates "${missing[@]}"
fi

mkdir -p \
    "$PXE_CACHE_DIR" \
    "$TFTP_ROOT/linux/suse" \
    "$TFTP_ROOT/grub/stacks" \
    "$HTTP_ROOT/linux/suse" \
    "$HTTP_ROOT/autoyast"

TMP="$(mktemp -d)"
MNT="$TMP/iso"
mkdir -p "$MNT"
MOUNTED=0

cleanup() {
    if [[ "$MOUNTED" == "1" ]] && mountpoint -q "$MNT"; then
        umount "$MNT" || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

# SHA256 bestimmen. Bei der offiziellen openSUSE-Quelle ist die Prüfung Pflicht.
EXPECTED_SHA256=""
if [[ -n "$SUSE_SHA256" ]]; then
    EXPECTED_SHA256="$(printf '%s' "$SUSE_SHA256" | tr '[:upper:]' '[:lower:]')"
elif [[ -n "$SUSE_SHA256_URL" ]]; then
    log "Lade SHA256-Prüfsumme"
    curl -fL --retry 5 --retry-delay 3 "$SUSE_SHA256_URL" -o "$TMP/image.sha256" \
        || fail "SHA256-Prüfsumme konnte nicht geladen werden: $SUSE_SHA256_URL"
    EXPECTED_SHA256="$(awk '$1 ~ /^[0-9A-Fa-f]{64}$/ {print tolower($1); exit}' "$TMP/image.sha256")"
    [[ -n "$EXPECTED_SHA256" ]] || fail "Keine gültige SHA256-Prüfsumme in $SUSE_SHA256_URL gefunden."
fi

HTTP_CURRENT="$HTTP_ROOT/linux/suse/current"
MARKER="$HTTP_CURRENT/.lernvirt-suse-source"
TFTP_KERNEL="$TFTP_ROOT/linux/suse/linux"
TFTP_INITRD="$TFTP_ROOT/linux/suse/initrd"

# Bereits korrekt aufbereitete Version nicht erneut als mehrere GiB herunterladen.
if [[ "$SUSE_FORCE" != "1" && -s "$TFTP_KERNEL" && -s "$TFTP_INITRD" && -d "$HTTP_CURRENT/boot" && -f "$MARKER" ]]; then
    marker_source="$(sed -n 's/^source=//p' "$MARKER" | head -n1)"
    marker_sha="$(sed -n 's/^sha256=//p' "$MARKER" | head -n1)"

    if [[ "$marker_source" == "$ISO_SOURCE" ]]; then
        if [[ -z "$EXPECTED_SHA256" || "$marker_sha" == "$EXPECTED_SHA256" ]]; then
            log "SUSE-Installationsquelle ist bereits vollständig aufbereitet."
            SKIP_PREPARE=1
        else
            SKIP_PREPARE=0
        fi
    else
        SKIP_PREPARE=0
    fi
else
    SKIP_PREPARE=0
fi

if [[ "$SKIP_PREPARE" != "1" ]]; then
    ISO_PATH=""
    DOWNLOADED_ISO=0

    case "$ISO_SOURCE" in
        http://*|https://*)
            DOWNLOADED_ISO=1
            ISO_CACHE="$PXE_CACHE_DIR/suse-${SUSE_VERSION}-${SUSE_ARCH}.iso"
            ISO_PART="${ISO_CACHE}.part"

            if [[ "$SUSE_FORCE" == "1" ]]; then
                rm -f "$ISO_CACHE" "$ISO_PART"
            fi

            # Vorhandenen Cache nur verwenden, wenn er die erwartete Prüfsumme hat.
            if [[ -s "$ISO_CACHE" && -n "$EXPECTED_SHA256" ]]; then
                actual="$(sha256sum "$ISO_CACHE" | awk '{print $1}')"
                if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
                    warn "Vorhandenes ISO hat eine falsche SHA256-Prüfsumme und wird neu geladen."
                    rm -f "$ISO_CACHE"
                fi
            fi

            if [[ ! -s "$ISO_CACHE" ]]; then
                log "Lade SUSE-Installationsimage:"
                log "  $ISO_SOURCE"
                curl -fL \
                    --retry 8 \
                    --retry-delay 5 \
                    --retry-all-errors \
                    --continue-at - \
                    "$ISO_SOURCE" \
                    -o "$ISO_PART"

                [[ -s "$ISO_PART" ]] || fail "ISO-Download ist leer."

                if [[ -n "$EXPECTED_SHA256" ]]; then
                    actual="$(sha256sum "$ISO_PART" | awk '{print $1}')"
                    [[ "$actual" == "$EXPECTED_SHA256" ]] || {
                        rm -f "$ISO_PART"
                        fail "SHA256-Prüfung des heruntergeladenen ISO fehlgeschlagen."
                    }
                fi

                mv -f "$ISO_PART" "$ISO_CACHE"
            fi

            ISO_PATH="$ISO_CACHE"
            ;;
        *)
            [[ -s "$ISO_SOURCE" ]] || fail "SUSE ISO nicht gefunden: $ISO_SOURCE"
            ISO_PATH="$ISO_SOURCE"
            ;;
    esac

    if [[ -n "$EXPECTED_SHA256" ]]; then
        actual="$(sha256sum "$ISO_PATH" | awk '{print $1}')"
        [[ "$actual" == "$EXPECTED_SHA256" ]] || fail "SHA256-Prüfung des ISO fehlgeschlagen."
    else
        actual="$(sha256sum "$ISO_PATH" | awk '{print $1}')"
        warn "Keine externe SHA256-Prüfsumme angegeben; verwende lokale Prüfsumme $actual."
    fi

    log "Mounte Installationsimage"
    mount -o loop,ro "$ISO_PATH" "$MNT"
    MOUNTED=1

    # Standardpfad von openSUSE Leap / SLES. Als Fallback wird im boot-Baum
    # nach einem loader-Verzeichnis gesucht, damit auch SLES-Medien funktionieren.
    LOADER_DIR="$MNT/boot/$SUSE_ARCH/loader"
    if [[ ! -s "$LOADER_DIR/linux" || ! -s "$LOADER_DIR/initrd" ]]; then
        kernel_candidate="$(find "$MNT/boot" -type f -path '*/loader/linux' -print -quit 2>/dev/null || true)"
        [[ -n "$kernel_candidate" ]] || fail "Kein SUSE-PXE-Kernel (*/loader/linux) im ISO gefunden."
        LOADER_DIR="$(dirname "$kernel_candidate")"
    fi

    [[ -s "$LOADER_DIR/linux" ]] || fail "SUSE PXE-Kernel fehlt: $LOADER_DIR/linux"
    [[ -s "$LOADER_DIR/initrd" ]] || fail "SUSE PXE-initrd fehlt: $LOADER_DIR/initrd"

    log "Installiere Kernel und initrd nach TFTP"
    install -m 0644 "$LOADER_DIR/linux" "$TFTP_KERNEL.new"
    install -m 0644 "$LOADER_DIR/initrd" "$TFTP_INITRD.new"
    mv -f "$TFTP_KERNEL.new" "$TFTP_KERNEL"
    mv -f "$TFTP_INITRD.new" "$TFTP_INITRD"

    log "Kopiere vollständigen SUSE-Installationsbaum nach $HTTP_CURRENT"
    mkdir -p "$HTTP_CURRENT"
    rsync -aH --delete --exclude='.lernvirt-suse-source' "$MNT/" "$HTTP_CURRENT/"

    cat > "$MARKER" <<MARKER_EOF
source=$ISO_SOURCE
sha256=$actual
version=$SUSE_VERSION
arch=$SUSE_ARCH
MARKER_EOF

    umount "$MNT"
    MOUNTED=0

    if [[ "$DOWNLOADED_ISO" == "1" && "$KEEP_ISO" != "1" ]]; then
        log "Entferne ISO-Cache (KEEP_ISO=1 würde ihn behalten)"
        rm -f "$ISO_PATH"
    fi
fi

# Der SUSE-Stack wird vom Add-on selbst installiert. Die Images sind bereits
# aufbereitet; pxe-prepare muss SUSE deshalb nicht speziell kennen.
cat > "$TFTP_ROOT/grub/stacks/suse.cfg" <<'GRUB_EOF'
if [ -z "${variant}" ]; then
    menuentry "Install SUSE" {
        linux /linux/suse/linux \
            netsetup=dhcp \
            install=http://${pxe_server}/linux/suse/current/
        initrd /linux/suse/initrd
    }
else
    menuentry "Install SUSE - AutoYaST ${variant}" {
        linux /linux/suse/linux \
            netsetup=dhcp \
            install=http://${pxe_server}/linux/suse/current/ \
            autoyast=http://${pxe_server}/autoyast/${variant}
        initrd /linux/suse/initrd
    }
fi
GRUB_EOF

chmod 0644 "$TFTP_ROOT/grub/stacks/suse.cfg"

# nginx-Konfiguration gehört zur PXE-Basis und wird hier nicht verändert.
if command -v nginx >/dev/null 2>&1; then
    nginx -t || fail "Bestehende nginx-Konfiguration ist ungültig."
fi

"$TFTP_ROOT/bin/pxe-render"

log "SUSE PXE Add-on bereit."
printf '  TFTP Kernel : %s\n' "$TFTP_KERNEL"
printf '  TFTP initrd : %s\n' "$TFTP_INITRD"
printf '  HTTP Source : http://%s/linux/suse/current/\n' "${PXE_SERVER:-<pxe-server>}"
printf '  AutoYaST    : %s/autoyast/<datei.xml>\n' "$HTTP_ROOT"
printf '\nStack in rack.conf verwenden, z.B.:\n'
printf '  HOSTS=( "*|suse|" )\n'
printf 'oder mit AutoYaST:\n'
printf '  HOSTS=( "*|suse|lab.xml" )\n'
