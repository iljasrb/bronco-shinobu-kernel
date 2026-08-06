#!/system/bin/sh
# Keep the saved profile across updates (STATE_DIR is outside the module dir).

STATE_DIR="${STATE_DIR:-/data/adb/shinobu-battery}"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

if [ ! -f "$STATE_DIR/profile" ]; then
    printf 'battery\n' >"$STATE_DIR/profile"
fi
