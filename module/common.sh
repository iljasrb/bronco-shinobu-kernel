# Shared helpers. Sourced by the module scripts and the test harness.
# Paths overridable for tests.

MODDIR="${MODDIR:-/data/adb/modules/shinobu-battery}"
STATE_DIR="${STATE_DIR:-/data/adb/shinobu-battery}"
SYS="${SYS:-/sys}"
PROC="${PROC:-/proc}"

LOG_FILE="$STATE_DIR/tune.log"
PROFILE_FILE="$STATE_DIR/profile"
CAPS_FILE="$STATE_DIR/caps"

# SM8475 clusters.
LITTLE_CPUS="0 1 2 3"
PERF_CPUS="4 5 6"
PRIME_CPUS="7"
POLICIES="policy0 policy4 policy7"

log() {
    [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
    if [ -f "$LOG_FILE" ] && [ "$(wc -c <"$LOG_FILE")" -ge 1048576 ]; then
        : >"$LOG_FILE"
    fi
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

# write_file <sysfs-path> <value>: best-effort, logs failures, never fatal.
write_file() {
    local path="$1" value="$2" current
    [ -w "$path" ] || { log "skip: $path not writable"; return 1; }
    current="$(cat "$path" 2>/dev/null || true)"
    if [ "$current" = "$value" ]; then
        log "ok (unchanged): $path=$value"
        return 0
    fi
    if echo "$value" >"$path" 2>/dev/null; then
        log "ok: $path=$value"
    else
        log "FAIL: $path=$value"
        return 1
    fi
}

# cpu_freqs <cpu> -> "kHz kHz ..." from the device table, empty if unavailable.
cpu_freqs() {
    cat "$SYS/devices/system/cpu/cpu$1/cpufreq/scaling_available_frequencies" \
        2>/dev/null || true
}

# cap_freq <cpu> <pct>: highest table freq <= pct% of the hardware max.
# Empty = skip (no cap).
cap_freq() {
    local cpu="$1" pct="$2" freqs max_khz target pick=""
    freqs="$(cpu_freqs "$cpu")"
    [ -n "$freqs" ] || return 0
    [ "$pct" -ge 100 ] && return 0
    max_khz="$(cat "$SYS/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq" \
        2>/dev/null || printf '%s\n' $freqs | sort -n | tail -1)"
    target=$((max_khz / 100 * pct))
    for f in $freqs; do
        [ "$f" -le "$target" ] && [ "$f" -gt "${pick:-0}" ] && pick="$f"
    done
    [ -n "$pick" ] || pick="$(printf '%s\n' $freqs | sort -n | head -1)"
    printf '%s\n' "$pick"
}

# gpu_cap_hz <pct>: highest devfreq table entry <= pct% of max.
# Empty = no table.
gpu_cap_hz() {
    local pct="$1" table max_hz target pick=""
    table="$(cat "$SYS/class/kgsl/kgsl-3d0/devfreq/available_frequencies" \
        2>/dev/null || true)"
    [ -n "$table" ] || return 0
    max_hz="$(printf '%s\n' $table | sort -n | tail -1)"
    [ "$pct" -ge 100 ] && return 0
    target=$((max_hz / 100 * pct))
    for f in $table; do
        [ "$f" -le "$target" ] && [ "$f" -gt "${pick:-0}" ] && pick="$f"
    done
    [ -n "$pick" ] || pick="$(printf '%s\n' $table | sort -n | head -1)"
    printf '%s\n' "$pick"
}

# ufs_clkscale_path: best-effort locate, empty if absent.
ufs_clkscale_path() {
    find "$SYS/devices" -name clkscale_enable -type f 2>/dev/null | head -1
}

# apply_cpu_profile <battery|balanced|performance>: sets the profile knobs.
apply_cpu_profile() {
    case "$1" in
        battery)
            LITTLE_CAP=100; PERF_CAP=80; PRIME_CAP=70
            UP_RATE_LIMIT_US=20000; DOWN_RATE_LIMIT_US=10000
            HISPEED_LOAD=95
            IB_LP=806400; IB_PERF=883200; IB_PRIME=806400
            GPU_CAP=60
            ;;
        balanced)
            LITTLE_CAP=100; PERF_CAP=90; PRIME_CAP=85
            UP_RATE_LIMIT_US=10000; DOWN_RATE_LIMIT_US=10000
            HISPEED_LOAD=90
            IB_LP=998400; IB_PERF=1036800; IB_PRIME=979200
            GPU_CAP=80
            ;;
        performance)
            LITTLE_CAP=100; PERF_CAP=100; PRIME_CAP=100
            UP_RATE_LIMIT_US=5000; DOWN_RATE_LIMIT_US=5000
            HISPEED_LOAD=80
            IB_LP=1132800; IB_PERF=1113600; IB_PRIME=1036800
            GPU_CAP=100
            ;;
        *)
            log "unknown profile: $1"
            return 1
            ;;
    esac
    return 0
}

