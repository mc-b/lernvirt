#!/usr/bin/env bash
set -euo pipefail

# Entfernt den User rpodman inkl. Podman-Objekte und Artefakte.
# Idempotent: kann mehrfach laufen.

USER="rpodman"
RSHELL="/usr/local/bin/rpodman-rbash"
RBIN_BASE="/usr/local/rpodman"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Fehler: Bitte als root ausführen (z.B. sudo $0)." >&2
    exit 1
  fi
}

have_user() {
  id "$USER" >/dev/null 2>&1
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

cleanup_podman_rootless() {
  # Nur wenn User existiert und podman vorhanden ist.
  if ! have_user; then
    return 0
  fi
  if ! cmd_exists podman; then
    return 0
  fi

  # Podman-Objekte als rpodman entfernen (best effort).
  sudo -u "$USER" podman stop -a >/dev/null 2>&1 || true
  sudo -u "$USER" podman rm -a >/dev/null 2>&1 || true
  sudo -u "$USER" podman volume rm -a >/dev/null 2>&1 || true
}

kill_user_procs() {
  if ! have_user; then
    return 0
  fi

  # Prozesse beenden (best effort).
  if cmd_exists pkill; then
    pkill -u "$USER" >/dev/null 2>&1 || true
  fi
}

remove_user() {
  if have_user; then
    userdel -r "$USER" >/dev/null 2>&1 || userdel "$USER" >/dev/null 2>&1 || true
  fi
}

remove_subids() {
  # subordinate IDs entfernen, falls vorhanden
  if [[ -f /etc/subuid ]]; then
    sed -i "/^${USER}:/d" /etc/subuid
  fi
  if [[ -f /etc/subgid ]]; then
    sed -i "/^${USER}:/d" /etc/subgid
  fi
}

remove_local_artifacts() {
  rm -rf "$RBIN_BASE" || true
  rm -f "$RSHELL" || true

  # Shell aus /etc/shells entfernen
  if [[ -f /etc/shells ]]; then
    sed -i "\|^${RSHELL}$|d" /etc/shells || true
  fi
}

remove_runtime_dir() {
  # Optional: /run/user/<uid> entfernen, falls es noch existiert und eindeutig ist.
  # Wir ermitteln die UID aus dem (ggf. noch vorhandenen) Home/Passwd-Eintrag nicht mehr, da User weg ist.
  # Daher nur „best effort“ für den Standardpfad /run/user/1002, aber NUR wenn leer/ungefährlich.
  # Empfehlung: lieber weglassen, ausser du bist sicher.
  :
}

main() {
  need_root

  cleanup_podman_rootless
  kill_user_procs
  remove_user
  remove_subids
  remove_local_artifacts

  echo "OK: '$USER' entfernt (sofern vorhanden)."
}

main "$@"