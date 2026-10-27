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

readonly out_dir="$(realpath -m "${OUT_DIR:-$root_dir/out}")"
readonly anykernel3_dir="${ANYKERNEL3_DIR:-$root_dir/${ANYKERNEL3_DIRECTORY:-AnyKernel3}}"
readonly kernel_image="${KERNEL_IMAGE:-$out_dir/arch/arm64/boot/Image}"
readonly kernel_release_file="${KERNEL_RELEASE_FILE:-$out_dir/include/config/kernel.release}"
readonly template="${ANYKERNEL3_TEMPLATE:-$root_dir/scripts/anykernel3.sh.in}"
readonly output_zip="${OUTPUT_ANYKERNEL3_ZIP:-$out_dir/shinobu-kernel-${PROJECT_VERSION}-anykernel3.zip}"

for file in "$kernel_image" "$kernel_release_file" "$template"; do
    [[ -f "$file" ]] || {
        printf 'required file is missing: %s\n' "$file" >&2
        exit 1
    }
done
[[ -d "$anykernel3_dir" ]] || {
    printf 'AnyKernel3 source is missing at %s; run ./sync-sources.sh --reset\n' \
        "$anykernel3_dir" >&2
    exit 1
}

lineageos_build="${BOOT_IMAGE_URL%/*}"
lineageos_build="${lineageos_build##*/}"
readonly lineageos_build
[[ "$lineageos_build" =~ ^[0-9]{8}$ ]] || {
    printf 'could not derive the LineageOS build date from BOOT_IMAGE_URL: %s\n' \
        "$BOOT_IMAGE_URL" >&2
    exit 1
}

readonly kernel_release="$(<"$kernel_release_file")"
[[ -n "$kernel_release" ]] || {
    printf 'kernel release is empty: %s\n' "$kernel_release_file" >&2
    exit 1
}

mkdir -p "$out_dir" "$(dirname -- "$output_zip")"
readonly work_dir="$(mktemp -d "$out_dir/anykernel3.XXXXXX")"
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

readonly package_dir="$work_dir/package"
mkdir -p "$package_dir"
cp -a "$anykernel3_dir/." "$package_dir/"
rm -rf "$package_dir/.git" "$package_dir/.github"
rm -f "$package_dir/README.md"
rm -f "$package_dir/modules/system/lib/modules/placeholder"
rm -f "$package_dir/patch/placeholder" "$package_dir/ramdisk/placeholder"

readonly update_binary="$package_dir/META-INF/com/google/android/update-binary"
for file in "$update_binary" "$package_dir/tools/ak3-core.sh" \
    "$package_dir/tools/magiskboot" "$package_dir/tools/busybox"; do
    [[ -f "$file" ]] || {
        printf 'AnyKernel3 source is incomplete; missing %s\n' "$file" >&2
        exit 1
    }
done

# AnyKernel3 08e9d128 treated a successful split_boot() as a failure because
# the status check was a bare test. Reject that known-broken revision if it is
# ever pinned again.
if grep -qF '[ $? == 1 ] && splitfail=1;' "$package_dir/tools/ak3-core.sh"; then
    printf 'AnyKernel3 tools/ak3-core.sh has the broken split_boot status check\n' >&2
    exit 1
fi

# BakaSU's ksud injects its own mkbootfs at this exact marker before running
# the installer. Keep the marker present exactly once.
python3 - "$update_binary" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
marker = b"chmod -R 755 tools bin;"
count = data.count(marker)
if count != 1:
    raise SystemExit(
        f"{path} must contain the AnyKernel3 injection marker exactly once; found {count}"
    )
PY

python3 - "$template" "$package_dir/anykernel.sh" "$PROJECT_VERSION" \
    "$kernel_release" "$lineageos_build" <<'PY'
from pathlib import Path
import re
import sys

template, output, version, release, build = sys.argv[1:]
text = Path(template).read_text()
replacements = {
    "@PROJECT_VERSION@": version,
    "@KERNEL_RELEASE@": release,
    "@LINEAGEOS_BUILD@": build,
}
for placeholder, value in replacements.items():
    if placeholder not in text:
        raise SystemExit(f"template is missing {placeholder}")
    text = text.replace(placeholder, value)
leftover = re.search(r"@[A-Z0-9_]+@", text)
if leftover:
    raise SystemExit(f"template has an unresolved placeholder: {leftover.group(0)}")
Path(output).write_text(text)
PY

if [[ "$(od -An -tx1 -N2 "$kernel_image" | tr -d ' \n')" == "1f8b" ]]; then
    readonly kernel_name="Image.gz"
else
    readonly kernel_name="Image"
fi
install -m 0644 "$kernel_image" "$package_dir/$kernel_name"

{
    printf 'Shinobu Kernel %s\n' "$PROJECT_VERSION"
    printf 'Kernel: %s\n' "$kernel_release"
    printf 'Package build: LineageOS %s\n' "$lineageos_build"
} > "$package_dir/version"
{
    printf 'project=ThinkPhone Shinobu Kernel\n'
    printf 'project_version=%s\n' "$PROJECT_VERSION"
    printf 'kernel_release=%s\n' "$kernel_release"
    printf 'lineageos_build=%s\n' "$lineageos_build"
    printf 'anykernel3_revision=%s\n' \
        "$(git -C "$anykernel3_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
} > "$package_dir/shinobu-info.txt"

chmod 0755 "$update_binary" "$package_dir/tools/"*
chmod 0644 "$package_dir/anykernel.sh" "$package_dir/version" "$package_dir/shinobu-info.txt"

python3 - "$package_dir" "$output_zip" <<'PY'
from pathlib import Path
import stat
import sys
import zipfile

package, output = map(Path, sys.argv[1:])
output.parent.mkdir(parents=True, exist_ok=True)
files = sorted(path for path in package.rglob("*") if path.is_file())
if not files:
    raise SystemExit("AnyKernel3 package is empty")
with zipfile.ZipFile(output, "w") as archive:
    for path in files:
        arcname = path.relative_to(package).as_posix()
        mode = stat.S_IMODE(path.stat().st_mode)
        info = zipfile.ZipInfo(arcname, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = (mode & 0xFFFF) << 16
        archive.writestr(info, path.read_bytes())
with zipfile.ZipFile(output) as archive:
    bad = archive.testzip()
    if bad is not None:
        raise SystemExit(f"corrupt ZIP entry: {bad}")
    names = set(archive.namelist())
    required = {"anykernel.sh", "version", "META-INF/com/google/android/update-binary"}
    missing = required - names
    if missing:
        raise SystemExit(f"ZIP is missing required entries: {sorted(missing)}")
    if not any(name.endswith("/magiskboot") for name in names):
        raise SystemExit("ZIP is missing the magiskboot tool")
PY

printf 'Created %s\n' "$output_zip"
printf 'AnyKernel3 revision: %s\n' \
    "$(git -C "$anykernel3_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
