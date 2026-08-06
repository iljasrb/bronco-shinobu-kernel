#!/system/bin/sh
# Re-asserts knobs perf-hal resets (walt rate limits, hispeed_load,
# input boost). Polls every 30 s. Kills the previous instance on start.

MODDIR="${MODDIR:-/data/adb/modules/shinobu-battery}"
# shellcheck source=common.sh
. "$MODDIR/common.sh"

PID_FILE="$STATE_DIR/watchdog.pid"
if [ -f "$PID_FILE" ]; then
    # Only kill a live watchdog: the PID may be recycled after reboot.
    old="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$old" ] && grep -q watchdog.sh "/proc/$old/cmdline" 2>/dev/null; then
        kill "$old" 2>/dev/null || true
    fi
fi
printf '%s\n' "$$" >"$PID_FILE"

# restore_caps: undo recorded CPU/GPU caps (used when disabled/uninstalled).
restore_caps() {
    [ -f "$CAPS_FILE" ] || return 0
    while IFS='=' read -r path original; do
        echo "$original" >"$path" 2>/dev/null || true
    done <"$CAPS_FILE"
    rm -f "$CAPS_FILE"
}

while :; do
    # Exit when the module is removed or disabled.
    [ -f "$MODDIR/common.sh" ] && [ -f "$PID_FILE" ] || exit 0
    if [ -f "$MODDIR/disable" ]; then
        restore_caps
        exit 0
    fi
    reassert_profile || exit 1
    sleep 30
done
