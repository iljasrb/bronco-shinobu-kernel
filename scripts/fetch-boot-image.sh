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

[[ -n "${BOOT_IMAGE_URL:-}" && -n "${BOOT_IMAGE_SHA256:-}" ]] || {
    printf 'BOOT_IMAGE_URL/BOOT_IMAGE_SHA256 are missing from %s\n' "$source_manifest" >&2
    exit 1
}

readonly input_boot_img="${INPUT_BOOT_IMG:-$root_dir/inputs/boot.img}"

verify() {
    printf '%s  %s\n' "$BOOT_IMAGE_SHA256" "$1" | sha256sum --check --status
}

if [[ -f "$input_boot_img" ]] && verify "$input_boot_img"; then
    printf 'boot image already present and verified: %s\n' "$input_boot_img"
    exit 0
fi

mkdir -p "$(dirname -- "$input_boot_img")"
readonly tmp="$input_boot_img.part"
rm -f "$tmp"
trap 'rm -f "$tmp"' EXIT

printf 'Downloading pinned boot image: %s\n' "$BOOT_IMAGE_URL"
curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$BOOT_IMAGE_URL"

verify "$tmp" || {
    printf 'boot image sha256 mismatch; expected %s\n' "$BOOT_IMAGE_SHA256" >&2
    exit 1
}

mv "$tmp" "$input_boot_img"
trap - EXIT
printf 'Verified boot image at %s\n' "$input_boot_img"
