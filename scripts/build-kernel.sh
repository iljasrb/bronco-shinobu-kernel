#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_manifest="$root_dir/sources.env"

[[ -f "$source_manifest" ]] || {
    printf 'source manifest is missing at %s\n' "$source_manifest" >&2
    exit 1
}
# shellcheck disable=SC1091
source "$source_manifest"

readonly kernel_dir="$root_dir/$KERNEL_DIRECTORY"
readonly out_dir="$(realpath "${OUT_DIR:-$root_dir/out}")"
readonly devicetree_dir="$root_dir/$DEVICE_TREE_DIRECTORY"
readonly resolved_devicetree_link="$root_dir/sm8475-devicetrees"
readonly qcom_dts_dir="$devicetree_dir/qcom"
readonly bronco_kbuild="$qcom_dts_dir/Kbuild"
readonly android_clang_dir="${ANDROID_CLANG_DIR:-$root_dir/$ANDROID_CLANG_PATH}"
readonly jobs="${JOBS:-$(nproc)}"
readonly config_dir="$kernel_dir/arch/arm64/configs"

[[ -d "$kernel_dir" ]] || {
    printf 'kernel source is missing at %s\n' "$kernel_dir" >&2
    exit 1
}

# Project-scoped ccache dir (clear with rm -rf .ccache).
export CCACHE_DIR="${CCACHE_DIR:-$root_dir/.ccache}"
# Reproducible build timestamp: date of the checked-out kernel commit.
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "$(git -C "$kernel_dir" show -s --format=%cI HEAD)" '+%Y-%m-%d %H:%M:%S +0000')"

[[ -d "$devicetree_dir" ]] || {
    printf 'device-tree source is missing at %s\n' "$devicetree_dir" >&2
    exit 1
}

[[ -x "$android_clang_dir/bin/clang" ]] || {
    printf 'Android clang is missing at %s\n' "$android_clang_dir/bin/clang" >&2
    exit 1
}
export PATH="$android_clang_dir/bin:$PATH"

[[ ! -e "$bronco_kbuild" ]] || {
    printf 'temporary device-tree Kbuild path already exists at %s\n' "$bronco_kbuild" >&2
    exit 1
}

mkdir -p "$out_dir"
rm -f "$out_dir/.config"

[[ ! -e "$resolved_devicetree_link" && ! -L "$resolved_devicetree_link" ]] || {
    printf 'temporary device-tree link path already exists at %s\n' "$resolved_devicetree_link" >&2
    exit 1
}
ln -s "$devicetree_dir" "$resolved_devicetree_link"
cat > "$bronco_kbuild" <<'EOF'
dtb-y += cape-moto-bronco-base.dtb cape-v2-moto-bronco-base.dtb
dtbo-y += cape-bronco-evb1-overlay.dtbo cape-bronco-evt1-overlay.dtbo
dtbo-y += cape-bronco-evt2-overlay.dtbo cape-bronco-dvt1-overlay.dtbo
dtbo-y += cape-bronco-dvt2-overlay.dtbo

cape-bronco-evb1-overlay.dtbo-base := cape-moto-bronco-base.dtb
cape-bronco-evt1-overlay.dtbo-base := cape-v2-moto-bronco-base.dtb
cape-bronco-evt2-overlay.dtbo-base := cape-v2-moto-bronco-base.dtb
cape-bronco-dvt1-overlay.dtbo-base := cape-v2-moto-bronco-base.dtb
cape-bronco-dvt2-overlay.dtbo-base := cape-v2-moto-bronco-base.dtb

always-y := $(dtb-y)
EOF
trap 'rm -f "$bronco_kbuild" "$resolved_devicetree_link"' EXIT

KCONFIG_CONFIG="$out_dir/.config" "$kernel_dir/scripts/kconfig/merge_config.sh" -m -r -y \
    "$config_dir/gki_defconfig" \
    "$config_dir/vendor/waipio_GKI.config" \
    "$config_dir/vendor/ext_config/moto-waipio.config" \
    "$config_dir/vendor/ext_config/moto-waipio-bronco.config"

"$kernel_dir/scripts/config" --file "$out_dir/.config" \
    --enable LTO \
    --enable LTO_CLANG \
    --enable HAS_LTO_CLANG \
    --enable LTO_CLANG_THIN \
    --disable LTO_CLANG_FULL \
    --disable LTO_NONE \
    --enable CFI_CLANG \
    --enable CFI_CLANG_SHADOW \
    --disable CFI_PERMISSIVE \
    --enable TCP_CONG_ADVANCED \
    --enable TCP_CONG_BBR \
    --enable DEFAULT_BBR \
    --disable DEFAULT_CUBIC \
    --enable KSU \
    --enable KSU_SUSFS \
    --set-str KSU_FULL_NAME_FORMAT "ThinkPhone-Shinobu-v${PROJECT_VERSION}-%TAG_NAME%-%COMMIT_SHA%@%REPO_NAME%" \
    --disable KSU_MANUAL_HOOK \
    --disable KSU_TRACEPOINT_HOOK \
    --enable CPU_INPUT_BOOST \
    --enable LLVM_POLLY \
    --set-val LITTLE_CPU_MASK 15 \
    --set-val BIG_CPU_MASK 112 \
    --set-val PRIME_CPU_MASK 128 \
    --set-val INPUT_BOOST_DURATION_MS 200 \
    --set-val INPUT_BOOST_FREQ_LP 1132800 \
    --set-val INPUT_BOOST_FREQ_PERF 1113600 \
    --set-val INPUT_BOOST_FREQ_PRIME 1036800 \
    --set-val MAX_BOOST_FREQ_LP 1670400 \
    --set-val MAX_BOOST_FREQ_PERF 2150400 \
    --set-val MAX_BOOST_FREQ_PRIME 2553600 \
    ${EXTRA_KCONFIG:-}

make -C "$kernel_dir" \
    O="$out_dir" \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CC="ccache clang" \
    HOSTCC="ccache cc" \
    HOSTCXX="ccache c++" \
    CROSS_COMPILE=aarch64-linux-gnu- \
    olddefconfig

make -C "$kernel_dir" \
    O="$out_dir" \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CC="ccache clang" \
    HOSTCC="ccache cc" \
    HOSTCXX="ccache c++" \
    CROSS_COMPILE=aarch64-linux-gnu- \
    -j"$jobs" \
    Image dtbs modules
