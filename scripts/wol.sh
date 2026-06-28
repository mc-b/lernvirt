#!/usr/bin/env bash
set -euo pipefail

# Wake on LAN

if ip -o link show br0 2>/dev/null | grep -q "UP"; then
  ETH="br0"
else
  ETH=$(ip -o link show | awk -F': ' '$2 ~ /^en/ && $0 ~ /UP/ {print $2; exit}')
fi

if [ -z "${ETH:-}" ]; then
  echo "Kein aktives Ethernet-Interface gefunden."
  exit 1
fi

HOST="${1:-}"

if [ -z "$HOST" ]; then
  echo "Verwendung: $0 <rechnername>"
  exit 1
fi

case "$HOST" in
  dl380-01)
    MAC="..."
    ;;

  dl380-02)
    MAC="14:02:ec:40:2c:60"
    ;;

  dl385-01)
    MAC="40:5b:7f:9e:ea:52"
    ;;

  *)
    echo "Unbekannter Rechner: $HOST"
    exit 1
    ;;
esac

echo "Sende Wake-on-LAN an $HOST ($MAC) über Interface $ETH"

sudo etherwake -i "$ETH" "$MAC"