#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Lerncloud Setup Script für Ubuntu 24.x
# ============================================================
#
# Verwendung:
#   sudo bash ./lerncloud-setup.sh
#
# Einzelne Schritte deaktivieren:
#   sudo bash ./lerncloud-setup.sh --no-kubevirt
#   sudo bash ./lerncloud-setup.sh --no-kubevirt-patch --no-jupyter
#   sudo bash ./lerncloud-setup.sh --no-kubevirt --no-kubevirt-patch --no-xfce4 --no-vscode --no-cloud-cli --no-k8stools
#
# Nur anzeigen, was ausgeführt würde:
#   sudo bash ./lerncloud-setup.sh --dry-run
#
# Hilfe:
#   ./lerncloud-setup.sh --help
#
# ============================================================

SCRIPT_NAME="$(basename "$0")"

# Standard: alles aktiv
RUN_KUBEVIRT=true
RUN_KUBEVIRT_PATCH=true
RUN_JUPYTER=true
RUN_XFCE4=true
RUN_VSCODE=true
RUN_CLOUD_CLI=true
RUN_K8STOOLS=true
DRY_RUN=false

UBUNTU_USER="ubuntu"

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

err() {
  echo "[ERROR] $*" >&2
}

usage() {
  cat <<EOF
Verwendung:
  sudo ./$SCRIPT_NAME [OPTIONEN]

Optionen:
  --no-kubevirt         kubevirt.sh nicht ausführen
  --no-kubevirt-patch   KubeVirt Patch nicht ausführen
  --no-jupyter          jupyter-lab.sh nicht ausführen
  --no-xfce4            xfce4.sh nicht ausführen
  --no-vscode           vscode.sh nicht ausführen
  --no-cloud-cli        cloud-cli.sh nicht ausführen
  --no-k8stools         k8stools.sh nicht ausführen
  --dry-run             nur anzeigen, was ausgeführt würde
  -h, --help            Hilfe anzeigen

Beispiel:
  sudo ./$SCRIPT_NAME --no-xfce4 --no-vscode
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Dieses Script muss als root ausgeführt werden."
    err "Beispiel: sudo ./$SCRIPT_NAME"
    exit 1
  fi
}

require_user() {
  if ! id "$UBUNTU_USER" >/dev/null 2>&1; then
    err "Benutzer '$UBUNTU_USER' existiert nicht."
    exit 1
  fi
}

run_cmd() {
  local description="$1"
  shift

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] $description"
    echo "          $*"
    return 0
  fi

  log "$description"
  "$@"
}

run_as_ubuntu() {
  local description="$1"
  local command="$2"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] $description"
    echo "          sudo su - $UBUNTU_USER -c \"$command\""
    return 0
  fi

  log "$description"
  sudo su - "$UBUNTU_USER" -c "$command"
}
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-kubevirt)
        RUN_KUBEVIRT=false
        ;;
      --no-kubevirt-patch)
        RUN_KUBEVIRT_PATCH=false
        ;;
      --no-jupyter)
        RUN_JUPYTER=false
        ;;
      --no-xfce4)
        RUN_XFCE4=false
        ;;
      --no-vscode)
        RUN_VSCODE=false
        ;;
      --no-cloud-cli)
        RUN_CLOUD_CLI=false
        ;;
      --no-k8stools)
        RUN_K8STOOLS=false
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unbekannte Option: $1"
        echo
        usage
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_root
  require_user

  log "Starte Setup"
  log "Benutzer für User-Kommandos: $UBUNTU_USER"

  if [[ "$RUN_KUBEVIRT" == true ]]; then
    run_as_ubuntu \
      "Installiere KubeVirt" \
      "curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/kubevirt.sh | bash -"
  else
    warn "Überspringe KubeVirt"
  fi

  if [[ "$RUN_KUBEVIRT_PATCH" == true ]]; then
    run_as_ubuntu \
      "Patche KubeVirt: developerConfiguration.useEmulation=false" \
      "kubectl -n kubevirt patch kubevirt kubevirt --type=merge --patch '{\"spec\":{\"configuration\":{\"developerConfiguration\":{\"useEmulation\":false}}}}'"
  else
    warn "Überspringe KubeVirt Patch"
  fi

  if [[ "$RUN_JUPYTER" == true ]]; then
    run_as_ubuntu \
      "Installiere JupyterLab" \
      "curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/jupyter-lab.sh | bash -"
  else
    warn "Überspringe JupyterLab"
  fi

  if [[ "$RUN_XFCE4" == true ]]; then
    run_cmd \
      "Installiere XFCE4" \
      bash -lc 'curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/xfce4.sh | bash -'
  else
    warn "Überspringe XFCE4"
  fi

  if [[ "$RUN_VSCODE" == true ]]; then
    run_cmd \
      "Installiere VS Code" \
      bash -lc 'curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/vscode.sh | bash -'
  else
    warn "Überspringe VS Code"
  fi

  if [[ "$RUN_CLOUD_CLI" == true ]]; then
    run_cmd \
      "Installiere Cloud CLI" \
      bash -lc 'curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/cloud-cli.sh | bash -'
  else
    warn "Überspringe Cloud CLI"
  fi

  if [[ "$RUN_K8STOOLS" == true ]]; then
    run_cmd \
      "Installiere Kubernetes Tools" \
      bash -lc 'curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/k8stools.sh | bash -'
  else
    warn "Überspringe Kubernetes Tools"
  fi

  log "Setup abgeschlossen"
}

main "$@"