set -euo pipefail

export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig

PASS="$(openssl rand -base64 24 | tr -d '\n')"

podman pull registry.access.redhat.com/ubi9/httpd-24:latest >/dev/null

HASH="$(
  podman run --rm \
    --entrypoint /usr/bin/htpasswd \
    registry.access.redhat.com/ubi9/httpd-24:latest \
    -bnBC 10 "" "$PASS" |
    cut -d: -f2 |
    tr -d '\r\n'
)"

test -n "$HASH" || {
  echo "FEHLER: bcrypt-Hash konnte nicht erzeugt werden"
  exit 1
}

B64="$(printf '%s' "$HASH" | base64 -w0)"

oc patch secret kubeadmin -n kube-system \
  --type=merge \
  -p "{\"data\":{\"kubeadmin\":\"${B64}\"}}"

rm -f /tmp/kubeadmin.kubeconfig

KUBECONFIG=/tmp/kubeadmin.kubeconfig \
oc login \
  https://api.terra5.lernvirt.test:6443 \
  -u kubeadmin \
  -p "$PASS" \
  --insecure-skip-tls-verify=true

echo
echo "Kubeadmin Login erfolgreich"
echo "User:     kubeadmin"
echo "Password: $PASS"
echo "Console:  https://console-openshift-console.apps.terra5.lernvirt.test"