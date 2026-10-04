#!/usr/bin/env bash
set -Eeuo pipefail

HELM_VERSION="${HELM_VERSION:-v3.22.0}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.2}"
RANCHER_VERSION="${RANCHER_VERSION:-2.15.2}"
RANCHER_HOST="${RANCHER_HOST:-}"
RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:-insecure}"
KUBECONFIG="${KUBECONFIG:-/etc/rancher/rke2/rke2.yaml}"
KUBECTL="/var/lib/rancher/rke2/bin/kubectl"
HELM="/opt/rke2/bin/helm"

log() { printf '[install-rancher] %s\n' "$*"; }
fail() { printf '[install-rancher] FEHLER: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Script muss als root laufen."
[[ -x "$KUBECTL" ]] || fail "RKE2 kubectl fehlt: $KUBECTL"
[[ -s "$KUBECONFIG" ]] || fail "RKE2 kubeconfig fehlt: $KUBECONFIG"
[[ "$HELM_VERSION" =~ ^v3\.[0-9]+\.[0-9]+$ ]] || fail "Ungültige HELM_VERSION: $HELM_VERSION"
[[ "$CERT_MANAGER_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Ungültige CERT_MANAGER_VERSION: $CERT_MANAGER_VERSION"
[[ "$RANCHER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Ungültige RANCHER_VERSION: $RANCHER_VERSION"

export KUBECONFIG
export PATH="/opt/rke2/bin:/var/lib/rancher/rke2/bin:$PATH"

"$KUBECTL" get nodes --no-headers | awk '$2 == "Ready" {found=1} END {exit !found}' || fail "RKE2 Node ist nicht Ready."

zypper --non-interactive --gpg-auto-import-keys refresh || true
zypper --non-interactive install --no-recommends curl ca-certificates tar gzip || \
  zypper --non-interactive install curl ca-certificates tar gzip

NODE_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
[[ -n "$NODE_IP" ]] || NODE_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$NODE_IP" ]] || fail "Keine primäre IPv4-Adresse gefunden."
[[ -n "$RANCHER_HOST" ]] || RANCHER_HOST="${NODE_IP}.sslip.io"

if [[ ! -x "$HELM" ]]; then
  case "$(uname -m)" in
    x86_64) HELM_ARCH=amd64 ;;
    aarch64|arm64) HELM_ARCH=arm64 ;;
    *) fail "Nicht unterstützte Architektur: $(uname -m)" ;;
  esac
  mkdir -p /opt/rke2/bin
  HELM_TGZ="/tmp/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
  HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
  log "Installiere Helm $HELM_VERSION"
  curl -fL --retry 5 --retry-delay 3 "$HELM_URL" -o "$HELM_TGZ"
  expected="$(curl -fsSL "${HELM_URL}.sha256sum" | awk '{print $1}')"
  actual="$(sha256sum "$HELM_TGZ" | awk '{print $1}')"
  [[ -n "$expected" && "$actual" == "$expected" ]] || fail "Helm SHA256-Prüfung fehlgeschlagen."
  rm -rf "/tmp/linux-${HELM_ARCH}"
  tar -xzf "$HELM_TGZ" -C /tmp
  install -m 0755 "/tmp/linux-${HELM_ARCH}/helm" "$HELM"
fi
ln -sfn "$HELM" /usr/local/bin/helm
ln -sfn "$KUBECTL" /usr/local/bin/kubectl

cat >/etc/profile.d/rke2.sh <<'PROFILE_EOF'
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=/opt/rke2/bin:/var/lib/rancher/rke2/bin:$PATH
PROFILE_EOF
chmod 0644 /etc/profile.d/rke2.sh

log "Helm: $($HELM version --short)"
"$HELM" repo add jetstack https://charts.jetstack.io --force-update
"$HELM" repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update
"$HELM" repo update

log "Installiere/aktualisiere cert-manager $CERT_MANAGER_VERSION"
"$HELM" upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true \
  --wait \
  --timeout 15m

"$KUBECTL" create namespace cattle-system --dry-run=client -o yaml | "$KUBECTL" apply -f -

RANCHER_HOST_YAML="$(printf '%s' "$RANCHER_HOST" | sed "s/'/''/g")"
RANCHER_PASSWORD_YAML="$(printf '%s' "$RANCHER_BOOTSTRAP_PASSWORD" | sed "s/'/''/g")"
cat >/tmp/rancher-values.yaml <<RANCHER_VALUES
hostname: '$RANCHER_HOST_YAML'
replicas: 1
bootstrapPassword: '$RANCHER_PASSWORD_YAML'
RANCHER_VALUES

log "Installiere/aktualisiere Rancher $RANCHER_VERSION"
"$HELM" upgrade --install rancher rancher-latest/rancher \
    --namespace cattle-system \
    --version "$RANCHER_VERSION" \
    -f /tmp/rancher-values.yaml \
    --wait \
    --timeout 20m

"$KUBECTL" -n cattle-system rollout status deployment/rancher --timeout=1200s

cat >/root/rancher-access.txt <<RANCHER_ACCESS
Rancher URL: https://$RANCHER_HOST
Benutzer: admin
Bootstrap-Passwort: $RANCHER_BOOTSTRAP_PASSWORD
RANCHER_ACCESS
chmod 0600 /root/rancher-access.txt

touch /var/lib/lernvirt/helm-ready /var/lib/lernvirt/rancher-ready 2>/dev/null || true

printf '\nHelm:\n'
"$HELM" version --short
printf '\nRancher:\n  https://%s\n  Zugangsdaten: /root/rancher-access.txt\n\n' "$RANCHER_HOST"
"$KUBECTL" get pods -n cert-manager
"$KUBECTL" get pods -n cattle-system
