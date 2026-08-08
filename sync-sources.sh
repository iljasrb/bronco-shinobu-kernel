#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly source_manifest="$root_dir/sources.env"
reset_sources=false
pull_target=""
pins_only=false

usage() {
    cat <<'EOF'
Usage:
  ./sync-sources.sh --reset
  ./sync-sources.sh --pull-latest {all|lineage|resukisu|mkbootimg|clang} --reset
  ./sync-sources.sh --pull-latest {all|lineage|resukisu|mkbootimg|clang} --pins-only

Synchronize source trees to the exact revisions in sources.env.
--reset discards local changes and untracked files inside those source trees.
--pull-latest updates selected source pins first and saves sources.env.bak.
--pins-only updates the manifest without synchronizing source trees.
EOF
}

while (($#)); do
    case "$1" in
        --reset)
            reset_sources=true
            ;;
        --pins-only)
            pins_only=true
            ;;
        --pull-latest)
            (($# >= 2)) || { usage >&2; exit 2; }
            pull_target="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if "$pins_only"; then
    [[ -n "$pull_target" ]] || {
        printf '%s\n' '--pins-only requires --pull-latest' >&2
        exit 2
    }
else
    "$reset_sources" || {
        printf '%s\n' '--reset is required because source synchronization discards local source-tree changes' >&2
        exit 2
    }
fi

[[ -f "$source_manifest" ]] || {
    printf 'source manifest is missing at %s\n' "$source_manifest" >&2
    exit 1
}
# shellcheck disable=SC1091
source "$source_manifest"

latest_revision() {
    local repository="$1"
    local branch="$2"
    local revision=""

    while IFS=$'\t' read -r sha ref; do
        if [[ "$ref" == "refs/heads/$branch" || "$ref" == "refs/tags/$branch^{}" ]]; then
            revision="$sha"
            break
        fi
    done < <(git ls-remote "$repository" "refs/heads/$branch" "refs/tags/$branch^{}")
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || {
        printf 'could not resolve branch %s from %s\n' "$branch" "$repository" >&2
        exit 1
    }
    printf '%s\n' "$revision"
}

latest_lineage_updates() {
    local api_url="https://download.lineageos.org/api/v2/devices/bronco/builds"
    local kernel_revision device_tree_revision json metadata
    local filepath boot_url expected_sha tmp release kernel_sha sha

    kernel_revision="$(latest_revision "$KERNEL_REPOSITORY" "$KERNEL_BRANCH")"
    device_tree_revision="$(latest_revision "$DEVICE_TREE_REPOSITORY" "$DEVICE_TREE_BRANCH")"
    json="$(curl -fsSL --max-time 30 "$api_url")" || {
        printf 'could not query %s; LineageOS pins left unchanged\n' "$api_url" >&2
        return 1
    }
    metadata="$(
        BUILD_JSON="$json" LINEAGE_VERSION="${LINEAGE_BRANCH#lineage-}" python3 - <<'PY'
import json
import os

builds = json.loads(os.environ["BUILD_JSON"])
version = os.environ["LINEAGE_VERSION"]
candidates = [build for build in builds if str(build.get("version")) == version]
if not candidates:
    raise SystemExit(f"no LineageOS {version} build in API response")
build = max(candidates, key=lambda item: int(item.get("datetime", 0)))
boot = next(
    (item for item in build.get("files", []) if item.get("filename") == "boot.img"),
    None,
)
if boot is None:
    raise SystemExit(f"no boot.img in LineageOS {version} build")
print(boot.get("filepath", ""), boot.get("url", ""), boot.get("sha256", ""), sep="\t")
PY
    )" || {
        printf 'could not parse the LineageOS builds API; LineageOS pins left unchanged\n' >&2
        return 1
    }
    IFS=$'\t' read -r filepath boot_url expected_sha <<<"$metadata"
    [[ "$filepath" =~ ^/full/bronco/[0-9]{8}/boot\.img$ ]] &&
        [[ "$boot_url" == "https://mirrorbits.lineageos.org$filepath" ]] &&
        [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || {
        printf 'LineageOS API returned unexpected boot metadata; pins left unchanged\n' >&2
        return 1
    }

    tmp="$(mktemp)" || return 1
    if ! curl -fsSL --retry 3 -o "$tmp" "$boot_url"; then
        rm -f "$tmp"
        printf 'could not download %s; LineageOS pins left unchanged\n' "$boot_url" >&2
        return 1
    fi
    sha="$(sha256sum "$tmp" | cut -d' ' -f1)"
    if [[ "$sha" != "$expected_sha" ]]; then
        rm -f "$tmp"
        printf 'sha256 mismatch for %s; LineageOS pins left unchanged\n' "$boot_url" >&2
        return 1
    fi

    release="$(
        python3 - "$tmp" <<'PY'
import re
import struct
import sys

data = open(sys.argv[1], "rb").read()
if len(data) < 44 or data[:8] != b"ANDROID!":
    sys.exit("not an Android boot image")
if struct.unpack_from("<I", data, 40)[0] >= 3:
    offset = 4096
else:
    offset = struct.unpack_from("<I", data, 36)[0]
kernel_size = struct.unpack_from("<I", data, 8)[0]
if offset + kernel_size > len(data):
    sys.exit("invalid kernel bounds in boot image")
kernel = data[offset : offset + kernel_size]
if kernel[:2] == b"\x1f\x8b":
    import gzip

    kernel = gzip.decompress(kernel)
match = re.search(rb"Linux version ([0-9][^ ]*) \(", kernel)
if not match:
    sys.exit("no kernel version string in boot image")
sys.stdout.write(match.group(1).decode())
PY
    )" || {
        rm -f "$tmp"
        printf 'could not read kernel version from %s; LineageOS pins left unchanged\n' "$boot_url" >&2
        return 1
    }
    rm -f "$tmp"

    kernel_sha="${release##*-g}"
    [[ "$kernel_sha" =~ ^[0-9a-f]{12}$ ]] || {
        printf 'unexpected kernel release %s in %s; LineageOS pins left unchanged\n' \
            "$release" "$boot_url" >&2
        return 1
    }
    if [[ "${kernel_revision:0:12}" != "$kernel_sha" ]]; then
        printf 'newest LineageOS %s build ships kernel %s, branch tip is %s; LineageOS pins left unchanged\n' \
            "${LINEAGE_BRANCH#lineage-}" "$kernel_sha" "${kernel_revision:0:12}" >&2
        return 0
    fi

    printf 'KERNEL_REVISION=%s\n' "$kernel_revision"
    printf 'DEVICE_TREE_REVISION=%s\n' "$device_tree_revision"
    printf 'BOOT_IMAGE_URL=%s\n' "$boot_url"
    printf 'BOOT_IMAGE_SHA256=%s\n' "$sha"
}

