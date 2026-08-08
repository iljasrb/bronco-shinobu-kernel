#!/system/bin/sh
# Restore caps, stop the watchdog, drop state.

MODDIR="${MODDIR:-/data/adb/modules/shinobu-battery}"
STATE_DIR="${STATE_DIR:-/data/adb/shinobu-battery}"

if [ -f "$STATE_DIR/watchdog.pid" ]; then
    pid="$(cat "$STATE_DIR/watchdog.pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && grep -q watchdog.sh "/proc/$pid/cmdline" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
fi
if [ -f "$STATE_DIR/caps" ]; then
    while IFS='=' read -r path original; do
        echo "$original" >"$path" 2>/dev/null || true
    done <"$STATE_DIR/caps"
fi
rm -rf "$STATE_DIR"
