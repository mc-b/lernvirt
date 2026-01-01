#!/bin/bash
set -e

ENV="$1"              # lernmaas | tbz-it | default
CHART="lernvirt"

SRC="$(pwd)"
DST="build/${ENV}"

rm -rf "${DST}"
mkdir -p "${DST}"

# 1. Chart kopieren
cp -r templates "${DST}/"
cp Chart.yaml "${DST}/Chart.yaml"

# 2. Chart-Name anpassen
sed -i "s/^name:.*/name: ${ENV}/" "${DST}/Chart.yaml"

# 3. values.yaml zusammenführen (Reihenfolge = gewinnt)
cat values.yaml env/${ENV}.yaml > "${DST}/values.yaml"

# 4. Package
cd "${DST}"
helm package .
