#!/usr/bin/env bash
# build_gstreamer_so.sh — Build libgstreamer_android.so for all target ABIs.
#
# Generates libgstreamer_android.so for each ABI defined in config/gstreamer.env,
# strips debug symbols, and saves output to artifacts/<abi>/.
#
# Usage:
#   scripts/build_gstreamer_so.sh          # all ABIs from config
#   scripts/build_gstreamer_so.sh --force  # rebuild even if artifacts exist
#
# Prerequisites:
#   - sdk/ must exist (run scripts/download_gstreamer_sdk.sh first)
#   - ANDROID_HOME must point to the Android SDK

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors and helpers
# ---------------------------------------------------------------------------
info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33mWARN:\033[0m %s\n" "$*"; }
error() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config/gstreamer.env"
PLUGINS_MK="${REPO_ROOT}/config/plugins.mk"
APPLICATION_MK="${REPO_ROOT}/config/Application.mk"

[[ -f "$CONFIG_FILE" ]] || error "Config file not found: $CONFIG_FILE"
[[ -f "$PLUGINS_MK" ]] || error "Plugins file not found: $PLUGINS_MK"
[[ -f "$APPLICATION_MK" ]] || error "Application.mk not found: $APPLICATION_MK"

source "$CONFIG_FILE"

GST_DIR="${REPO_ROOT}/sdk"
ARTIFACTS_DIR="${REPO_ROOT}/artifacts"
BUILD_DIR="${REPO_ROOT}/.build-tmp"

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
# Map NDK ABI to GStreamer SDK directory
# ---------------------------------------------------------------------------
abi_to_gst_dir() {
    case "$1" in
        arm64-v8a)   echo "arm64" ;;
        armeabi-v7a) echo "armv7" ;;
        x86_64)      echo "x86_64" ;;
        x86)         echo "x86" ;;
        *)           error "Unknown ABI: $1" ;;
    esac
}

# ---------------------------------------------------------------------------
# Find NDK
# ---------------------------------------------------------------------------
find_ndk() {
    NDK_DIR=""

    # Try specific version first
    if [[ -n "${ANDROID_HOME:-}" ]] && [[ -d "${ANDROID_HOME}/ndk/${NDK_VERSION}" ]]; then
        NDK_DIR="${ANDROID_HOME}/ndk/${NDK_VERSION}"
    elif [[ -n "${ANDROID_NDK_HOME:-}" ]] && [[ -d "$ANDROID_NDK_HOME" ]]; then
        NDK_DIR="$ANDROID_NDK_HOME"
    elif [[ -n "${ANDROID_HOME:-}" ]] && [[ -d "${ANDROID_HOME}/ndk" ]]; then
        # Fallback: highest version
        NDK_DIR="$(ls -d "${ANDROID_HOME}/ndk"/*/ 2>/dev/null | sort -V | tail -1)"
        NDK_DIR="${NDK_DIR%/}"
    fi

    if [[ -z "$NDK_DIR" ]] || [[ ! -f "${NDK_DIR}/ndk-build" ]]; then
        command -v ndk-build >/dev/null 2>&1 && NDK_DIR="$(dirname "$(command -v ndk-build)")" || \
            error "Cannot find NDK. Set ANDROID_HOME or ANDROID_NDK_HOME."
    fi

    NDK_BUILD="${NDK_DIR}/ndk-build"
    local actual_version
    actual_version="$(grep 'Pkg.Revision' "${NDK_DIR}/source.properties" 2>/dev/null | cut -d= -f2 | tr -d ' ')" || true
    info "NDK: ${NDK_DIR} (version ${actual_version:-unknown})"
}

