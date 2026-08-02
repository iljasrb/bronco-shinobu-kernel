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
readonly resukisu_dir="$root_dir/$RESUKISU_DIRECTORY"
readonly driver_dir="$kernel_dir/drivers"
readonly driver_link="$driver_dir/kernelsu"
readonly expected_target="../../$RESUKISU_DIRECTORY/kernel"

[[ -f "$driver_dir/Makefile" && -f "$driver_dir/Kconfig" ]] || {
    printf 'kernel drivers directory is missing at %s\n' "$driver_dir" >&2
    exit 1
}
[[ -f "$resukisu_dir/kernel/Kconfig" ]] || {
    printf 'ReSukiSU kernel source is missing at %s\n' "$resukisu_dir/kernel" >&2
    exit 1
}

if [[ -L "$driver_link" ]]; then
    [[ "$(readlink "$driver_link")" == "$expected_target" ]] || {
        printf 'unexpected ReSukiSU driver link at %s\n' "$driver_link" >&2
        exit 1
    }
elif [[ -e "$driver_link" ]]; then
    printf 'ReSukiSU driver path is not a symbolic link: %s\n' "$driver_link" >&2
    exit 1
else
    ln -s "$expected_target" "$driver_link"
fi

DRIVER_MAKEFILE="$driver_dir/Makefile" DRIVER_KCONFIG="$driver_dir/Kconfig" python3 - <<'PY'
from pathlib import Path
import os

makefile = Path(os.environ["DRIVER_MAKEFILE"])
kconfig = Path(os.environ["DRIVER_KCONFIG"])
make_entry = "obj-$(CONFIG_KSU)\t\t+= kernelsu/"
kconfig_entry = 'source "drivers/kernelsu/Kconfig"'

make_text = makefile.read_text()
if make_entry not in make_text:
    makefile.write_text(make_text.rstrip() + "\n" + make_entry + "\n")

kconfig_text = kconfig.read_text()
if kconfig_entry not in kconfig_text:
    marker = "\nendmenu"
    index = kconfig_text.rfind(marker)
    if index < 0:
        raise SystemExit(f"no final endmenu in {kconfig}")
    kconfig.write_text(kconfig_text[:index] + "\n" + kconfig_entry + kconfig_text[index:])
PY

printf 'ReSukiSU %s is integrated into %s\n' "$RESUKISU_REVISION" "$KERNEL_DIRECTORY"
