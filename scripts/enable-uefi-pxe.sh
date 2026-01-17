#!/bin/sh
set -eu

# ------------------------------------------------------------------
# Re-enable UEFI PXE by prioritizing existing PXE boot entries
# ------------------------------------------------------------------

# Root-Check
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Dependency check
if ! command -v efibootmgr >/dev/null 2>&1; then
  echo "efibootmgr is not installed" >&2
  exit 1
fi

echo "Current UEFI boot entries:"
efibootmgr
echo

# PXE boot entries
PXE_IDS=$(efibootmgr \
  | grep -Ei 'PXE|IPv4|IPv6|Network' \
  | sed -n 's/^Boot\([0-9A-F]\{4\}\).*/\1/p')

# Local (non-PXE) boot entries
LOCAL_IDS=$(efibootmgr \
  | grep -viE 'PXE|IPv4|IPv6|Network' \
  | sed -n 's/^Boot\([0-9A-F]\{4\}\).*/\1/p')

if [ -z "${PXE_IDS}" ]; then
  echo "No PXE boot entries found – cannot re-enable PXE" >&2
  exit 1
fi

# New BootOrder: PXE first, local afterwards
NEW_ORDER=$(printf "%s\n%s\n" "${PXE_IDS}" "${LOCAL_IDS}" | sed '/^$/d' | paste -sd, -)

echo "Setting new BootOrder: ${NEW_ORDER}"
efibootmgr -o "${NEW_ORDER}"

echo
echo "Resulting UEFI boot order:"
efibootmgr
