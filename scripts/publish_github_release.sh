#!/usr/bin/env bash
# publish_github_release.sh — Publish GitHub Release with prebuilt GStreamer .so files.
#
# Usage:
#   scripts/publish_github_release.sh [--tag <tag>] [--title <title>] [--repo <owner/name>]
#                                     [--draft] [--prerelease] [--skip-build]

set -euo pipefail

info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33mWARN:\033[0m %s\n" "$*"; }
error() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG=""
TITLE=""
REPO=""
DRAFT=false
PRERELEASE=false
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)        TAG="$2"; shift 2 ;;
        --title)      TITLE="$2"; shift 2 ;;
        --repo)       REPO="$2"; shift 2 ;;
        --draft)      DRAFT=true; shift ;;
        --prerelease) PRERELEASE=true; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        -h|--help)
            cat <<'USAGE'
Usage:
  scripts/publish_github_release.sh [--tag <tag>] [--title <title>] [--repo <owner/name>]
                                     [--draft] [--prerelease] [--skip-build]
USAGE
            exit 0 ;;
        *) error "Unknown argument: $1" ;;
    esac
done

# Check gh CLI
command -v gh >/dev/null 2>&1 || error "GitHub CLI (gh) is required: https://cli.github.com"

# Warn about env tokens
if [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
    warn "GH_TOKEN/GITHUB_TOKEN is set. Ensure it has repo+workflow scopes."
fi

# Verify OAuth scopes
oauth_scopes="$(gh api -i /user --silent 2>&1 | awk 'BEGIN { IGNORECASE = 1 } /^X-Oauth-Scopes:/ { print $0 }')"
if [[ "$oauth_scopes" != *repo* || "$oauth_scopes" != *workflow* ]]; then
    warn "Token may lack repo/workflow scopes. Observed: ${oauth_scopes:-unknown}"
    warn "Run: gh auth refresh -h github.com -s repo -s workflow"
fi

# Build if needed
if [[ "$SKIP_BUILD" != true ]]; then
    info "Running download_gstreamer_sdk.sh..."
    "${ROOT_DIR}/scripts/download_gstreamer_sdk.sh"
    info "Running build_gstreamer_so.sh..."
    "${ROOT_DIR}/scripts/build_gstreamer_so.sh"
fi

# Package
info "Running package_release.sh..."
package_output="$("${ROOT_DIR}/scripts/package_release.sh")"
archive_path="$(printf '%s\n' "$package_output" | sed -n '1p')"
checksum_path="$(printf '%s\n' "$package_output" | sed -n '2p')"

[[ -n "$archive_path" && -f "$archive_path" ]] || error "Archive not found: ${archive_path}"
[[ -n "$checksum_path" && -f "$checksum_path" ]] || error "Checksum not found: ${checksum_path}"

# Determine tag
if [[ -z "$TAG" ]]; then
    if [[ -f "${ROOT_DIR}/artifacts/versions.txt" ]]; then
        TAG="$(awk '/^GStreamer:/ { print $2 }' "${ROOT_DIR}/artifacts/versions.txt")"
    fi
    if [[ -z "$TAG" ]] && [[ -f "${ROOT_DIR}/VERSION" ]]; then
        TAG="$(awk 'NF { print $1; exit }' "${ROOT_DIR}/VERSION")"
    fi
    [[ -n "$TAG" ]] || error "Cannot determine tag. Pass --tag or ensure VERSION file exists."
fi

[[ -z "$TITLE" ]] && TITLE="GStreamer Android ${TAG}"

# Release notes
release_notes="$(mktemp)"
trap 'rm -f "$release_notes"' EXIT
cat > "$release_notes" <<NOTES
Pre-built GStreamer Android binaries.

$(cat "${ROOT_DIR}/artifacts/versions.txt" 2>/dev/null || echo "No versions.txt found")
NOTES

info "Publishing GitHub Release ${TAG}..."
gh_args=(release create "$TAG" "$archive_path" "$checksum_path" \
    --title "$TITLE" \
    --notes-file "$release_notes")

[[ -n "$REPO" ]] && gh_args+=(--repo "$REPO")
[[ "$DRAFT" == true ]] && gh_args+=(--draft)
[[ "$PRERELEASE" == true ]] && gh_args+=(--prerelease)

gh "${gh_args[@]}"
info "Release published: ${TAG}"