# cap_cpu <cpu> <pct>: apply a cap and record the original for later
# restore. Skip if unchanged.
cap_cpu() {
    local cpu="$1" pct="$2" cap cur path
    cap="$(cap_freq "$cpu" "$pct")"
    [ -n "$cap" ] || return 0
    path="$SYS/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq"
    cur="$(cat "$path" 2>/dev/null || true)"
    [ "$cur" = "$cap" ] && return 0
    write_file "$path" "$cap" || return 1
    printf '%s=%s\n' "$path" "$cur" >>"$CAPS_FILE"
}

cap_gpu() {
    local pct="$1" cap cur path
    cap="$(gpu_cap_hz "$pct")"
    [ -n "$cap" ] || return 0
    path="$SYS/class/kgsl/kgsl-3d0/devfreq/max_freq"
    cur="$(cat "$path" 2>/dev/null || true)"
    [ "$cur" = "$cap" ] && return 0
    write_file "$path" "$cap" || return 1
    printf '%s=%s\n' "$path" "$cur" >>"$CAPS_FILE"
}

# apply_profile <battery|balanced|performance>: restore old caps, then
# apply the profile.
apply_profile() {
    local profile="$1" cpu policy ufs
    apply_cpu_profile "$profile" || return 1
    log "applying profile: $profile"

    # Restore previously recorded caps to their original values.
    if [ -f "$CAPS_FILE" ]; then
        local restore_failed=0
        while IFS='=' read -r path original; do
            write_file "$path" "$original" || restore_failed=1
        done <"$CAPS_FILE"
        [ "$restore_failed" -eq 0 ] || return 1
        rm -f "$CAPS_FILE"
    fi

    # CPU: per-cluster max caps (kHz from device table). Governor untouched.
    for cpu in $LITTLE_CPUS; do
        cap_cpu "$cpu" "$LITTLE_CAP"
    done
    for cpu in $PERF_CPUS; do
        cap_cpu "$cpu" "$PERF_CAP"
    done
    for cpu in $PRIME_CPUS; do
        cap_cpu "$cpu" "$PRIME_CAP"
    done

    # WALT governor (per-policy): delay up-ramps, harden hispeed entry.
    for policy in $POLICIES; do
        write_file "$SYS/devices/system/cpu/cpufreq/$policy/walt/up_rate_limit_us" \
            "$UP_RATE_LIMIT_US"
        write_file "$SYS/devices/system/cpu/cpufreq/$policy/walt/down_rate_limit_us" \
            "$DOWN_RATE_LIMIT_US"
        write_file "$SYS/devices/system/cpu/cpufreq/$policy/walt/hispeed_load" \
            "$HISPEED_LOAD"
    done

    # Built-in input-boost parameters.
    local ib_param="$SYS/module/cpu_input_boost/parameters"
    write_file "$ib_param/input_boost_freq_little" "$IB_LP"
    write_file "$ib_param/input_boost_freq_big" "$IB_PERF"
    write_file "$ib_param/input_boost_freq_prime" "$IB_PRIME"

    # GPU: cap from the devfreq table (Hz), never touch the floor.
    cap_gpu "$GPU_CAP"

    # UFS clock scaling (best-effort; absent on some builds).
    ufs="$(ufs_clkscale_path)"
    [ -n "$ufs" ] && write_file "$ufs" 1

    log "profile applied: $profile"
}

