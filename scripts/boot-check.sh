#!/usr/bin/env bash
# boot-check.sh [feature] — wait for the phone to boot, then verify a kernel
# feature is live. Exit 0 = booted and feature present; 1 = booted, feature
# missing; 2 = never booted (timeout).
#
# Usage (adb must be on PATH, e.g. `nix shell nixpkgs#android-tools -c ...`):
#   scripts/boot-check.sh version     print /proc/version
#   scripts/boot-check.sh root        adb root context is u:r:ksu:s0
#   scripts/boot-check.sh tcp-cc      tcp_congestion_control == bbr
#   scripts/boot-check.sh susfs       /proc/config.gz has CONFIG_KSU_SUSFS=y
set -euo pipefail

feature="${1:-version}"
timeout="${BOOT_CHECK_TIMEOUT:-180}"

adb wait-for-device

deadline=$(( $(date +%s) + timeout ))
while (( $(date +%s) < deadline )); do
    booted="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$booted" == "1" ]] && break
    sleep 5
done

booted="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
if [[ "$booted" != "1" ]]; then
    echo "boot-check: device did not finish booting within ${timeout}s" >&2
    exit 2
fi

case "$feature" in
    version)
        adb shell cat /proc/version
        ;;
    root)
        ctx="$(adb shell id | tr -d '\r')"
        echo "$ctx"
        [[ "$ctx" == *"u:r:ksu:s0"* ]]
        ;;
    tcp-cc)
        cc="$(adb shell "sysctl -n net.ipv4.tcp_congestion_control" | tr -d '\r')"
        echo "tcp_congestion_control=$cc"
        [[ "$cc" == "bbr" ]]
        ;;
    susfs)
        cfg="$(adb shell 'zcat /proc/config.gz 2>/dev/null | grep -c "^CONFIG_KSU_SUSFS=y" || true' | tr -d '\r')"
        echo "CONFIG_KSU_SUSFS=y in running config: $cfg"
        [[ "$cfg" == "1" ]]
        ;;
    *)
        echo "unknown feature: $feature" >&2
        exit 2
        ;;
esac
