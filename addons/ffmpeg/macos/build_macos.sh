#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building Universal macOS dylib (arm64 + x86_64) for ffmpeg.gdextension..."
clang -dynamiclib -arch arm64 -arch x86_64 -O2 \
    -I. \
    ffmpeg_init.c \
    -o libgdffmpeg.macos.dylib

echo "==> Build complete: libgdffmpeg.macos.dylib"
file libgdffmpeg.macos.dylib
