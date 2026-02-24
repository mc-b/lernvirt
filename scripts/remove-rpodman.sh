#!/usr/bin/env bash
set -euo pipefail

USER="rpodman"
RSHELL="/usr/local/bin/rpodman-rbash"
RBIN_BASE="/usr/local/rpodman"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Fehler: Bitte als root ausführen (z.B. sudo $0)." >&2
    exit 1
  fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }
have_user() { id "$USER" >/dev/null 2>&1; }

get_user_uid_home() {
  local line uid home
  line="$(getent passwd "$USER" || true)"
  [[ -n "$line" ]] || return 1
  uid="$(awk -F: '{print $3}' <<<"$line")"
  home="$(awk -F: '{print $6}' <<<"$line")"
  printf "%s %s\n" "$uid" "$home"
}

rootless_cleanup_only() {
  local uid="$1" home="$2"

  if cmd_exists podman; then
    # Rootless Podman aufräumen (nur für diesen User)
    sudo -u "$USER" env \
      XDG_RUNTIME_DIR="/run/user/${uid}" \
      HOME="${home}" \
      podman stop -a >/dev/null 2>&1 || true

    sudo -u "$USER" env \
      XDG_RUNTIME_DIR="/run/user/${uid}" \
      HOME="${home}" \
      podman rm -a -f >/dev/null 2>&1 || true

    # Löscht ALLE rootless Volumes dieses Users (aber keine systemweiten rootful Volumes)
    sudo -u "$USER" env \
      XDG_RUNTIME_DIR="/run/user/${uid}" \
      HOME="${home}" \
      podman volume rm -a >/dev/null 2>&1 || true

    # Optional: härterer Reset nur im rootless Kontext des Users
    sudo -u "$USER" env \
      XDG_RUNTIME_DIR="/run/user/${uid}" \
      HOME="${home}" \
      podman system reset -f >/dev/null 2>&1 || true
  fi

  # Rootless Storage-Verzeichnisse des Users entfernen (nur dessen Home)
  rm -rf "${home}/.local/share/containers" 2>/dev/null || true
  rm -rf "${home}/.cache/containers" 2>/dev/null || true
  rm -rf "${home}/.config/containers" 2>/dev/null || true
  rm -rf "/run/user/${uid}/containers" 2>/dev/null || true
}

kill_user_procs() {
  pkill -u "$USER" >/dev/null 2>&1 || true
}

remove_user_and_local_artifacts() {
  # User löschen
  userdel -r "$USER" >/dev/null 2>&1 || userdel "$USER" >/dev/null 2>&1 || true

  # subordinate IDs entfernen (falls vorhanden)
  [[ -f /etc/subuid ]] && sed -i "/^${USER}:/d" /etc/subuid || true
  [[ -f /etc/subgid ]] && sed -i "/^${USER}:/d" /etc/subgid || true

  # lokale Artefakte
  rm -rf "$RBIN_BASE" || true
  rm -f "$RSHELL" || true
  [[ -f /etc/shells ]] && sed -i "\|^${RSHELL}$|d" /etc/shells || true
}

main() {
  need_root

  if ! have_user; then
    # Wenn der User schon weg ist: nur noch lokale Artefakte entfernen.
    rm -rf "$RBIN_BASE" || true
    rm -f "$RSHELL" || true
    [[ -f /etc/shells ]] && sed -i "\|^${RSHELL}$|d" /etc/shells || true
    echo "OK: '$USER' existiert nicht mehr; Artefakte entfernt (best effort)."
    exit 0
  fi

  local uid home
  read -r uid home < <(get_user_uid_home)

  rootless_cleanup_only "$uid" "$home"
  kill_user_procs
  remove_user_and_local_artifacts

  echo "OK: '$USER' (rootless) Container/Volumes/Storage entfernt; systemweite rootful Volumes bleiben erhalten."
}

main "$@"