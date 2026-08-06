#!/system/bin/sh
# Boot entry (KernelSU late_start). Applies the saved profile.

MODDIR="${MODDIR:-/data/adb/modules/shinobu-battery}"
# shellcheck source=common.sh
. "$MODDIR/common.sh"

apply_profile "$(current_profile)"
