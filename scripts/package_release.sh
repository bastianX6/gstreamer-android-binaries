#!/usr/bin/env bash
# package_release.sh — Package artifacts into a zip for GitHub Release.
#
# Usage:
#   scripts/package_release.sh [--artifacts-dir <path>] [--dist-dir <path>]

set -euo pipefail

info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
error() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
DIST_DIR="${ROOT_DIR}/dist"
VERSION_FILE="${ROOT_DIR}/VERSION"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
        --dist-dir)      DIST_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--artifacts-dir <path>] [--dist-dir <path>]"
            exit 0 ;;
        *) error "Unknown argument: $1" ;;
    esac
done

# Verify required artifacts
for required in versions.txt; do
    [[ -e "${ARTIFACTS_DIR}/${required}" ]] || error "Missing artifact: ${ARTIFACTS_DIR}/${required}"
done

# Verify at least one ABI .so exists
found_so=false
for abi in arm64-v8a armeabi-v7a x86_64; do
    [[ -f "${ARTIFACTS_DIR}/${abi}/libgstreamer_android.so" ]] && found_so=true && break
done
[[ "$found_so" == true ]] || error "No libgstreamer_android.so found in ${ARTIFACTS_DIR}/<abi>/"

mkdir -p "$DIST_DIR"

# Determine version (prefer VERSION file over versions.txt GStreamer version)
release_version=""
if [[ -f "$VERSION_FILE" ]]; then
    release_version="$(awk 'NF { print $1; exit }' "$VERSION_FILE")"
fi
if [[ -z "$release_version" ]] && [[ -f "${ARTIFACTS_DIR}/versions.txt" ]]; then
    release_version="$(awk '/^GStreamer:/ { print $2 }' "${ARTIFACTS_DIR}/versions.txt")"
fi
[[ -n "$release_version" ]] || error "Cannot determine release version"

archive_name="gstreamer-android-${release_version}.zip"
archive_path="${DIST_DIR}/${archive_name}"

info "Packaging artifacts to ${archive_path}..."
rm -f "$archive_path"
(
    cd "$(dirname "$ARTIFACTS_DIR")"
    zip -qry "$archive_path" "$(basename "$ARTIFACTS_DIR")"
)

shasum -a 256 "$archive_path" > "${archive_path}.sha256"

info "Created: ${archive_path} ($(du -h "$archive_path" | cut -f1))"
info "SHA256:  ${archive_path}.sha256"

echo "$archive_path"
echo "${archive_path}.sha256"