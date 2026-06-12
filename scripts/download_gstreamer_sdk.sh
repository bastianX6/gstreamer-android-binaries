#!/usr/bin/env bash
# download_gstreamer_sdk.sh — Download and patch GStreamer Android SDK.
#
# Downloads the official GStreamer universal Android binaries,
# extracts them to sdk/ at the repo root, and applies the patches
# required for building with AGP 9 + NDK 28+.
#
# Usage:
#   scripts/download_gstreamer_sdk.sh          # from repo root
#   scripts/download_gstreamer_sdk.sh --force  # re-download even if present
#
# Requirements: curl, tar (with xz support), sed, find

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors and helpers
# ---------------------------------------------------------------------------
info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33mWARN:\033[0m %s\n" "$*"; }
error() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Configuration (loaded from config/gstreamer.env)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config/gstreamer.env"

[[ -f "$CONFIG_FILE" ]] || error "Config file not found: $CONFIG_FILE"
# shellcheck source=../config/gstreamer.env
source "$CONFIG_FILE"

DEST_DIR="${REPO_ROOT}/sdk"
# GStreamer SDK internal ABI dirs (different naming from NDK ABIs)
GST_ABIS=(arm64 armv7 x86_64)

FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
check_deps() {
    for cmd in curl tar sed find; do
        command -v "$cmd" >/dev/null 2>&1 || error "'$cmd' is required but not found"
    done
}

# ---------------------------------------------------------------------------
# Step 1: Download
# ---------------------------------------------------------------------------
download_gstreamer() {
    local tarball="${REPO_ROOT}/gstreamer-1.0-android-universal-${GSTREAMER_VERSION}.tar.xz"

    if [[ -d "${DEST_DIR}/arm64/lib" ]] && [[ "$FORCE" == false ]]; then
        info "GStreamer SDK already present at ${DEST_DIR}. Use --force to re-download."
        return 0
    fi

    if [[ -f "$tarball" ]] && [[ "$FORCE" == false ]]; then
        info "Tarball already downloaded: $tarball"
    else
        info "Downloading GStreamer ${GSTREAMER_VERSION} for Android (~940 MB)..."
        curl -L --progress-bar -o "$tarball" "$GSTREAMER_URL"
    fi

    info "Extracting to ${DEST_DIR}/ ..."
    rm -rf "$DEST_DIR"
    mkdir -p "$DEST_DIR"
    tar -xf "$tarball" -C "$DEST_DIR"

    info "Removing tarball..."
    rm -f "$tarball"
}

# ---------------------------------------------------------------------------
# Step 2: Patch .la files
# ---------------------------------------------------------------------------
patch_la_files() {
    info "Patching .la files (fixing libdir paths)..."

    local old_prefix="/home/nirbheek/projects/repos/cerbero.git/1.28/build/dist/android_universal"
    local count=0

    for abi in "${GST_ABIS[@]}"; do
        local abi_dir="${DEST_DIR}/${abi}"
        [[ -d "$abi_dir" ]] || { warn "ABI dir not found: $abi_dir — skipping"; continue; }

        local new_prefix="${DEST_DIR}/${abi}"
        while IFS= read -r -d '' la_file; do
            if grep -q "$old_prefix" "$la_file" 2>/dev/null; then
                sed -i.bak "s|${old_prefix}/${abi}|${new_prefix}|g" "$la_file"
                rm -f "${la_file}.bak"
                count=$((count + 1))
            fi
        done < <(find "$abi_dir" -name "*.la" -print0)
    done

    info "Patched $count .la files across ${#GST_ABIS[@]} ABIs."
}

# ---------------------------------------------------------------------------
# Step 3: Create stub .la files
# ---------------------------------------------------------------------------
create_stub_la_files() {
    info "Creating stub .la files for missing dependencies..."

    local lcevc_libs=(
        liblcevc_dec_api liblcevc_dec_api_utility liblcevc_dec_common
        liblcevc_dec_enhancement liblcevc_dec_extract liblcevc_dec_legacy
        liblcevc_dec_pipeline liblcevc_dec_pipeline_cpu liblcevc_dec_pipeline_legacy
        liblcevc_dec_pixel_processing liblcevc_dec_sequencer
    )

    local system_libs=(libm liblog libc++ libatomic libdl libiconv)

    local missing_la_libs=(
        libFLAC libSvtAv1Enc libass libavcodec libavfilter libavformat
        libbz2 libdav1d libdv libexpat libfmt libfontconfig libfreetype
        libfribidi libgdk_pixbuf-2.0 libgmodule-2.0 libgstallocators-1.0
        libgstanalytics-1.0 libgstapp-1.0 libgstaudio-1.0 libgstbase-1.0
        libgstbasecamerabinsrc-1.0 libgstcheck-1.0 libgstcodecs-1.0
        libgstcontroller-1.0 libgstfft-1.0 libgstinsertbin-1.0
        libgstpbutils-1.0 libgstphotography-1.0 libgstplayer-1.0
        libgstrtsp-1.0 libgstrtspserver-1.0 libgstsctp-1.0 libgstsdp-1.0
        libgsttag-1.0 libgsttranscoder-1.0 libgstvalidate-1.0 libgstvideo-1.0
        libgstvulkan-1.0 libgstwebrtc-1.0 libgthread-2.0 libharfbuzz-cairo
        libharfbuzz-gobject libharfbuzz-subset libintl libjpeg libltc
        libmp3lame libmpg123 libogg libopencore-amrnb libopenh264 libopenjp2
        liborc-0.4 liborc-test-0.4 libpango-1.0 libpangocairo-1.0
        libpangoft2-1.0 libpixman-1 libpng16 libproxy libpsl libqrencode
        librsvg-2 librtmp libsoup-3.0 libspeex libsqlite3 libsrt libssl
        libswresample libswscale libtheoradec libtiff libtinyalsa
        libvo-aacenc libvorbis libvvdec libwavpack libwebrtc-audio-processing-2
        libxml2 libz libzbar
    )

    local count=0
    for abi in "${GST_ABIS[@]}"; do
        local lib_dir="${DEST_DIR}/${abi}/lib"
        [[ -d "$lib_dir" ]] || continue

        for lib in "${system_libs[@]}"; do
            local la_file="${lib_dir}/${lib}.la"
            local link_name="${lib#lib}"
            cat > "$la_file" <<EOF
# ${lib}.la - stub for NDK system library
dlname=''
library_names=''
old_library=''
inherited_linker_flags=''
dependency_libs='-l${link_name}'
weak_library_names=''
current=
age=
revision=
installed=yes
shouldnotlink=no
dlopen=''
dlpreopen=''
libdir='${lib_dir}'
EOF
            count=$((count + 1))
        done

        local non_system_libs=("${lcevc_libs[@]}" "${missing_la_libs[@]}")
        for lib in "${non_system_libs[@]}"; do
            local la_file="${lib_dir}/${lib}.la"
            [[ -f "$la_file" ]] && continue
            cat > "$la_file" <<EOF
# ${lib}.la - stub
dlname=''
library_names=''
old_library='${lib}.a'
inherited_linker_flags=''
dependency_libs=''
weak_library_names=''
current=
age=
revision=
installed=yes
shouldnotlink=no
dlopen=''
dlpreopen=''
libdir='${lib_dir}'
EOF
            count=$((count + 1))
        done
    done

    info "Created $count stub .la files."
}

# ---------------------------------------------------------------------------
# Step 4: Patch gstreamer-1.0.mk for AGP 9
# ---------------------------------------------------------------------------
patch_gstreamer_mk() {
    info "Patching gstreamer-1.0.mk for AGP 9 compatibility..."

    local count=0
    for abi in "${GST_ABIS[@]}"; do
        local mk_file="${DEST_DIR}/${abi}/share/gst-android/ndk-build/gstreamer-1.0.mk"
        [[ -f "$mk_file" ]] || continue

        if grep -q 'host-rm,\$(prebuilt)' "$mk_file"; then
            sed -i.bak 's|$(hide)$(call host-rm,$(prebuilt))|@echo "AGP9: keeping prebuilt .so"|' "$mk_file"
            rm -f "${mk_file}.bak"
            count=$((count + 1))
        elif grep -q 'AGP9: keeping prebuilt' "$mk_file"; then
            : # Already patched
        else
            warn "Could not find delsharedlib pattern in $mk_file — skipping"
        fi
    done

    info "Patched gstreamer-1.0.mk in $count ABIs."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    check_deps
    info "GStreamer ${GSTREAMER_VERSION} Android SDK setup"
    info "Destination: ${DEST_DIR}"
    echo ""

    download_gstreamer
    patch_la_files
    create_stub_la_files
    patch_gstreamer_mk

    echo ""
    info "Done. GStreamer ${GSTREAMER_VERSION} SDK ready at ${DEST_DIR}/"
    info "ABIs: ${GST_ABIS[*]}"
}

main "$@"