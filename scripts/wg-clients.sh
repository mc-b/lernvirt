#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 add    --fullname NAME --endpoint HOSTNAME_OR_IP [--namespace NS] [--wg-net CIDR] --count N [--start-id ID] [--output-dir DIR]
  $0 delete --fullname NAME [--namespace NS] FROM_ID TO_ID

Beispiele:
  # 5 neue Clients erzeugen, IDs automatisch fortlaufend, Konfigs nach ./out exportieren
  $0 add --fullname m122-lernvirt --endpoint vpn.example.com --count 5 --output-dir ./out

  # Clients 101 bis 120 löschen (inklusive)
  $0 delete --fullname m122-lernvirt 101 120

Parameter:
  add:
    --fullname NAME       Prefix der Ressourcen, z.B. Helm-FULLNAME (wie im Gateway)
    --endpoint HOST       Öffentlicher Endpoint des Gateways (DNS oder IP)
    --namespace, -n NS    Namespace (Standard: default)
    --wg-net CIDR         WG Netz (Standard: 10.10.0.0/24)
    --count N             Anzahl neuer Clients
    --start-id ID         Erste Host-ID (optional, sonst automatisch ermittelt)
    --output-dir DIR      Verzeichnis, in das wg0.conf-Dateien geschrieben werden

  delete:
    --fullname NAME       Prefix der Ressourcen
    --namespace, -n NS    Namespace (Standard: default)
    FROM_ID TO_ID         Von-/bis-ID (inkl.), z.B. 101 120
EOF
}

ACTION=""
FULLNAME=""
NS="default"
WG_NET="10.10.0.0/24"
ENDPOINT=""
COUNT=0
START_ID=""
OUTPUT_DIR=""
DELETE_FROM=""
DELETE_TO=""

# Argumente parsen
while [[ $# -gt 0 ]]; do
  case "$1" in
    add|delete)
      ACTION="$1"
      ;;
    --fullname)
      FULLNAME="$2"; shift
      ;;
    --namespace|-n)
      NS="$2"; shift
      ;;
    --endpoint)
      ENDPOINT="$2"; shift
      ;;
    --wg-net)
      WG_NET="$2"; shift
      ;;
    --count)
      COUNT="$2"; shift
      ;;
    --start-id)
      START_ID="$2"; shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"; shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unbekannte Option: $1" >&2
      usage
      exit 1
      ;;
    *)
      # erster nicht-Option-Parameter (für delete: FROM_ID)
      break
      ;;
  esac
  shift
done

