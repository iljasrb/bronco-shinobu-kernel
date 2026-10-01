#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_manifest="$root_dir/sources.env"
readonly patch_dir="$root_dir/patches"

[[ -f "$source_manifest" ]] || {
    printf 'source manifest is missing at %s\n' "$source_manifest" >&2
    exit 1
}
# shellcheck disable=SC1091
source "$source_manifest"

readonly kernel_dir="$root_dir/$KERNEL_DIRECTORY"
[[ -d "$kernel_dir/.git" ]] || {
    printf 'kernel source repository is missing at %s\n' "$kernel_dir" >&2
    exit 1
}

grep -qx "# SUSFS_REVISION=$SUSFS_REVISION" "$patch_dir/0001-susfs.patch" || {
    printf '%s\n' 'SUSFS patch does not match its pin; run scripts/refresh-susfs.sh' >&2
    exit 1
}

for patch in "$patch_dir"/*.patch; do
    patch_name="${patch#"$patch_dir"/}"

    if git -C "$kernel_dir" apply --reverse --check "$patch" 2>/dev/null; then
        printf 'Kernel patch already applied: %s\n' "$patch_name"
        continue
    fi

    if ! git -C "$kernel_dir" apply --check "$patch"; then
        printf 'cannot apply kernel patch: %s\n' "$patch_name" >&2
        exit 1
    fi

    printf 'Applying kernel patch: %s\n' "$patch_name"
    git -C "$kernel_dir" apply "$patch"
done
