#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly out_dir="${OUT_DIR:-$root_dir/out}"
# shellcheck disable=SC1091
source "$root_dir/sources.env"

readonly manager_dir="$root_dir/$BAKASU_DIRECTORY/manager"
readonly describe="$(git -C "$root_dir/$BAKASU_DIRECTORY" describe --tags --always)"

[[ -x "$manager_dir/gradlew" ]] || {
    printf 'BakaSU manager source is missing at %s\n' "$manager_dir" >&2
    exit 1
}

readonly keystore="$manager_dir/build/manager.keystore"
mkdir -p "${keystore%/*}"
if [[ -n "${KEYSTORE_B64:-}" ]]; then
    printf '%s' "$KEYSTORE_B64" | base64 -d > "$keystore"
else
    # ponytail: throwaway key when the BAKASU_KEYSTORE_* secrets are absent; set them
    # for a stable signature, else every build needs an uninstall before upgrading.
    password="$(openssl rand -hex 32)"
    keytool -genkeypair -keystore "$keystore" -storetype JKS -alias manager -keyalg RSA \
        -keysize 2048 -validity 3650 -storepass "$password" -keypass "$password" \
        -dname 'CN=Shinobu CI' >/dev/null 2>&1
    KEYSTORE_PASSWORD="$password" KEY_ALIAS=manager KEY_PASSWORD="$password"
fi

(cd "$manager_dir" && ./gradlew --no-daemon assembleRelease \
    "-PKEYSTORE_FILE=$keystore" \
    "-PKEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-}" \
    "-PKEY_ALIAS=${KEY_ALIAS:-}" \
    "-PKEY_PASSWORD=${KEY_PASSWORD:-}")

readonly apk="$(find "$manager_dir/app/build/outputs/apk/release" -name '*-arm64-v8a-*.apk' -print -quit)"
[[ -n "$apk" ]] || {
    printf 'arm64-v8a manager APK is missing under %s\n' "$manager_dir/app/build/outputs/apk/release" >&2
    exit 1
}

mkdir -p "$out_dir"
readonly output="$out_dir/bakasu-manager-${describe}-arm64-v8a.apk"
cp "$apk" "$output"
printf 'Built %s\n' "$output"
