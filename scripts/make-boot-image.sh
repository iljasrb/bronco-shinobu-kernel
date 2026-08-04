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

readonly out_dir="${OUT_DIR:-$root_dir/out}"
readonly boot_tool_dir="$root_dir/$MKBOOTIMG_DIRECTORY"
readonly input_boot_img="${INPUT_BOOT_IMG:-$root_dir/inputs/boot.img}"
readonly kernel_image="${KERNEL_IMAGE:-$out_dir/arch/arm64/boot/Image}"
readonly kernel_release_file="${KERNEL_RELEASE_FILE:-$out_dir/include/config/kernel.release}"
readonly output_boot_img="${OUTPUT_BOOT_IMG:-$out_dir/boot-custom.img}"

mkdir -p "$out_dir"
readonly work_dir="$(mktemp -d "$out_dir/boot-package.XXXXXX")"

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

[[ -f "$input_boot_img" ]] || {
    printf 'boot image is missing at %s\n' "$input_boot_img" >&2
    exit 1
}
[[ -f "$kernel_image" ]] || {
    printf 'kernel image is missing at %s\n' "$kernel_image" >&2
    exit 1
}
[[ -f "$kernel_release_file" ]] || {
    printf 'kernel release is missing at %s; run build-kernel.sh first\n' "$kernel_release_file" >&2
    exit 1
}

python "$boot_tool_dir/unpack_bootimg.py" \
    --boot_img "$input_boot_img" \
    --out "$work_dir/unpacked" \
    --format=mkbootimg \
    -0 > "$work_dir/mkbootimg.args"

input_kernel_release="$(
    python3 - "$work_dir/unpacked/kernel" <<'PY'
from pathlib import Path
import re
import sys

kernel = Path(sys.argv[1]).read_bytes()
match = re.search(rb"Linux version ([0-9][^ ]*) \(", kernel)
if match is None:
    raise SystemExit("could not extract the kernel release from the input boot image")
print(match.group(1).decode("ascii"))
PY
)"
readonly input_kernel_release
readonly kernel_release="$(<"$kernel_release_file")"
[[ "$kernel_release" == "$input_kernel_release" ||
   "$kernel_release" == "$input_kernel_release-dirty" ]] || {
    printf 'input boot image kernel release is %s; built kernel release is %s\n' \
        "$input_kernel_release" "$kernel_release" >&2
    exit 1
}

mkbootimg_args=()
while IFS= read -r -d '' arg; do
    if [[ "$arg" == --kernel ]]; then
        IFS= read -r -d '' _
    else
        mkbootimg_args+=("$arg")
    fi
done < "$work_dir/mkbootimg.args"

python "$boot_tool_dir/mkbootimg.py" \
    "${mkbootimg_args[@]}" \
    --kernel "$kernel_image" \
    --output "$work_dir/boot.img"

readonly input_size="$(stat --format=%s "$input_boot_img")"
readonly output_size="$(stat --format=%s "$work_dir/boot.img")"
(( output_size <= input_size )) || {
    printf 'repacked boot image (%s bytes) exceeds the input partition image (%s bytes)\n' \
        "$output_size" "$input_size" >&2
    exit 1
}

mkdir -p "$(dirname -- "$output_boot_img")"
cp "$work_dir/boot.img" "$output_boot_img"

python "$boot_tool_dir/unpack_bootimg.py" \
    --boot_img "$output_boot_img" \
    --out "$work_dir/verified" \
    --format=info
