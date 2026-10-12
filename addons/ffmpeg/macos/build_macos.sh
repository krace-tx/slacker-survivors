#!/usr/bin/env bash
set -e

echo "[EIRTeam.FFmpeg] Starting macOS Universal (arm64 + x86_64) GDExtension build..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/ffmpeg-macos-build"

if [ -d "$BUILD_DIR" ]; then
    echo "[INFO] Cleaning previous build directory $BUILD_DIR..."
    rm -rf "$BUILD_DIR"
fi

echo "[INFO] Cloning EIRTeam.FFmpeg..."
git clone --depth 1 --recursive https://github.com/EIRTeam/EIRTeam.FFmpeg.git "$BUILD_DIR"

cd "$BUILD_DIR"

echo "[INFO] Bootstrapping build tools..."
make bootstrap

echo "[INFO] Compiling macOS Universal GDExtension..."
make gdextension PLATFORM=macos

echo "[INFO] Copying compiled binaries back to $SCRIPT_DIR..."
cp -r gdextension_build/build/addons/ffmpeg/macos/* "$SCRIPT_DIR/"

echo "[INFO] Applying Ad-hoc code signing and clearing quarantine..."
xattr -cr "$SCRIPT_DIR"/*
codesign --force --deep --sign - "$SCRIPT_DIR"/libgdffmpeg.macos.template_debug.framework
codesign --force --deep --sign - "$SCRIPT_DIR"/libgdffmpeg.macos.template_release.framework
codesign --force --sign - "$SCRIPT_DIR"/*.dylib

echo "[SUCCESS] macOS Universal FFmpeg binaries updated successfully!"
