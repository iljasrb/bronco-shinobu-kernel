#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly source_manifest="$root_dir/sources.env"
readonly script_dir="$root_dir/scripts"
(($# == 0)) || {
    printf '%s\n' 'Usage: ./build.sh' >&2
    exit 2
}

[[ -f "$source_manifest" ]] || {
    printf 'source manifest is missing at %s\n' "$source_manifest" >&2
    exit 1
}
# shellcheck disable=SC1091
source "$source_manifest"

printf '%s\n' 'ThinkPhone Shinobu Kernel'
printf 'Project version: %s\n' "$PROJECT_VERSION"
printf 'Kernel revision: %s\n' "$KERNEL_REVISION"
printf 'Boot image: %s\n' "${INPUT_BOOT_IMG:-$root_dir/inputs/boot.img}"
printf 'Output image: %s\n' "${OUTPUT_BOOT_IMG:-$root_dir/out/boot-custom.img}"

"$script_dir/integrate-bakasu.sh"
"$script_dir/apply-patches.sh"
"$script_dir/integrate-nomount.sh"

"$script_dir/fetch-boot-image.sh"
"$script_dir/build-kernel.sh"
"$script_dir/make-boot-image.sh"

readonly out_dir="${OUT_DIR:-$root_dir/out}"
readonly output_boot_img="${OUTPUT_BOOT_IMG:-$out_dir/boot-custom.img}"
readonly input_boot_img="${INPUT_BOOT_IMG:-$root_dir/inputs/boot.img}"
readonly manifest_path="$out_dir/build-manifest"
{
    printf 'project_version=%s\n' "$PROJECT_VERSION"
    printf 'project_revision=%s\n' "$(git -C "$root_dir" rev-parse HEAD)"
    printf 'project_dirty=%s\n' "$(test -z "$(git -C "$root_dir" status --porcelain)" && echo false || echo true)"
    printf 'built_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'kernel_revision=%s\n' "$(git -C "$root_dir/$KERNEL_DIRECTORY" rev-parse HEAD)"
    printf 'devicetree_revision=%s\n' \
        "$(git -C "$root_dir/$DEVICE_TREE_DIRECTORY" rev-parse HEAD)"
    printf 'bakasu_revision=%s\n' \
        "$(git -C "$root_dir/$BAKASU_DIRECTORY" rev-parse HEAD)"
    printf 'susfs_revision=%s\n' "$SUSFS_REVISION"
    printf 'nomount_revision=%s\n' \
        "$(git -C "$root_dir/$NOMOUNT_DIRECTORY" rev-parse HEAD)"
    printf 'mkbootimg_revision=%s\n' \
        "$(git -C "$root_dir/$MKBOOTIMG_DIRECTORY" rev-parse HEAD)"
    printf 'clang_ref=%s\n' "$ANDROID_CLANG_REF"
    printf 'clang_revision=%s\n' \
        "$(git -C "$root_dir/tools/android-clang" rev-parse HEAD)"
    printf 'input_boot_sha256=%s\n' \
        "$(sha256sum "$input_boot_img" | cut -d' ' -f1)"
    printf 'output_boot_sha256=%s\n' \
        "$(sha256sum "$output_boot_img" | cut -d' ' -f1)"
    printf 'config_sha256=%s\n' "$(sha256sum "$out_dir/.config" | cut -d' ' -f1)"
    printf '%s\n' '[patches]'
    (cd "$root_dir/patches" && sha256sum -- *.patch) 2>/dev/null || true
} > "$manifest_path"
printf 'Recorded build manifest at %s\n' "$manifest_path"

readonly kernel_release="$(<"$out_dir/include/config/kernel.release")"
readonly bakasu_describe="$(git -C "$root_dir/$BAKASU_DIRECTORY" describe --tags 2>/dev/null || true)"
readonly susfs_version="$(sed -n 's/^#define SUSFS_VERSION "\(.*\)"/\1/p' "$root_dir/$KERNEL_DIRECTORY/include/linux/susfs.h" 2>/dev/null | head -1)"
readonly nomount_version="$(sed -n 's/^version=//p' "$root_dir/$NOMOUNT_DIRECTORY/module/module.prop" 2>/dev/null | head -1)"
readonly release_name="shinobu-kernel-${PROJECT_VERSION}"
readonly release_img="$out_dir/$release_name.img"
readonly boot_image_directory="${BOOT_IMAGE_URL%/*}"
readonly lineageos_build="${boot_image_directory##*/}"

cp "$output_boot_img" "$release_img"
(cd "$out_dir" && sha256sum "$release_name.img" > "$release_name.img.sha")

{
    printf '# ThinkPhone Shinobu Kernel v%s\n\n' "$PROJECT_VERSION"
    printf 'Custom kernel for the Motorola ThinkPhone (bronco) on LineageOS %s.\n\n' \
        "${LINEAGE_BRANCH#lineage-}"
    printf '| | |\n'
    printf '|---|---|\n'
    printf '| LineageOS build | %s |\n' "$lineageos_build"
    printf '| Kernel | %s |\n' "$kernel_release"
    printf '| Root | BakaSU %s |\n' "$bakasu_describe"
    printf '| SUSFS | %s |\n' "$susfs_version"
    printf '| NoMount | %s |\n' "$nomount_version"
    printf '| Built | %s |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '| SHA-256 | `%s` |\n' "$(cut -d' ' -f1 "$release_img.sha")"
    printf '\nInstall a compatible BakaSU manager for root. For NoMount, flash its\n'
    printf 'metamodule too. Always flash the LineageOS build listed above. Full\n'
    printf 'instructions: README.\n'
} > "$out_dir/INFO.md"

printf 'Created %s (%s), %s.sha, INFO.md\n' "$release_img" "$output_boot_img" "$release_name"
