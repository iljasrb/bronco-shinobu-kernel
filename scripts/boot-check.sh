#!/usr/bin/env bash
set -euo pipefail

feature="${1:-version}"
timeout="${BOOT_CHECK_TIMEOUT:-180}"

deadline=$(( $(date +%s) + timeout ))
if ! timeout "$timeout" adb wait-for-device; then
    echo "boot-check: device did not appear within ${timeout}s" >&2
    exit 2
fi
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
    input-boost)
        cfg="$(adb shell 'zcat /proc/config.gz 2>/dev/null | grep -c "^CONFIG_CPU_INPUT_BOOST=y" || true' | tr -d '\r')"
        params="$(adb shell 'ls /sys/module/cpu_input_boost/parameters 2>/dev/null | wc -l' | tr -d '\r')"
        echo "CONFIG_CPU_INPUT_BOOST=y in running config: $cfg; param files: $params"
        [[ "$cfg" == "1" && "$params" == "4" ]]
        ;;
    *)
        echo "unknown feature: $feature" >&2
        exit 2
        ;;
esac
