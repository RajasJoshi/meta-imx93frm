#!/bin/sh
# preinst.sh — runs (with arg "preinst") before images are written.
[ "$1" = "preinst" ] || exit 0
set -e

# 1. Refuse if we can't read the boot env — means fw_env.config is wrong,
#    and a wrong-slot write would break rollback. Fail closed.
CUR=$(fw_printenv -n boot_slot 2>/dev/null) || {
    echo "preinst: cannot read boot_slot — aborting" >&2
    exit 1
}
case "$CUR" in
    A|B) ;;
    *) echo "preinst: boot_slot='$CUR' invalid — aborting" >&2; exit 1 ;;
esac
echo "preinst: current slot=$CUR"

# 2. Guard against writing the RUNNING slot. The selection (-e stable,slot_X)
#    should target the standby; this verifies the invoker didn't get it wrong.
#    SWUPDATE_SELECTION is exported by swupdate as "<group>,<selection>".
SEL="${SWU_SELECTION:-$2}"     # depends on how your invoker passes it; see note
case "$CUR:$SEL" in
    A:*slot_a*) echo "preinst: refusing to write running slot A" >&2; exit 1 ;;
    B:*slot_b*) echo "preinst: refusing to write running slot B" >&2; exit 1 ;;
esac

exit 0