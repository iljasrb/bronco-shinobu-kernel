#!/usr/bin/env bash
# Self-check for the tuner engine: runs apply_profile against a fake sysfs
# tree built from the REAL bronco device tables and asserts the caps land on
# valid table entries. Host-runnable.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- fake sysfs (mirrors the device dump) -----------------------------------
fake_sys="$work/sys"
fake_proc="$work/proc"
fake_state="$work/state"
for c in 0 1 2 3 4 5 6 7; do
    mkdir -p "$fake_sys/devices/system/cpu/cpu$c/cpufreq"
done
for p in policy0 policy4 policy7; do
    mkdir -p "$fake_sys/devices/system/cpu/cpufreq/$p/walt"
done
mkdir -p "$fake_sys/class/kgsl/kgsl-3d0/devfreq" \
    "$fake_sys/module/cpu_input_boost/parameters"
mkdir -p "$fake_proc/sys/kernel"

# little (A510): 300-2016 MHz; perf (A710): 633-2745; prime (X2): 787-3187
for c in 0 1 2 3; do
    echo "300000 441600 556800 691200 806400 940800 1056000 1132800 1228800 1324800 1440000 1555200 1670400 1804800 1920000 2016000" \
        >"$fake_sys/devices/system/cpu/cpu$c/cpufreq/scaling_available_frequencies"
    echo 2016000 >"$fake_sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq"
    echo 1804800 >"$fake_sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq"
done
for c in 4 5 6; do
    echo "633600 768000 883200 998400 1113600 1209600 1324800 1440000 1555200 1651200 1766400 1881600 1996800 2112000 2227200 2342400 2457600 2572800 2649600 2745600" \
        >"$fake_sys/devices/system/cpu/cpu$c/cpufreq/scaling_available_frequencies"
    echo 2745600 >"$fake_sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq"
    echo 2745600 >"$fake_sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq"
done
echo "787200 921600 1036800 1171200 1286400 1401600 1536000 1651200 1766400 1881600 1996800 2131200 2246400 2361600 2476800 2592000 2707200 2822400 2918400 2995200" \
    >"$fake_sys/devices/system/cpu/cpu7/cpufreq/scaling_available_frequencies"
echo 3187200 >"$fake_sys/devices/system/cpu/cpu7/cpufreq/cpuinfo_max_freq"
echo 3187200 >"$fake_sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq"

for p in policy0 policy4 policy7; do
    for f in up_rate_limit_us down_rate_limit_us hispeed_load; do
        echo 0 >"$fake_sys/devices/system/cpu/cpufreq/$p/walt/$f"
    done
done

echo "900000000 862000000 815000000 765000000 710000000 645000000 580000000 515000000 439000000 364000000 324000000 285000000 220000000" \
    >"$fake_sys/class/kgsl/kgsl-3d0/devfreq/available_frequencies"
echo 900000000 >"$fake_sys/class/kgsl/kgsl-3d0/devfreq/max_freq"
for p in input_boost_freq_little input_boost_freq_big input_boost_freq_prime; do
    echo 0 >"$fake_sys/module/cpu_input_boost/parameters/$p"
done

export SYS="$fake_sys" PROC="$fake_proc" STATE_DIR="$fake_state"
# shellcheck disable=SC1091
. "$root/common.sh"

# --- assertions -------------------------------------------------------------
apply_profile battery
[ "$(cat "$fake_sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq")" = 1804800 ] \
    || fail "battery must not touch little (stock 1804800)"

# Preview must report the targets without applying.
pv="$(preview_profile battery)"
[ "$(printf '%s\n' "$pv" | grep '^big=' | cut -d= -f2)" = 2112000 ] \
    || fail "preview big"
[ "$(printf '%s\n' "$pv" | grep '^prime=' | cut -d= -f2)" = 2131200 ] \
    || fail "preview prime"
[ "$(printf '%s\n' "$pv" | grep '^gpu=' | cut -d= -f2)" = 515000000 ] \
    || fail "preview gpu"
[ "$(printf '%s\n' "$pv" | grep '^up=' | cut -d= -f2)" = 20000 ] \
    || fail "preview up"
[ -z "$(printf '%s\n' "$pv" | grep '^little=')" ] \
    || fail "preview little must be absent when uncapped"
[ "$(cat "$fake_sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq")" = 2112000 ] \
    || fail "battery perf cap: expected 2112000 (80% of 2745600)"
[ "$(cat "$fake_sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq")" = 2131200 ] \
    || fail "battery prime cap: expected 2131200 (70% of 3187200)"
[ "$(cat "$fake_sys/devices/system/cpu/cpufreq/policy0/walt/up_rate_limit_us")" = 20000 ] \
    || fail "battery walt up_rate_limit_us"
[ "$(cat "$fake_sys/devices/system/cpu/cpufreq/policy4/walt/hispeed_load")" = 95 ] \
    || fail "battery walt hispeed_load"
[ "$(cat "$fake_sys/class/kgsl/kgsl-3d0/devfreq/max_freq")" = 515000000 ] \
    || fail "battery gpu cap: expected 515000000 (60% of 900 MHz)"
[ "$(cat "$fake_sys/module/cpu_input_boost/parameters/input_boost_freq_little")" = 806400 ] \
    || fail "battery input boost little"

apply_profile performance
[ "$(cat "$fake_sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq")" = 3187200 ] \
    || fail "performance must leave prime at stock 3187200"
[ "$(cat "$fake_sys/class/kgsl/kgsl-3d0/devfreq/max_freq")" = 900000000 ] \
    || fail "performance must restore gpu"
[ "$(cat "$fake_sys/devices/system/cpu/cpufreq/policy0/walt/up_rate_limit_us")" = 5000 ] \
    || fail "performance walt up_rate_limit_us"

# Watchdog: simulate perf-hal drift, reassert_profile must restore.
apply_profile battery
echo 0 >"$fake_sys/devices/system/cpu/cpufreq/policy0/walt/up_rate_limit_us"
echo 0 >"$fake_sys/devices/system/cpu/cpufreq/policy4/walt/down_rate_limit_us"
echo 0 >"$fake_sys/module/cpu_input_boost/parameters/input_boost_freq_prime"
reassert_profile
[ "$(cat "$fake_sys/devices/system/cpu/cpufreq/policy0/walt/up_rate_limit_us")" = 20000 ] \
    || fail "reassert restores up_rate_limit_us"
[ "$(cat "$fake_sys/devices/system/cpu/cpufreq/policy4/walt/down_rate_limit_us")" = 10000 ] \
    || fail "reassert restores down_rate_limit_us"
[ "$(cat "$fake_sys/module/cpu_input_boost/parameters/input_boost_freq_prime")" = 806400 ] \
    || fail "reassert restores input boost prime"

# Double-apply must not clobber the recorded originals: battery -> battery ->
# performance still restores stock (the bug seen on-device).
apply_profile battery
apply_profile battery
[ "$(cat "$fake_sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq")" = 2112000 ] \
    || fail "second battery apply keeps perf cap"
apply_profile performance
[ "$(cat "$fake_sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq")" = 2745600 ] \
    || fail "double-apply must still restore perf stock"
[ "$(cat "$fake_sys/class/kgsl/kgsl-3d0/devfreq/max_freq")" = 900000000 ] \
    || fail "double-apply must still restore gpu stock"

printf 'tuner self-check OK\n'
