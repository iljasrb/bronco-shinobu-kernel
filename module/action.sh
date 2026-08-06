#!/system/bin/sh
# CLI + WebUI backend.
#   action.sh                 -> status
#   action.sh status          -> current profile + live values
#   action.sh preview <profile> -> values the profile would apply
#   action.sh apply <profile> -> apply now and save
#   action.sh profiles        -> list profile names

MODDIR="${MODDIR:-/data/adb/modules/shinobu-battery}"
# shellcheck source=common.sh
. "$MODDIR/common.sh"

status() {
    local profile
    profile="$(current_profile)"
    printf 'profile: %s\n' "$profile"
    printf 'valid: battery balanced performance\n'
    for p in 0 4 7; do
        printf 'cpu%d max: %s\n' "$p" \
            "$(cat "$SYS/devices/system/cpu/cpu$p/cpufreq/scaling_max_freq" \
                2>/dev/null || echo '?')"
    done
    printf 'gpu max: %s Hz\n' \
        "$(cat "$SYS/class/kgsl/kgsl-3d0/devfreq/max_freq" 2>/dev/null || echo '?')"
    printf 'walt up/down: %s / %s us\n' \
        "$(cat "$SYS/devices/system/cpu/cpufreq/policy0/walt/up_rate_limit_us" \
            2>/dev/null || echo '?')" \
        "$(cat "$SYS/devices/system/cpu/cpufreq/policy0/walt/down_rate_limit_us" \
            2>/dev/null || echo '?')"
}

case "${1:-status}" in
    status)
        status
        ;;
    apply)
        set_profile "${2:-}"
        ;;
    preview)
        preview_profile "${2:-}"
        ;;
    profiles)
        printf 'battery balanced performance\n'
        ;;
    *)
        printf 'usage: action.sh [status|preview <profile>|apply <profile>|profiles]\n' >&2
        exit 1
        ;;
esac
