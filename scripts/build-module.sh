#!/usr/bin/env bash
# Builds the standalone flashable KernelSU module zip + sha256.
# Runs independently of the kernel build.
set -euo pipefail

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
module_dir="$root_dir/module"
module_manifest="$module_dir/update.json"
[[ -f "$module_manifest" ]] || {
    printf 'module manifest is missing at %s\n' "$module_manifest" >&2
    exit 1
}
MODULE_VERSION="$(
    python3 - "$module_manifest" <<'PY'
import json
import re
import sys
from pathlib import Path

version = json.loads(Path(sys.argv[1]).read_text()).get("version")
if not isinstance(version, str) or re.fullmatch(r"v\d+(?:\.\d+){2,3}", version) is None:
    raise SystemExit("module manifest has an invalid version")
print(version[1:])
PY
)"
out_dir="${OUT_DIR:-$root_dir/out}"
mkdir -p "$out_dir"
out_dir="$(realpath "$out_dir")"
work_dir="$(mktemp -d "$out_dir/module-package.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT


# Release repo: CI provides GITHUB_REPOSITORY, local builds fall back to
# the git remote.
repo="${GITHUB_REPOSITORY:-}"
if [ -z "$repo" ]; then
    remote="$(git -C "$root_dir" remote get-url origin 2>/dev/null || true)"
    case "$remote" in
        *github.com:*)
            repo="${remote#*github.com:}"
            repo="${repo%.git}"
            ;;
        *github.com/*)
            repo="${remote#*github.com/}"
            repo="${repo%.git}"
            ;;
    esac
fi
[ -n "$repo" ] || {
    printf 'warning: cannot determine GitHub repo; update.json will use a placeholder\n' >&2
    repo='OWNER/REPO'
}

# "0.1.0.2" -> 10002: base-100 per component, no leading zeros.
version_code=0
IFS=. read -r -a parts <<EOF
$MODULE_VERSION
EOF
for part in "${parts[@]}"; do
    version_code=$((version_code * 100 + part))
done

mkdir -p "$work_dir/module"
cp "$module_dir/common.sh" "$module_dir/customize.sh" \
    "$module_dir/service.sh" "$module_dir/boot-completed.sh" \
    "$module_dir/watchdog.sh" "$module_dir/uninstall.sh" \
    "$module_dir/action.sh" "$work_dir/module/"

update_json_url="https://raw.githubusercontent.com/${repo}/main/module/update.json"

sed -e "s/@VERSION@/v${MODULE_VERSION}/" \
    -e "s/@VERSION_CODE@/$version_code/" \
    -e "s|@UPDATE_JSON_URL@|$update_json_url|" \
    "$module_dir/module.prop" >"$work_dir/module/module.prop"

cp -r "$module_dir/webroot" "$work_dir/module/webroot"

# The installed module reads this committed manifest from main; every release
# points it at an immutable module asset tag.
cp "$module_manifest" "$out_dir/shinobu-battery.json"

chmod 755 "$work_dir/module/service.sh" "$work_dir/module/action.sh" \
    "$work_dir/module/customize.sh" "$work_dir/module/boot-completed.sh" \
    "$work_dir/module/watchdog.sh" "$work_dir/module/uninstall.sh"

# Stable name: the manifest's zipUrl points here.
module_zip="$out_dir/shinobu-battery.zip"
rm -f "$module_zip" "$module_zip.sha"
python3 - "$work_dir/module" "$module_zip" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        info = zipfile.ZipInfo(path.relative_to(root).as_posix(), (1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = path.stat().st_mode << 16
        archive.writestr(info, path.read_bytes())
PY
(cd "$out_dir" && sha256sum "$(basename "$module_zip")" >"$(basename "$module_zip").sha")

printf 'Created %s (+ .sha)\n' "$module_zip"
