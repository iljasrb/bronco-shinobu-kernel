#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly source_manifest="$root_dir/sources.env"
readonly script_dir="$root_dir/scripts"
assume_yes=false
integrate_resukisu=true
apply_patches=true

usage() {
    cat <<'EOF'
Usage: ./build.sh [--yes] [--skip-resukisu] [--skip-patches]

Build and package the ThinkPhone Shinobu kernel.

Options:
  -y, --yes           integrate ReSukiSU and apply patches without prompting
      --skip-resukisu build without integrating ReSukiSU
      --skip-patches  build without applying patches from patches/
  -h, --help          show this help
EOF
}

while (($#)); do
    case "$1" in
        -y|--yes)
            assume_yes=true
            ;;
        --skip-resukisu)
            integrate_resukisu=false
            ;;
        --skip-patches)
            apply_patches=false
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

confirm() {
    local action="$1"
    local answer

    if "$assume_yes"; then
        return 0
    fi

    [[ -t 0 ]] || {
        printf 'cannot prompt to %s without a terminal; rerun with --yes or a --skip-* option\n' \
            "$action" >&2
        exit 2
    }

    while true; do
        read -r -p "$action? [Y/n] " answer
        case "${answer,,}" in
            ''|y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                printf 'answer yes or no\n' >&2
                ;;
        esac
    done
}

if "$integrate_resukisu" && confirm 'Integrate ReSukiSU'; then
    "$script_dir/integrate-resukisu.sh"
fi

if "$apply_patches" && confirm 'Apply kernel patches'; then
    "$script_dir/apply-patches.sh"
fi

"$script_dir/fetch-boot-image.sh"
"$script_dir/build-kernel.sh"
"$script_dir/make-boot-image.sh"
"$script_dir/build-module.sh"

readonly out_dir="${OUT_DIR:-$root_dir/out}"
readonly output_boot_img="${OUTPUT_BOOT_IMG:-$out_dir/boot-custom.img}"
readonly manifest_path="$out_dir/build-manifest"
{
    printf 'project_version=%s\n' "$PROJECT_VERSION"
    printf 'built_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'kernel_revision=%s\n' "$KERNEL_REVISION"
    printf 'kernel_head=%s\n' "$(git -C "$root_dir/$KERNEL_DIRECTORY" rev-parse HEAD)"
    printf 'devicetree_revision=%s\n' "$DEVICE_TREE_REVISION"
    printf 'resukisu_revision=%s\n' "$RESUKISU_REVISION"
    printf 'mkbootimg_revision=%s\n' "$MKBOOTIMG_REVISION"
    printf 'clang_ref=%s\n' "$ANDROID_CLANG_REF"
    printf 'clang_revision=%s\n' "$(git -C "$root_dir/tools/android-clang" rev-parse HEAD)"
    printf 'flake_lock_sha256=%s\n' "$(sha256sum "$root_dir/flake.lock" | cut -d' ' -f1)"
    printf 'boot_image_sha256=%s\n' "$(sha256sum "$output_boot_img" | cut -d' ' -f1)"
    printf 'module_version=%s\n' "$PROJECT_VERSION"
    printf 'module_zip_sha256=%s\n' "$(sha256sum "$out_dir/shinobu-battery.zip" | cut -d' ' -f1)"
    printf '%s\n' '[patches]'
    (cd "$root_dir/patches" && sha256sum -- *.patch) 2>/dev/null || true
} > "$manifest_path"
printf 'Recorded build manifest at %s\n' "$manifest_path"

readonly kernel_release="$(<"$out_dir/include/config/kernel.release")"
readonly resukisu_describe="$(git -C "$root_dir/$RESUKISU_DIRECTORY" describe --tags 2>/dev/null || true)"
readonly susfs_version="$(sed -n 's/^#define SUSFS_VERSION "\(.*\)"/\1/p' "$root_dir/$KERNEL_DIRECTORY/include/linux/susfs.h" 2>/dev/null | head -1)"
readonly release_name="shinobu-kernel-${PROJECT_VERSION}"
readonly release_img="$out_dir/$release_name.img"

cp "$output_boot_img" "$release_img"
(cd "$out_dir" && sha256sum "$release_name.img" > "$release_name.img.sha")

{
    printf '# %s\n\n' "$release_name"
    printf '| field | value |\n'
    printf '|---|---|\n'
    printf '| version | %s |\n' "$PROJECT_VERSION"
    printf '| built_at | %s |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
    printf '| module | shinobu-battery v%s (%s) |\n' "$PROJECT_VERSION" \
        "$(cut -d' ' -f1 "$out_dir/shinobu-battery.zip.sha")"
} > "$out_dir/INFO.md"

printf 'Created %s (%s), %s.sha, INFO.md\n' "$release_img" "$output_boot_img" "$release_name"
