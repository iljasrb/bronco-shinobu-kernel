#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$root_dir/sources.env"

readonly fs_dir="$root_dir/$KERNEL_DIRECTORY/fs"
readonly source_dir="$root_dir/$NOMOUNT_DIRECTORY/kernel/src"
readonly driver_link="$fs_dir/nomount"
readonly expected_target="../../$NOMOUNT_DIRECTORY/kernel/src"

for file in "$fs_dir/Makefile" "$fs_dir/Kconfig" \
    "$source_dir/Makefile" "$source_dir/Kconfig" \
    "$source_dir/nomount.c" "$source_dir/nomount.h"; do
    [[ -f "$file" ]] || {
        printf 'NoMount integration input is missing: %s\n' "$file" >&2
        exit 1
    }
done

if [[ -L "$driver_link" ]]; then
    [[ "$(readlink "$driver_link")" == "$expected_target" ]] || {
        printf 'unexpected NoMount driver link at %s\n' "$driver_link" >&2
        exit 1
    }
elif [[ -e "$driver_link" ]]; then
    printf 'NoMount driver path is not a symbolic link: %s\n' "$driver_link" >&2
    exit 1
else
    ln -s "$expected_target" "$driver_link"
fi

python3 - "$fs_dir" <<'PY'
from pathlib import Path
import sys

fs = Path(sys.argv[1])
makefile = fs / "Makefile"
kconfig = fs / "Kconfig"
make_entry = "obj-$(CONFIG_NOMOUNT) += nomount/"
kconfig_entry = 'source "fs/nomount/Kconfig"'

make_text = makefile.read_text()
if make_entry not in make_text.splitlines():
    makefile.write_text(make_text.rstrip() + "\n" + make_entry + "\n")

kconfig_text = kconfig.read_text()
if kconfig_entry not in kconfig_text.splitlines():
    index = kconfig_text.rfind("\nendmenu")
    if index < 0:
        raise SystemExit(f"no final endmenu in {kconfig}")
    kconfig.write_text(kconfig_text[:index] + "\n" + kconfig_entry + kconfig_text[index:])
PY

printf 'NoMount %s is integrated into %s\n' "$NOMOUNT_REVISION" "$KERNEL_DIRECTORY"
