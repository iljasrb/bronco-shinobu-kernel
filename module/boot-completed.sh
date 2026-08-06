#!/system/bin/sh
# perfd resets tunables after late_start; re-apply the profile and start
# the watchdog.

MODDIR="${MODDIR:-/data/adb/modules/shinobu-battery}"
# shellcheck source=common.sh
. "$MODDIR/common.sh"

apply_profile "$(current_profile)"
nohup sh "$MODDIR/watchdog.sh" >/dev/null 2>&1 &
