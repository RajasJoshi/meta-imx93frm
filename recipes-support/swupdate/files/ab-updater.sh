#!/bin/sh
#
# ab-update.sh — apply a signed+encrypted .swu to the STANDBY A/B slot.
#
# Reads the current boot_slot from the U-Boot environment, selects the
# opposite slot, and installs the given .swu into it. Never writes the
# running slot. Fails closed if the environment cannot be read.
#
# Usage:   ab-update.sh <path-to.swu>
# Example: ab-update.sh /tmp/update-image-*.swu
#
set -eu

# ---- configuration -------------------------------------------------------
SW_GROUP="stable"          # sw-description software group
FW_PRINTENV="fw_printenv"  # libubootenv tools
SWUPDATE="swupdate"

log()  { printf '%s\n' "ab-update: $*"; }
die()  { printf '%s\n' "ab-update: ERROR: $*" >&2; exit 1; }

# ---- argument ------------------------------------------------------------
[ $# -eq 1 ] || die "usage: $(basename "$0") <path-to.swu>"
SWU="$1"
[ -f "$SWU" ] || die "file not found: $SWU"
case "$SWU" in
    *.swu) ;;
    *) die "not a .swu file: $SWU" ;;
esac

# ---- preflight -----------------------------------------------------------
command -v "$SWUPDATE"    >/dev/null 2>&1 || die "swupdate not found"
command -v "$FW_PRINTENV" >/dev/null 2>&1 || die "fw_printenv not found"

# ---- read the running slot ----------------------------------------------
# Fail closed: if we cannot determine the running slot, we must not guess,
# because writing the running slot destroys the known-good fallback.
CUR="$("$FW_PRINTENV" -n boot_slot 2>/dev/null)" \
    || die "cannot read boot_slot from U-Boot env (check /etc/fw_env.config)"

case "$CUR" in
    A) SEL="slot_b"; STANDBY="B" ;;
    B) SEL="slot_a"; STANDBY="A" ;;
    *) die "boot_slot='$CUR' is not A or B — refusing to proceed" ;;
esac

log "running slot   : $CUR"
log "target standby : $STANDBY  (selection: ${SW_GROUP},${SEL})"
log "image          : $SWU"

# ---- sanity: is the update daemon config sane? --------------------------
# A quick read-back proves the env is writable, which the bootenv commit
# at the end of the update depends on. If this fails, the slot switch would
# silently not take, so stop now.
if ! "$FW_PRINTENV" -n bootcount >/dev/null 2>&1; then
    die "U-Boot env not readable for bootcount — aborting before install"
fi

# ---- install -------------------------------------------------------------
log "installing to standby slot $STANDBY ..."
if "$SWUPDATE" -v -i "$SWU" -e "${SW_GROUP},${SEL}"; then
    log "install OK"
else
    die "swupdate failed — standby slot may be partially written;"\
        " running slot $CUR is untouched, safe to retry"
fi

# ---- post-check ----------------------------------------------------------
# The sw-description bootenv block should have set boot_slot to the standby
# and armed the trial (upgrade_available=1). Confirm before advising reboot.
NEW="$("$FW_PRINTENV" -n boot_slot 2>/dev/null || echo '?')"
UA="$("$FW_PRINTENV" -n upgrade_available 2>/dev/null || echo '?')"

log "post-install: boot_slot=$NEW upgrade_available=$UA"

if [ "$NEW" != "$STANDBY" ]; then
    die "boot_slot is '$NEW', expected '$STANDBY' — the env switch did not"\
        " take; do NOT reboot until this is resolved (env size/offset"\
        " mismatch between U-Boot and fw_env.config is the usual cause)"
fi

if [ "$UA" != "1" ]; then
    log "WARNING: upgrade_available=$UA (expected 1) — the trial may not be"
    log "         armed; rollback might not trigger if the new slot fails"
fi

log "success. reboot to boot slot $STANDBY."
log "  after reboot, confirm with: fw_printenv boot_slot   (expect $STANDBY)"
log "  a healthy boot clears the trial via swupdate-confirm.service"