# ---------------------------------------------------------------------------
# Build .so for one ABI
# ---------------------------------------------------------------------------
build_so_for_abi() {
    local abi="$1"
    local gst_dir
    gst_dir=$(abi_to_gst_dir "$abi")
    local gst_root="${GST_DIR}/${gst_dir}"
    local out_dir="${ARTIFACTS_DIR}/${abi}"
    local out_so="${out_dir}/libgstreamer_android.so"

    [[ -d "$gst_root" ]] || error "GStreamer SDK not found at ${gst_root}. Run scripts/download_gstreamer_sdk.sh first."

    if [[ -f "$out_so" ]] && [[ "$FORCE" == false ]]; then
        info "[${abi}] Already built ($(du -h "$out_so" | cut -f1)). Use --force to rebuild."
        return 0
    fi

    info "[${abi}] Building libgstreamer_android.so..."

    # Create temporary Android.mk that includes our plugins config
    local tmp_dir="${BUILD_DIR}/${abi}"
    mkdir -p "$tmp_dir"

    local tmp_android_mk="${tmp_dir}/Android.mk"
    local gst_ndk_build_path="${gst_root}/share/gst-android/ndk-build"

    # Read plugins list from config/plugins.mk
    local plugins_list
    plugins_list=$(grep -E '^GSTREAMER_PLUGINS|^[[:space:]]' "$PLUGINS_MK" | \
        grep -v '\\$' | tr -d '\\' | tr '\n' ' ' | \
        sed 's/GSTREAMER_PLUGINS *:=//g' | tr -s ' ' | xargs)

    cat > "$tmp_android_mk" <<ANDROID_MK
LOCAL_PATH := \$(call my-dir)

include \$(CLEAR_VARS)
LOCAL_MODULE    := gstreamer_android_dummy
LOCAL_SRC_FILES :=
include \$(BUILD_SHARED_LIBRARY)

ifndef GSTREAMER_ROOT_ANDROID
\$(error GSTREAMER_ROOT_ANDROID is not defined!)
endif

ifeq (\$(TARGET_ARCH_ABI),arm64-v8a)
GSTREAMER_ABI_DIR := arm64
else ifeq (\$(TARGET_ARCH_ABI),armeabi-v7a)
GSTREAMER_ABI_DIR := armv7
else ifeq (\$(TARGET_ARCH_ABI),x86_64)
GSTREAMER_ABI_DIR := x86_64
else ifeq (\$(TARGET_ARCH_ABI),x86)
GSTREAMER_ABI_DIR := x86
endif

GSTREAMER_ROOT            := \$(GSTREAMER_ROOT_ANDROID)/\$(GSTREAMER_ABI_DIR)
GSTREAMER_NDK_BUILD_PATH  := \$(GSTREAMER_ROOT)/share/gst-android/ndk-build/

include \$(GSTREAMER_NDK_BUILD_PATH)/plugins.mk
ANDROID_MK

    # Append the full plugins.mk content
    cat "$PLUGINS_MK" >> "$tmp_android_mk"

    cat >> "$tmp_android_mk" <<ANDROID_MK

G_IO_MODULES         := ${G_IO_MODULES}
GSTREAMER_EXTRA_DEPS := ${GSTREAMER_EXTRA_DEPS}
GSTREAMER_EXTRA_LIBS := ${GSTREAMER_EXTRA_LIBS}

GSTREAMER_JAVA_SRC_DIR    := ${tmp_dir}/java
GSTREAMER_ASSETS_DIR      := ${tmp_dir}/assets

include \$(GSTREAMER_NDK_BUILD_PATH)/gstreamer-1.0.mk
ANDROID_MK

    mkdir -p "${tmp_dir}/java" "${tmp_dir}/assets"

    local libs_out="${tmp_dir}/libs"
    mkdir -p "$libs_out"

    info "[${abi}] Running ndk-build..."
    "$NDK_BUILD" \
        NDK_PROJECT_PATH="$tmp_dir" \
        NDK_APPLICATION_MK="$APPLICATION_MK" \
        NDK_LIBS_OUT="$libs_out" \
        APP_ABI="$abi" \
        APP_BUILD_SCRIPT="$tmp_android_mk" \
        GSTREAMER_ROOT_ANDROID="${GST_DIR}" \
        V=0 \
        -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" \
        2>&1

    # Find generated .so
    local generated_so
    generated_so=$(find "$libs_out" -name "libgstreamer_android.so" 2>/dev/null | head -1)
    if [[ -z "$generated_so" ]]; then
        generated_so=$(find "$tmp_dir" -name "libgstreamer_android.so" 2>/dev/null | head -1)
    fi
    [[ -n "$generated_so" ]] || error "[${abi}] libgstreamer_android.so not found after build!"

    local raw_size
    raw_size=$(du -h "$generated_so" | cut -f1)
    info "[${abi}] Generated .so: ${raw_size} (unstripped)"

    mkdir -p "$out_dir"
    cp "$generated_so" "$out_so"

    # Strip — try llvm-objcopy first (tolerant of malformed ELF sections)
    local objcopy_tool="${NDK_DIR}/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objcopy"
    local strip_tool="${NDK_DIR}/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip"
    [[ -f "$objcopy_tool" ]] || objcopy_tool="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy"
    [[ -f "$strip_tool" ]]   || strip_tool="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

    if [[ -f "$objcopy_tool" ]] && "$objcopy_tool" --strip-debug "$out_so" 2>/dev/null; then
        info "[${abi}] Stripped with llvm-objcopy --strip-debug"
    elif [[ -f "$strip_tool" ]] && "$strip_tool" --strip-unneeded "$out_so" 2>/dev/null; then
        info "[${abi}] Stripped with llvm-strip --strip-unneeded"
    else
        warn "[${abi}] Strip failed — keeping unstripped .so"
    fi

    local final_size
    final_size=$(du -h "$out_so" | cut -f1)
    info "[${abi}] Saved: ${out_so} (${final_size})"

    # Copy Java sources and assets
    if [[ -d "${tmp_dir}/java" ]] && [[ "$(ls -A "${tmp_dir}/java" 2>/dev/null)" ]]; then
        mkdir -p "${ARTIFACTS_DIR}/java"
        cp -R "${tmp_dir}/java"/* "${ARTIFACTS_DIR}/java/" 2>/dev/null || true
    fi

    for asset_subdir in ssl fontconfig; do
        if [[ -d "${tmp_dir}/assets/${asset_subdir}" ]]; then
            mkdir -p "${ARTIFACTS_DIR}/assets/${asset_subdir}"
            cp -R "${tmp_dir}/assets/${asset_subdir}"/* "${ARTIFACTS_DIR}/assets/${asset_subdir}/" 2>/dev/null || true
        fi
    done
}

# ---------------------------------------------------------------------------
# Generate versions.txt
# ---------------------------------------------------------------------------
generate_versions_txt() {
    local versions_file="${ARTIFACTS_DIR}/versions.txt"
    cat > "$versions_file" <<EOF
GStreamer: ${GSTREAMER_VERSION}
NDK: ${NDK_VERSION}
APP_PLATFORM: ${APP_PLATFORM}
APP_STL: ${APP_STL}
ABIs: ${ABIS}
G_IO_MODULES: ${G_IO_MODULES}
BuildDate: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF
    info "Generated versions.txt"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    info "GStreamer Android .so builder"
    echo ""

    [[ -d "$GST_DIR" ]] || error "GStreamer SDK not found at ${GST_DIR}. Run scripts/download_gstreamer_sdk.sh first."

    find_ndk
    echo ""

    mkdir -p "$ARTIFACTS_DIR"

    IFS=' ' read -ra ABI_LIST <<< "$ABIS"
    for abi in "${ABI_LIST[@]}"; do
        build_so_for_abi "$abi"
        echo ""
    done

    generate_versions_txt

    info "All ABIs built. Output in ${ARTIFACTS_DIR}/"
    for abi in "${ABI_LIST[@]}"; do
        local so="${ARTIFACTS_DIR}/${abi}/libgstreamer_android.so"
        if [[ -f "$so" ]]; then
            info "  ${abi}: $(du -h "$so" | cut -f1)"
        fi
    done
}

main "$@"