#!/usr/bin/env bash
set -euo pipefail

USER="rpodman"
RBIN_DIR="/usr/local/rpodman/rbin"
RSHELL="/usr/local/bin/rpodman-rbash"
SHELLS_FILE="/etc/shells"
HOME_DIR="/home/${USER}"
CONTAINERS_CONF_DIR="${HOME_DIR}/.config/containers"
CONTAINERS_CONF_FILE="${CONTAINERS_CONF_DIR}/containers.conf"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
PUBKEY_URL="https://raw.githubusercontent.com/mc-b/lerncloud/refs/heads/main/ssh/lerncloud.pub"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Fehler: Bitte als root ausführen (z.B. sudo $0)." >&2
    exit 1
  fi
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "Fehler: Kommando fehlt: $c" >&2
      exit 1
    }
  done
}

ensure_user() {
  if ! id "$USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$USER"
  fi
}

ensure_rbin() {
  install -d -m 0755 -o root -g root "$RBIN_DIR"
}

ensure_link_if_exec() {
  local src="$1" dst="$2"
  if [[ -x "$src" ]]; then
    ln -sf "$src" "$dst"
  fi
}

ensure_links() {
  ensure_link_if_exec /usr/bin/podman      "$RBIN_DIR/podman"
  ensure_link_if_exec /usr/bin/newuidmap   "$RBIN_DIR/newuidmap"
  ensure_link_if_exec /usr/bin/newgidmap   "$RBIN_DIR/newgidmap"
  ensure_link_if_exec /usr/bin/slirp4netns "$RBIN_DIR/slirp4netns"

  # NVIDIA-Tools – still überspringen, falls nicht vorhanden
  ensure_link_if_exec /usr/bin/nvidia-ctk  "$RBIN_DIR/nvidia-ctk"
  ensure_link_if_exec /usr/bin/nvidia-smi  "$RBIN_DIR/nvidia-smi"

  ensure_link_if_exec /usr/bin/id          "$RBIN_DIR/id"
  ensure_link_if_exec /usr/bin/watch       "$RBIN_DIR/watch"
  ensure_link_if_exec /usr/bin/ls          "$RBIN_DIR/ls"
  ensure_link_if_exec /usr/bin/cat         "$RBIN_DIR/cat"
  ensure_link_if_exec /usr/bin/curl        "$RBIN_DIR/curl"
  ensure_link_if_exec /usr/bin/wget        "$RBIN_DIR/wget"
}

write_rbash() {
  cat >"$RSHELL" <<'EOF'
#!/bin/bash
set -euo pipefail

uid=$(/usr/bin/id -u)
export XDG_RUNTIME_DIR="/run/user/$uid"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

export PATH="/usr/local/rpodman/rbin"
export HOME="/home/rpodman"
cd "$HOME" || exit 1

# --- Banner / MOTD ---
/usr/bin/clear 2>/dev/null || true

echo "============================================================"
echo "  rpodman Container-Sandbox"
echo "============================================================"

# Hostname
if [[ -r /etc/hostname ]]; then
  printf "Hostname:        %s\n" "$(/usr/bin/cat /etc/hostname)"
fi

# Ubuntu Version
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  printf "Betriebssystem:  %s %s\n" "${NAME:-}" "${VERSION:-}"
fi

echo
echo "Verfügbare Befehle:"
if [[ -d /usr/local/rpodman/rbin ]]; then
  /usr/bin/ls -1 /usr/local/rpodman/rbin | /usr/bin/sort
fi

echo
echo "------------------------------------------------------------"
echo "Hinweis:"
echo "Dieses System ist eine kontrollierte Container-Umgebung."
echo "Jegliche Versuche, Sicherheitsmechanismen zu umgehen,"
echo "Host-Zugriffe zu erzwingen oder das System zu manipulieren,"
echo "sind strikt untersagt und werden protokolliert."
echo "------------------------------------------------------------"
echo

# Username & Hostname holen
user="$(/usr/bin/id -un)"
host="$(/bin/hostname -s 2>/dev/null || /bin/hostname 2>/dev/null || echo unknown)"

# Prompt setzen (z.B. user@host:rpodman$)
# \w = aktuelles Verzeichnis
export PS1="[$user@$host \w]$ "

exec /bin/bash --restricted --noprofile --norc -i
EOF

  chmod 0755 "$RSHELL"
  chown root:root "$RSHELL"
}

ensure_shells_entry() {
  grep -Fxq "$RSHELL" "$SHELLS_FILE" || echo "$RSHELL" >>"$SHELLS_FILE"
}

ensure_user_shell() {
  local current_shell
  current_shell="$(getent passwd "$USER" | awk -F: '{print $7}')"
  [[ "$current_shell" == "$RSHELL" ]] || usermod -s "$RSHELL" "$USER"
}

ensure_containers_conf() {
  install -d -m 0700 -o "$USER" -g "$USER" "$CONTAINERS_CONF_DIR"

  local desired=$'[engine]\ncgroup_manager = "cgroupfs"\n\n[containers]\nuserns = "auto"\n'

  if [[ ! -f "$CONTAINERS_CONF_FILE" ]] || ! cmp -s <(printf "%s" "$desired") "$CONTAINERS_CONF_FILE"; then
    printf "%s" "$desired" >"$CONTAINERS_CONF_FILE"
    chown "$USER:$USER" "$CONTAINERS_CONF_FILE"
    chmod 0600 "$CONTAINERS_CONF_FILE"
  fi
}

ensure_ssh_key() {
  require_cmd curl

  install -d -m 0700 -o "$USER" -g "$USER" "$SSH_DIR"

  local tmpkey=""
  tmpkey="$(mktemp)"
  trap '[[ -n "${tmpkey:-}" ]] && rm -f "$tmpkey"' RETURN

  curl -fsSL "$PUBKEY_URL" -o "$tmpkey"

  [[ -f "$AUTH_KEYS" ]] || install -m 0600 -o "$USER" -g "$USER" /dev/null "$AUTH_KEYS"

  if ! grep -Fqx "$(cat "$tmpkey")" "$AUTH_KEYS"; then
    cat "$tmpkey" >>"$AUTH_KEYS"
    # optional: newline sicherstellen
    tail -c 1 "$AUTH_KEYS" | read -r _ || echo >>"$AUTH_KEYS"
  fi

  chown "$USER:$USER" "$AUTH_KEYS"
  chmod 0600 "$AUTH_KEYS"
}

main() {
  need_root
  require_cmd adduser ln install usermod getent awk grep cmp chmod chown

  ensure_user
  ensure_rbin
  ensure_links
  write_rbash
  ensure_shells_entry
  ensure_user_shell
  ensure_containers_conf
  ensure_ssh_key
}

main "$@"