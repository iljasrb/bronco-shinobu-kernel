#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly source_manifest="$root_dir/sources.env"
reset_sources=false
pull_target=""

usage() {
    cat <<'EOF'
Usage:
  ./sync-sources.sh --reset
  ./sync-sources.sh --pull-latest {all|lineage|resukisu|mkbootimg|clang} --reset

Synchronize source trees to the exact revisions in sources.env.
--reset discards local changes and untracked files inside those source trees.
--pull-latest updates selected source pins first and saves sources.env.bak.
EOF
}

while (($#)); do
    case "$1" in
        --reset)
            reset_sources=true
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

"$reset_sources" || {
    printf '%s\n' '--reset is required because source synchronization discards local source-tree changes' >&2
    exit 2
}

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
    [[ -n "$revision" ]] || {
        printf 'could not resolve branch %s from %s\n' "$branch" "$repository" >&2
        exit 1
    }
    printf '%s\n' "$revision"
}

update_boot_image_pin() {
    local api_url="https://download.lineageos.org/api/v2/devices/bronco/builds?version=${LINEAGE_BRANCH#lineage-}"
    local json filepath boot_url tmp release kernel_sha sha

    json="$(curl -fsSL --max-time 30 "$api_url")" || {
        printf 'could not query %s; boot image pin left unchanged\n' "$api_url" >&2
        return 1
    }
    filepath="$(printf '%s' "$json" | python3 -c 'import json, sys; sys.stdout.write(json.load(sys.stdin)[0]["files"][0]["filepath"])')" || {
        printf 'could not parse LineageOS builds API; boot image pin left unchanged\n' >&2
        return 1
    }
    boot_url="https://mirrorbits.lineageos.org${filepath%/*}/boot.img"
    tmp="$(mktemp)" || return 1

    if ! curl -fsSL --retry 3 -o "$tmp" "$boot_url"; then
        rm -f "$tmp"
        printf 'could not download %s; boot image pin left unchanged\n' "$boot_url" >&2
        return 1
    fi

    release="$(
        python3 - "$tmp" <<'PY'
import re
import struct
import sys

data = open(sys.argv[1], "rb").read()
if data[:8] != b"ANDROID!":
    sys.exit("not an Android boot image")
if struct.unpack_from("<I", data, 40)[0] >= 3:
    offset = 4096
else:
    offset = struct.unpack_from("<I", data, 36)[0]
kernel = data[offset : offset + struct.unpack_from("<I", data, 8)[0]]
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
        printf 'could not read kernel version from %s; boot image pin left unchanged\n' "$boot_url" >&2
        return 1
    }

    sha="$(sha256sum "$tmp" | cut -d' ' -f1)"
    rm -f "$tmp"

    kernel_sha="${release##*-g}"
    if [[ "${KERNEL_REVISION:0:12}" != "$kernel_sha" ]]; then
        printf 'newest nightly %s ships kernel %s, pinned kernel is %s; boot image pin left unchanged — re-run after the next nightly\n' \
            "$(basename "$(dirname "$filepath")")" "$kernel_sha" "${KERNEL_REVISION:0:12}" >&2
        return 1
    fi

    printf 'BOOT_IMAGE_URL=%s\n' "$boot_url"
    printf 'BOOT_IMAGE_SHA256=%s\n' "$sha"
}

update_manifest() {
    local updates="$1"

    cp "$source_manifest" "$root_dir/sources.env.bak"
    SOURCE_MANIFEST="$source_manifest" MANIFEST_UPDATES="$updates" python3 - <<'PY'
from pathlib import Path
import os
import re

manifest = Path(os.environ["SOURCE_MANIFEST"])
updates = dict(line.split("=", 1) for line in os.environ["MANIFEST_UPDATES"].splitlines())
text = manifest.read_text()
for key, value in updates.items():
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
    text, count = pattern.subn(f'{key}="{value}"', text)
    if count != 1:
        raise SystemExit(f"expected one {key} entry in {manifest}, found {count}")
manifest.write_text(text)
PY
}

pull_latest() {
    local updates=""

    case "$pull_target" in
        all)
            updates+="KERNEL_REVISION=$(latest_revision "$KERNEL_REPOSITORY" "$KERNEL_BRANCH")"$'\n'
            updates+="DEVICE_TREE_REVISION=$(latest_revision "$DEVICE_TREE_REPOSITORY" "$DEVICE_TREE_BRANCH")"$'\n'
            updates+="RESUKISU_REVISION=$(latest_revision "$RESUKISU_REPOSITORY" "$RESUKISU_BRANCH")"$'\n'
            updates+="MKBOOTIMG_REVISION=$(latest_revision "$MKBOOTIMG_REPOSITORY" "$MKBOOTIMG_BRANCH")"$'\n'
            updates+="ANDROID_CLANG_REVISION=$(latest_revision "$ANDROID_CLANG_REPOSITORY" "$ANDROID_CLANG_REF")"$'\n'
            ;;
        lineage)
            updates+="KERNEL_REVISION=$(latest_revision "$KERNEL_REPOSITORY" "$KERNEL_BRANCH")"$'\n'
            updates+="DEVICE_TREE_REVISION=$(latest_revision "$DEVICE_TREE_REPOSITORY" "$DEVICE_TREE_BRANCH")"$'\n'
            ;;
        resukisu)
            updates+="RESUKISU_REVISION=$(latest_revision "$RESUKISU_REPOSITORY" "$RESUKISU_BRANCH")"$'\n'
            ;;
        mkbootimg)
            updates+="MKBOOTIMG_REVISION=$(latest_revision "$MKBOOTIMG_REPOSITORY" "$MKBOOTIMG_BRANCH")"$'\n'
            ;;
        clang)
            updates+="ANDROID_CLANG_REVISION=$(latest_revision "$ANDROID_CLANG_REPOSITORY" "$ANDROID_CLANG_REF")"$'\n'
            ;;
        *)
            printf 'unknown latest source target: %s\n' "$pull_target" >&2
            exit 2
            ;;
    esac

    case "$pull_target" in
        all|lineage)
            if boot_updates="$(update_boot_image_pin)"; then
                updates+="$boot_updates"$'\n'
            fi
            ;;
    esac

    update_manifest "$updates"
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

prepare_repository "$KERNEL_DIRECTORY" "$KERNEL_REPOSITORY" "$KERNEL_REVISION"
prepare_repository "$DEVICE_TREE_DIRECTORY" "$DEVICE_TREE_REPOSITORY" "$DEVICE_TREE_REVISION"
prepare_repository "$RESUKISU_DIRECTORY" "$RESUKISU_REPOSITORY" "$RESUKISU_REVISION"
prepare_repository "$MKBOOTIMG_DIRECTORY" "$MKBOOTIMG_REPOSITORY" "$MKBOOTIMG_REVISION"
prepare_android_clang
