#!/usr/bin/env bash
set -e

echo "[EIRTeam.FFmpeg] Starting Linux x86_64 GDExtension build..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/ffmpeg-linux-build"

if [ -d "$BUILD_DIR" ]; then
    echo "[INFO] Cleaning previous build directory $BUILD_DIR..."
    rm -rf "$BUILD_DIR"
fi

echo "[INFO] Cloning EIRTeam.FFmpeg..."
git clone --depth 1 --recursive https://github.com/EIRTeam/EIRTeam.FFmpeg.git "$BUILD_DIR"

cd "$BUILD_DIR"

echo "[INFO] Bootstrapping build dependencies..."
make bootstrap

echo "[INFO] Compiling Linux GDExtension..."
make gdextension PLATFORM=linux TARGET_ARCH=x86_64

echo "[INFO] Copying compiled binaries back to $SCRIPT_DIR..."
cp -r gdextension_build/build/addons/ffmpeg/linux64/* "$SCRIPT_DIR/"

echo "[SUCCESS] Linux x86_64 FFmpeg binaries updated successfully!"
