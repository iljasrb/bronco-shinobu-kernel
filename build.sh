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

"$script_dir/build-kernel.sh"
"$script_dir/make-boot-image.sh"

printf 'Created %s\n' "${OUTPUT_BOOT_IMG:-$root_dir/out/boot-custom.img}"
