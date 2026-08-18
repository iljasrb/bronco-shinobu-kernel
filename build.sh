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

"$script_dir/integrate-resukisu.sh"
"$script_dir/apply-patches.sh"

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
    printf 'built_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'kernel_revision=%s\n' "$(git -C "$root_dir/$KERNEL_DIRECTORY" rev-parse HEAD)"
    printf 'devicetree_revision=%s\n' \
        "$(git -C "$root_dir/$DEVICE_TREE_DIRECTORY" rev-parse HEAD)"
    printf 'resukisu_revision=%s\n' \
        "$(git -C "$root_dir/$RESUKISU_DIRECTORY" rev-parse HEAD)"
    printf 'mkbootimg_revision=%s\n' \
        "$(git -C "$root_dir/$MKBOOTIMG_DIRECTORY" rev-parse HEAD)"
    printf 'clang_ref=%s\n' "$ANDROID_CLANG_REF"
    printf 'clang_revision=%s\n' \
        "$(git -C "$root_dir/tools/android-clang" rev-parse HEAD)"
    printf 'input_boot_sha256=%s\n' \
        "$(sha256sum "$input_boot_img" | cut -d' ' -f1)"
    printf 'output_boot_sha256=%s\n' \
        "$(sha256sum "$output_boot_img" | cut -d' ' -f1)"
    printf '%s\n' '[patches]'
    (cd "$root_dir/patches" && sha256sum -- *.patch) 2>/dev/null || true
} > "$manifest_path"
printf 'Recorded build manifest at %s\n' "$manifest_path"

readonly kernel_release="$(<"$out_dir/include/config/kernel.release")"
readonly resukisu_describe="$(git -C "$root_dir/$RESUKISU_DIRECTORY" describe --tags 2>/dev/null || true)"
readonly susfs_version="$(sed -n 's/^#define SUSFS_VERSION "\(.*\)"/\1/p' "$root_dir/$KERNEL_DIRECTORY/include/linux/susfs.h" 2>/dev/null | head -1)"
readonly release_name="shinobu-kernel-${PROJECT_VERSION}"
readonly release_img="$out_dir/$release_name.img"
readonly boot_image_directory="${BOOT_IMAGE_URL%/*}"
readonly lineageos_build="${boot_image_directory##*/}"

cp "$output_boot_img" "$release_img"
(cd "$out_dir" && sha256sum "$release_name.img" > "$release_name.img.sha")

{
    printf '# %s\n\n' "$release_name"
    printf '| field | value |\n'
    printf '|---|---|\n'
    printf '| version | %s |\n' "$PROJECT_VERSION"
    printf '| built_at | %s |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '| lineageos_build | %s |\n' "$lineageos_build"
    printf '| kernel | %s |\n' "$kernel_release"
    printf '| kernel_revision | %s |\n' "$KERNEL_REVISION"
    printf '| devicetree_revision | %s |\n' "$DEVICE_TREE_REVISION"
    printf '| resukisu | %s |\n' "$resukisu_describe"
    printf '| resukisu_revision | %s |\n' "$RESUKISU_REVISION"
    printf '| susfs | %s |\n' "$susfs_version"
    printf '| mkbootimg_revision | %s |\n' "$MKBOOTIMG_REVISION"
    printf '| clang | %s (%s) |\n' "$ANDROID_CLANG_REF" "$ANDROID_CLANG_REVISION"
    printf '| boot_image | %s |\n' "$BOOT_IMAGE_URL"
    printf '| boot_image_sha256 | %s |\n' "$BOOT_IMAGE_SHA256"
    printf '| image_sha256 | %s |\n' "$(cut -d' ' -f1 "$release_img.sha")"
} > "$out_dir/INFO.md"

printf 'Created %s (%s), %s.sha, INFO.md\n' "$release_img" "$output_boot_img" "$release_name"
