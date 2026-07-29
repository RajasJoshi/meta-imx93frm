#!/bin/sh
# postinst.sh — runs (with arg "postinst") after images are written.
[ "$1" = "postinst" ] || exit 0
set -e

echo "postinst: images written; bootenv committed by sw-description"

# Optional: sync to ensure writes hit the card before any reboot
sync

# Optional: sanity-check the env actually took the new slot
NEW=$(fw_printenv -n boot_slot 2>/dev/null || echo "?")
echo "postinst: boot_slot now = $NEW, upgrade_available = $(fw_printenv -n upgrade_available 2>/dev/null || echo ?)"

exit 0