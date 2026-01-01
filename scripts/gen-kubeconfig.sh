#!/bin/bash
set -euo pipefail

########################################
# Parameter & Validierung
########################################

if [ -z "${1:-}" ]; then
  echo "Fehler: Bitte gib das Kuerzel der Lehrperson an, z.B.:"
  echo "  $0 ALP"
  exit 1
fi

LP_RAW="$1"
LP_LOWER=$(echo "$LP_RAW" | tr '[:upper:]' '[:lower:]')

SA_NAME="te-${LP_LOWER}"
SA_NAMESPACE="kube-system"
BINDING_NAME="${SA_NAME}-admin"

CLUSTER_NAME="lerncluster"
USER_NAME="te-${LP_LOWER}-user"
CONTEXT_NAME="te-${LP_LOWER}-context"
KUBECONFIG_FILE="${LP_RAW}-kubeconfig.yaml"

########################################
# Cleanup bei Abbruch
########################################

TMP_CA_FILE=$(mktemp)
cleanup() {
  rm -f "$TMP_CA_FILE"
}
trap cleanup EXIT

########################################
# ServiceAccount erstellen
########################################

echo "▶ Erstelle ServiceAccount '${SA_NAME}'..."
kubectl get serviceaccount "${SA_NAME}" -n "${SA_NAMESPACE}" >/dev/null 2>&1 || \
kubectl create serviceaccount "${SA_NAME}" -n "${SA_NAMESPACE}"

########################################
# ClusterRoleBinding
########################################

echo "▶ Stelle ClusterRoleBinding sicher..."
kubectl get clusterrolebinding "${BINDING_NAME}" >/dev/null 2>&1 || \
kubectl create clusterrolebinding "${BINDING_NAME}" \
  --clusterrole=cluster-admin \
  --serviceaccount="${SA_NAMESPACE}:${SA_NAME}"

########################################
# Token erzeugen
########################################

echo "▶ Erzeuge Token..."
TOKEN=$(kubectl create token "${SA_NAME}" -n "${SA_NAMESPACE}")

########################################
# API Server
########################################

APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

########################################
# CA temporär extrahieren
########################################

echo "▶ Extrahiere CA-Zertifikat (temporär)..."
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > "$TMP_CA_FILE"

########################################
# kubeconfig erstellen
########################################

echo "▶ Erstelle kubeconfig: ${KUBECONFIG_FILE}"

kubectl config set-cluster "${CLUSTER_NAME}" \
  --server="${APISERVER}" \
  --certificate-authority="$TMP_CA_FILE" \
  --embed-certs=true \
  --kubeconfig="${KUBECONFIG_FILE}"

kubectl config set-credentials "${USER_NAME}" \
  --token="${TOKEN}" \
  --kubeconfig="${KUBECONFIG_FILE}"

kubectl config set-context "${CONTEXT_NAME}" \
  --cluster="${CLUSTER_NAME}" \
  --user="${USER_NAME}" \
  --kubeconfig="${KUBECONFIG_FILE}"

kubectl config use-context "${CONTEXT_NAME}" \
  --kubeconfig="${KUBECONFIG_FILE}"

########################################
# Abschluss
########################################

echo ""
echo "✅ Fertig"
echo "➡ kubeconfig Datei: ${KUBECONFIG_FILE}"
echo "➡ Test:"
echo "   KUBECONFIG=${KUBECONFIG_FILE} kubectl auth whoami"