update_manifest() {
    local updates="$1"

    SOURCE_MANIFEST="$source_manifest" \
        BACKUP_MANIFEST="$root_dir/sources.env.bak" \
        MANIFEST_UPDATES="$updates" python3 - <<'PY'
from pathlib import Path
import os
import re
import shutil

manifest = Path(os.environ["SOURCE_MANIFEST"])
backup = Path(os.environ["BACKUP_MANIFEST"])
lines = os.environ["MANIFEST_UPDATES"].splitlines()
updates = dict(line.split("=", 1) for line in lines)
if len(updates) != len(lines):
    raise SystemExit("duplicate source-manifest update")

patterns = {
    "KERNEL_REVISION": r"[0-9a-f]{40}",
    "DEVICE_TREE_REVISION": r"[0-9a-f]{40}",
    "RESUKISU_REVISION": r"[0-9a-f]{40}",
    "MKBOOTIMG_REVISION": r"[0-9a-f]{40}",
    "ANDROID_CLANG_REVISION": r"[0-9a-f]{40}",
    "BOOT_IMAGE_URL": r"https://mirrorbits\.lineageos\.org/full/bronco/[0-9]{8}/boot\.img",
    "BOOT_IMAGE_SHA256": r"[0-9a-f]{64}",
}
for key, value in updates.items():
    if key not in patterns or re.fullmatch(patterns[key], value) is None:
        raise SystemExit(f"invalid {key} update")

original = manifest.read_text()
text = original
for key, value in updates.items():
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
    text, count = pattern.subn(f'{key}="{value}"', text)
    if count != 1:
        raise SystemExit(f"expected one {key} entry in {manifest}, found {count}")

if text == original:
    print("unchanged")
else:
    temporary = manifest.with_name(f".{manifest.name}.tmp")
    shutil.copy2(manifest, backup)
    temporary.write_text(text)
    temporary.chmod(manifest.stat().st_mode)
    os.replace(temporary, manifest)
    print("updated")
PY
}