# Restliche Argumente für delete: FROM_ID TO_ID
if [[ "$ACTION" == "delete" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "Fehlende FROM_ID / TO_ID fuer delete." >&2
    usage
    exit 1
  fi
  DELETE_FROM="$1"
  DELETE_TO="$2"
fi

if [[ -z "$ACTION" ]]; then
  echo "Aktion add oder delete angeben." >&2
  usage
  exit 1
fi

if [[ -z "$FULLNAME" ]]; then
  echo "--fullname ist erforderlich." >&2
  exit 1
fi

# Basis-Abhaengigkeiten pruefen
for cmd in kubectl wg base64 sed sort; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Benoetigtes Kommando '$cmd' ist nicht im PATH." >&2
    exit 1
  fi
done

GW_PUB=""
WG_PORT=""

wait_for_gateway_pub() {
  echo "Warte auf Secret ${FULLNAME}-gateway-pub in Namespace ${NS} ..."
  while true; do
    if kubectl get secret "${FULLNAME}-gateway-pub" -n "$NS" >/dev/null 2>&1; then
      GW_PUB="$(kubectl get secret "${FULLNAME}-gateway-pub" -n "$NS" \
        -o jsonpath='{.data.publickey}' | base64 -d || true)"
      if [[ -n "$GW_PUB" ]]; then
        break
      fi
    fi
    sleep 2
  done
  echo "Gateway PublicKey geladen."
}

wait_for_gateway_service() {
  echo "Warte auf Service ${FULLNAME}-gateway in Namespace ${NS} ..."
  while true; do
    if kubectl get svc "${FULLNAME}-gateway" -n "$NS" >/dev/null 2>&1; then
      WG_PORT="$(kubectl get svc "${FULLNAME}-gateway" -n "$NS" \
        -o jsonpath='{.spec.ports[?(@.port==51820)].nodePort}')"
      if [[ -n "$WG_PORT" ]]; then
        break
      fi
    fi
    sleep 2
  done
  echo "Gateway Port: ${WG_PORT}"
}

next_free_id() {
  local max_id
  max_id="$(kubectl get secrets -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | sed -n "s/^${FULLNAME}-client-\([0-9][0-9]*\)\$/\1/p" \
    | sort -n \
    | tail -n1 || true)"
  if [[ -z "$max_id" ]]; then
    # Falls noch keine Clients existieren, hier Default-Start-ID setzen
    echo 2
  else
    echo $((max_id + 1))
  fi
}

add_clients() {
  if [[ "$COUNT" -le 0 ]]; then
    echo "--count muss > 0 sein." >&2
    exit 1
  fi
  if [[ -z "$ENDPOINT" ]]; then
    echo "--endpoint ist erforderlich." >&2
    exit 1
  fi

  wait_for_gateway_pub
  wait_for_gateway_service

  local start_id
  if [[ -n "$START_ID" ]]; then
    start_id="$START_ID"
  else
    start_id="$(next_free_id)"
  fi

  echo "Erzeuge ${COUNT} Clients ab Host-ID ${start_id} ..."

  if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
  fi

  for ((i=0; i<COUNT; i++)); do
    local host_id=$((start_id + i))
    local secret_name="${FULLNAME}-client-${host_id}"
    local client_ip="10.10.0.${host_id}/32"

    if kubectl get secret "$secret_name" -n "$NS" >/dev/null 2>&1; then
      echo "Secret ${secret_name} existiert bereits – ueberspringe."
      continue
    fi

    echo "Erzeuge Client ${host_id} (${secret_name}) ..."

    umask 077
    local client_priv client_pub
    client_priv="$(wg genkey)"
    client_pub="$(printf "%s" "$client_priv" | wg pubkey)"

    local tmp_conf="/tmp/wg0-${host_id}.conf"

    cat > "$tmp_conf" <<EOF
[Interface]
PrivateKey = ${client_priv}
Address = ${client_ip}

[Peer]
PublicKey = ${GW_PUB}
Endpoint = ${ENDPOINT}:${WG_PORT}
AllowedIPs = ${WG_NET}
PersistentKeepalive = 25
EOF

    # Einmal base64, wie im Job im Cluster
    local conf_b64 priv_b64 pub_b64
    conf_b64="$(base64 -w0 "$tmp_conf")"
    priv_b64="$(printf "%s" "$client_priv" | base64 -w0)"
    pub_b64="$(printf "%s" "$client_pub" | base64 -w0)"

    # Secret als YAML mit bereits base64-codierten Daten erstellen
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: ${NS}
type: Opaque
data:
  wg0.conf: ${conf_b64}
  privatekey: ${priv_b64}
  publickey: ${pub_b64}
EOF

    if [[ -n "$OUTPUT_DIR" ]]; then
      cp "$tmp_conf" "${OUTPUT_DIR}/client-${host_id}-wg0.conf"
      echo "  -> Konfiguration: ${OUTPUT_DIR}/client-${host_id}-wg0.conf"
    fi
  done

  echo "Fertig (add)."
}

delete_clients() {
  # IDs in aufsteigende Reihenfolge bringen
  local from_id="$DELETE_FROM"
  local to_id="$DELETE_TO"

  if ! [[ "$from_id" =~ ^[0-9]+$ && "$to_id" =~ ^[0-9]+$ ]]; then
    echo "FROM_ID und TO_ID muessen numerisch sein." >&2
    exit 1
  fi

  if (( from_id > to_id )); then
    local tmp="$from_id"
    from_id="$to_id"
    to_id="$tmp"
  fi

  echo "Loesche Clients ${from_id} bis ${to_id} im Namespace ${NS} ..."

  local id
  for (( id=from_id; id<=to_id; id++ )); do
    local secret_name="${FULLNAME}-client-${id}"
    echo "Versuche Secret ${secret_name} zu loeschen ..."
    if kubectl delete secret "$secret_name" -n "$NS" >/dev/null 2>&1; then
      echo "  -> ${secret_name} geloescht."
    else
      echo "  -> ${secret_name} nicht gefunden (uebersprungen)."
    fi
  done
  echo "Fertig (delete)."
}

case "$ACTION" in
  add)
    add_clients
    ;;
  delete)
    delete_clients
    ;;
  *)
    echo "Unbekannte Aktion: $ACTION" >&2
    usage
    exit 1
    ;;
esac
