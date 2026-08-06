#!/usr/bin/env bash
# Builds the flashable KernelSU module zip + sha256.
# Runs standalone or as part of build.sh (after the kernel build).
set -euo pipefail

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_manifest="$root_dir/sources.env"

[ -f "$source_manifest" ] || {
    printf 'source manifest is missing at %s\n' "$source_manifest" >&2
    exit 1
}
# shellcheck disable=SC1091
source "$source_manifest"

module_dir="$root_dir/module"
out_dir="$(realpath "${OUT_DIR:-$root_dir/out}")"
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
$PROJECT_VERSION
EOF
for part in "${parts[@]}"; do
    version_code=$((version_code * 100 + part))
done

mkdir -p "$work_dir/module"
cp "$module_dir/common.sh" "$module_dir/customize.sh" \
    "$module_dir/service.sh" "$module_dir/boot-completed.sh" \
    "$module_dir/watchdog.sh" "$module_dir/uninstall.sh" \
    "$module_dir/action.sh" "$work_dir/module/"

update_json_url="https://github.com/${repo}/releases/latest/download/shinobu-battery.json"

sed -e "s/@VERSION@/v${PROJECT_VERSION}/" \
    -e "s/@VERSION_CODE@/$version_code/" \
    -e "s|@UPDATE_JSON_URL@|$update_json_url|" \
    "$module_dir/module.prop" >"$work_dir/module/module.prop"

cp -r "$module_dir/webroot" "$work_dir/module/webroot"

# Auto-update manifest. Served from the release; the manager reads it via
# module.prop updateJson= and offers an update when versionCode is newer.
cat >"$out_dir/shinobu-battery.json" <<EOF
{
  "version": "v${PROJECT_VERSION}",
  "versionCode": ${version_code},
  "zipUrl": "https://github.com/${repo}/releases/latest/download/shinobu-battery.zip",
  "changelog": "See https://github.com/${repo}/releases"
}
EOF

chmod 755 "$work_dir/module/service.sh" "$work_dir/module/action.sh" \
    "$work_dir/module/customize.sh" "$work_dir/module/boot-completed.sh" \
    "$work_dir/module/watchdog.sh" "$work_dir/module/uninstall.sh"

# Stable name: the manifest's zipUrl points here.
module_zip="$out_dir/shinobu-battery.zip"
rm -f "$module_zip" "$module_zip.sha"
(cd "$work_dir/module" && python3 -m zipfile -c "$module_zip" .)
(cd "$out_dir" && sha256sum "$(basename "$module_zip")" >"$(basename "$module_zip").sha")

printf 'Created %s (+ .sha)\n' "$module_zip"