pull_latest() {
    local updates="" lineage_updates="" result

    case "$pull_target" in
        all)
            lineage_updates="$(latest_lineage_updates)"
            [[ -z "$lineage_updates" ]] || updates+="$lineage_updates"$'\n'
            updates+="RESUKISU_REVISION=$(latest_revision "$RESUKISU_REPOSITORY" "$RESUKISU_BRANCH")"$'\n'
            updates+="MKBOOTIMG_REVISION=$(latest_revision "$MKBOOTIMG_REPOSITORY" "$MKBOOTIMG_BRANCH")"$'\n'
            updates+="ANDROID_CLANG_REVISION=$(latest_revision "$ANDROID_CLANG_REPOSITORY" "$ANDROID_CLANG_REF")"$'\n'
            ;;
        lineage)
            updates="$(latest_lineage_updates)"
            ;;
        resukisu)
            updates="RESUKISU_REVISION=$(latest_revision "$RESUKISU_REPOSITORY" "$RESUKISU_BRANCH")"
            ;;
        mkbootimg)
            updates="MKBOOTIMG_REVISION=$(latest_revision "$MKBOOTIMG_REPOSITORY" "$MKBOOTIMG_BRANCH")"
            ;;
        clang)
            updates="ANDROID_CLANG_REVISION=$(latest_revision "$ANDROID_CLANG_REPOSITORY" "$ANDROID_CLANG_REF")"
            ;;
        *)
            printf 'unknown latest source target: %s\n' "$pull_target" >&2
            exit 2
            ;;
    esac

    if [[ -z "$updates" ]]; then
        printf 'no compatible %s source update is available\n' "$pull_target"
        return 0
    fi
    result="$(update_manifest "$updates")"
    if [[ "$result" == "unchanged" ]]; then
        printf 'source pins are already current in %s\n' "$source_manifest"
        return 0
    fi

    # shellcheck disable=SC1090
    source "$source_manifest"
    printf 'updated source pins in %s; previous values are in %s\n' \
        "$source_manifest" "$root_dir/sources.env.bak"
}

prepare_repository() {
    local directory="$1"
    local repository="$2"
    local revision="$3"
    local path="$root_dir/$directory"

    if [[ ! -d "$path/.git" ]]; then
        mkdir -p "$(dirname -- "$path")"
        git init "$path"
        git -C "$path" remote add origin "$repository"
    fi

    [[ "$(git -C "$path" remote get-url origin)" == "$repository" ]] || {
        printf 'unexpected origin for %s\n' "$path" >&2
        exit 1
    }

    if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
        git -C "$path" reset --hard
        git -C "$path" clean -fd
    fi

    git -C "$path" fetch --depth 1 origin "$revision"
    git -C "$path" checkout --detach FETCH_HEAD
}

prepare_android_clang() {
    local path="$root_dir/tools/android-clang"

    [[ -n "$ANDROID_CLANG_REVISION" ]] || {
        printf 'ANDROID_CLANG_REVISION is missing from %s; run sync-sources.sh --pull-latest clang --reset\n' \
            "$source_manifest" >&2
        exit 1
    }

    if [[ ! -d "$path/.git" ]]; then
        mkdir -p "$(dirname -- "$path")"
        git clone --depth 1 --branch "$ANDROID_CLANG_REF" --filter=blob:none --sparse \
            "$ANDROID_CLANG_REPOSITORY" "$path"
    else
        [[ "$(git -C "$path" remote get-url origin)" == "$ANDROID_CLANG_REPOSITORY" ]] || {
            printf 'unexpected origin for %s\n' "$path" >&2
            exit 1
        }
        if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
            git -C "$path" reset --hard
            git -C "$path" clean -fd
        fi
    fi

    git -C "$path" fetch --depth 1 origin "$ANDROID_CLANG_REVISION"
    git -C "$path" checkout --detach FETCH_HEAD
    git -C "$path" sparse-checkout set "$ANDROID_CLANG_DIRECTORY"
}

if [[ -n "$pull_target" ]]; then
    pull_latest
fi
"$pins_only" && exit 0

prepare_repository "$KERNEL_DIRECTORY" "$KERNEL_REPOSITORY" "$KERNEL_REVISION"
prepare_repository "$DEVICE_TREE_DIRECTORY" "$DEVICE_TREE_REPOSITORY" "$DEVICE_TREE_REVISION"
prepare_repository "$RESUKISU_DIRECTORY" "$RESUKISU_REPOSITORY" "$RESUKISU_REVISION"
prepare_repository "$MKBOOTIMG_DIRECTORY" "$MKBOOTIMG_REPOSITORY" "$MKBOOTIMG_REVISION"
prepare_android_clang
