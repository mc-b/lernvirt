#!/usr/bin/env bash
set -euo pipefail

PREFIX="kvworker"

# IPv4-Adresse ermitteln (erste nicht-loopback)
IPV4=$(ip -4 addr show scope global | awk '/inet/ {print $2}' | cut -d/ -f1 | head -n1)

if [[ -z "${IPV4}" ]]; then
  echo "❌ Keine IPv4-Adresse gefunden"
  exit 1
fi

# Letzte Oktette extrahieren
LAST_OCTET="${IPV4##*.}"

# Validierung
if ! [[ "${LAST_OCTET}" =~ ^[0-9]+$ ]]; then
  echo "❌ Ungültige IP-Adresse: ${IPV4}"
  exit 1
fi

HOSTNAME="${PREFIX}"-"${LAST_OCTET}"

echo "ℹ️  Gefundene IP: ${IPV4}"
echo "ℹ️  Neuer Hostname: ${HOSTNAME}"

# Hostname setzen
hostnamectl set-hostname "${HOSTNAME}"

# /etc/hosts sicherstellen
if ! grep -q "${HOSTNAME}" /etc/hosts; then
  sed -i "/^127.0.1.1/d" /etc/hosts
  echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
fi

echo "✅ Hostname erfolgreich gesetzt"