current_profile() {
    cat "$PROFILE_FILE" 2>/dev/null || printf 'battery\n'
}

# reassert_profile: rewrite knobs perf-hal resets (walt rate limits,
# hispeed_load, input boost). Called by watchdog.sh.
reassert_profile() {
    local profile policy cur
    profile="$(current_profile)"
    apply_cpu_profile "$profile" || return 1
    for policy in $POLICIES; do
        local base="$SYS/devices/system/cpu/cpufreq/$policy/walt"
        cur="$(cat "$base/up_rate_limit_us" 2>/dev/null || true)"
        [ "$cur" = "$UP_RATE_LIMIT_US" ] || write_file "$base/up_rate_limit_us" \
            "$UP_RATE_LIMIT_US"
        cur="$(cat "$base/down_rate_limit_us" 2>/dev/null || true)"
        [ "$cur" = "$DOWN_RATE_LIMIT_US" ] || \
            write_file "$base/down_rate_limit_us" "$DOWN_RATE_LIMIT_US"
        cur="$(cat "$base/hispeed_load" 2>/dev/null || true)"
        [ "$cur" = "$HISPEED_LOAD" ] || write_file "$base/hispeed_load" \
            "$HISPEED_LOAD"
    done
    local ib_param="$SYS/module/cpu_input_boost/parameters"
    cur="$(cat "$ib_param/input_boost_freq_little" 2>/dev/null || true)"
    [ "$cur" = "$IB_LP" ] || write_file "$ib_param/input_boost_freq_little" \
        "$IB_LP"
    cur="$(cat "$ib_param/input_boost_freq_big" 2>/dev/null || true)"
    [ "$cur" = "$IB_PERF" ] || write_file "$ib_param/input_boost_freq_big" \
        "$IB_PERF"
    cur="$(cat "$ib_param/input_boost_freq_prime" 2>/dev/null || true)"
    [ "$cur" = "$IB_PRIME" ] || write_file "$ib_param/input_boost_freq_prime" \
        "$IB_PRIME"
    return 0
}

# cluster_cap <cpus> <pct>: first online cpu's cap in a cluster.
cluster_cap() {
    local c cap
    for c in $1; do
        cap="$(cap_freq "$c" "$2")"
        [ -n "$cap" ] && { printf '%s\n' "$cap"; return 0; }
    done
    return 1
}

# preview_profile <name>: print the values the profile would apply,
# without changing anything. key=value lines.
preview_profile() {
    apply_cpu_profile "$1" || return 1
    local cap
    cap="$(cluster_cap "$LITTLE_CPUS" "$LITTLE_CAP")" \
        && printf 'little=%s\n' "$cap"
    cap="$(cluster_cap "$PERF_CPUS" "$PERF_CAP")" \
        && printf 'big=%s\n' "$cap"
    cap="$(cluster_cap "$PRIME_CPUS" "$PRIME_CAP")" \
        && printf 'prime=%s\n' "$cap"
    cap="$(gpu_cap_hz "$GPU_CAP")" && printf 'gpu=%s\n' "$cap"
    printf 'up=%s\ndown=%s\n' "$UP_RATE_LIMIT_US" "$DOWN_RATE_LIMIT_US"
}

set_profile() {
    local profile="$1"
    apply_cpu_profile "$profile" || return 1
    mkdir -p "$STATE_DIR" || return 1
    printf '%s\n' "$profile" 2>/dev/null >"$PROFILE_FILE" || return 1
    apply_profile "$profile"
}
