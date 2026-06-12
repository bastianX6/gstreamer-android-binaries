# gstreamer-android-binaries

Pre-built `libgstreamer_android.so` for Android, packaged for use as a GitHub Release asset.

## Overview

This repository builds and publishes `libgstreamer_android.so` for three Android ABIs:
- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

The binaries are consumed by the [multiview-tv-android](https://github.com/bastianX6/multiview-tv-android) project to avoid building GStreamer from source on every CI run.

## Versions

| Component | Version |
|---|---|
| GStreamer | 1.28.3 |
| Android NDK | 30.0.14904198 |
| APP_PLATFORM | android-29 |
| APP_STL | c++_shared |

## Usage

Download the latest release asset and extract it. The zip contains:
- `arm64-v8a/libgstreamer_android.so`
- `armeabi-v7a/libgstreamer_android.so`
- `x86_64/libgstreamer_android.so`
- `java/` — GStreamer Java sources
- `assets/` — SSL certs, fontconfig
- `versions.txt` — Build metadata

## Building

```bash
# 1. Download and patch the GStreamer SDK (~940 MB)
scripts/download_gstreamer_sdk.sh

# 2. Build .so for all 3 ABIs
scripts/build_gstreamer_so.sh

# 3. Package into zip
scripts/package_release.sh

# 4. Publish GitHub Release
scripts/publish_github_release.sh
```

## Structure

```
gstreamer-android-binaries/
  VERSION                   # e.g. "1.28.3.1"
  config/
    gstreamer.env           # Pinned versions
    plugins.mk              # GStreamer plugin list
    Application.mk          # APP_STL, APP_PLATFORM
  scripts/
    download_gstreamer_sdk.sh
    build_gstreamer_so.sh
    package_release.sh
    publish_github_release.sh
  artifacts/                # Build output (gitignored)
  dist/                     # Release zip (gitignored)
  sdk/                      # GStreamer SDK (gitignored)
```