#!/usr/bin/env bash
set -euo pipefail

# Entfernt den User rpodman inkl. dessen ROOTLESS Podman-Container/Volumes/Storage
# und löscht Home-Verzeichnis. Systemweite (rootful) Podman-Volumes bleiben unangetastet.
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

rootless_podman_cleanup() {
  local uid="$1" home="$2"

  if ! cmd_exists podman; then
    return 0
  fi

  # Rootless Podman für diesen User aufräumen (best effort).
  sudo -u "$USER" env \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    HOME="${home}" \
    podman stop -a >/dev/null 2>&1 || true

  sudo -u "$USER" env \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    HOME="${home}" \
    podman rm -a -f >/dev/null 2>&1 || true

  # Löscht alle rootless Volumes dieses Users (aber keine systemweiten rootful Volumes)
  sudo -u "$USER" env \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    HOME="${home}" \
    podman volume rm -a >/dev/null 2>&1 || true

  # Optional: entfernt Images/Netzwerke/etc. nur im rootless Kontext dieses Users
  sudo -u "$USER" env \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    HOME="${home}" \
    podman system reset -f >/dev/null 2>&1 || true
}

remove_rootless_storage_dirs() {
  local uid="$1" home="$2"

  rm -rf "${home}/.local/share/containers" 2>/dev/null || true
  rm -rf "${home}/.cache/containers" 2>/dev/null || true
  rm -rf "${home}/.config/containers" 2>/dev/null || true
  rm -rf "/run/user/${uid}/containers" 2>/dev/null || true
}

kill_user_procs() {
  # best effort
  if cmd_exists pkill; then
    pkill -u "$USER" >/dev/null 2>&1 || true
  fi
}

remove_user_and_home() {
  # userdel -r löscht Home + Mailspool, falls möglich
  if cmd_exists userdel; then
    userdel -r "$USER" >/dev/null 2>&1 || userdel "$USER" >/dev/null 2>&1 || true
  fi
}

remove_subids() {
  [[ -f /etc/subuid ]] && sed -i "/^${USER}:/d" /etc/subuid || true
  [[ -f /etc/subgid ]] && sed -i "/^${USER}:/d" /etc/subgid || true
}

remove_local_artifacts() {
  rm -rf "$RBIN_BASE" 2>/dev/null || true
  rm -f "$RSHELL" 2>/dev/null || true
  [[ -f /etc/shells ]] && sed -i "\|^${RSHELL}$|d" /etc/shells || true
}

main() {
  need_root

  if have_user; then
    local uid home
    read -r uid home < <(get_user_uid_home)

    # 1) Rootless Podman des Users entfernen
    rootless_podman_cleanup "$uid" "$home"

    # 2) Prozesse beenden
    kill_user_procs

    # 3) Rootless Storage-Verzeichnisse entfernen (falls noch vorhanden)
    remove_rootless_storage_dirs "$uid" "$home"

    # 4) User + Home löschen
    remove_user_and_home

    # Falls Home aus irgendeinem Grund stehen bleibt: hart entfernen
    rm -rf "$home" 2>/dev/null || true
  else
    # User existiert nicht mehr – kein rootless Cleanup möglich
    :
  fi

  # 5) Subuid/Subgid aufräumen + lokale Artefakte entfernen
  remove_subids
  remove_local_artifacts

  echo "OK: '$USER' inkl. Home und rootless Podman-Container/Volumes/Storage entfernt. Rootful Podman bleibt unverändert."
}

main "$@"