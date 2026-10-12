#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v xcrun >/dev/null 2>&1; then
	echo "error: xcrun is required to build the iOS plugin" >&2
	exit 1
fi

# Build against the exact Godot headers used by the iOS export template.
# Set GODOT_HEADERS to a checkout containing core/object/object.h, or set
# GODOT_SOURCE as an alias.
GODOT_HEADERS="${GODOT_HEADERS:-${GODOT_SOURCE:-}}"
if [[ -z "$GODOT_HEADERS" ]]; then
	for candidate in \
		"$SCRIPT_DIR/../../godot" \
		"$SCRIPT_DIR/../../../godot" \
		"${HOME}/src/godot"; do
		if [[ -f "$candidate/core/object/object.h" ]]; then
			GODOT_HEADERS="$candidate"
			break
		fi
	done
fi

if [[ -z "$GODOT_HEADERS" || ! -f "$GODOT_HEADERS/core/object/object.h" ]]; then
	cat >&2 <<'EOF'
error: Godot headers were not found.
Set GODOT_HEADERS (or GODOT_SOURCE) to the Godot source checkout used to build
the iOS export template, for example:

  GODOT_HEADERS=/path/to/godot ./addons/video_player_ios/build_ios.sh
EOF
	exit 1
fi

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
ARCH="${IOS_ARCH:-arm64}"
TARGET="${IOS_TARGET:-release}"
BUILD_FLAGS=(
	"-arch" "$ARCH"
	"-isysroot" "$SDK_PATH"
	"-fobjc-arc"
	"-fobjc-exceptions"
	"-fmodules"
	"-fcxx-modules"
	"-std=c++17"
	"-DPTRCALL_ENABLED"
	"-DTYPED_METHOD_BIND"
)

# Keep the old archive intact if compilation fails.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/godot-video-ios.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Compiling GodotVideoPlayer.mm for iOS ($ARCH, $TARGET)..."
clang++ -c \
	"${BUILD_FLAGS[@]}" \
	-I"$GODOT_HEADERS" \
	-I"$GODOT_HEADERS/thirdparty" \
	src/GodotVideoPlayer.mm \
	-o "$TMP_DIR/GodotVideoPlayer.o"

echo "==> Packaging godot_video_player.a..."
ar rcs "$TMP_DIR/godot_video_player.a" "$TMP_DIR/GodotVideoPlayer.o"
ranlib "$TMP_DIR/godot_video_player.a"

if ! nm -gU "$TMP_DIR/godot_video_player.a" | grep -q '_register_avplayer_types'; then
	echo "error: registration entry point was not exported by the archive" >&2
	exit 1
fi

mv "$TMP_DIR/godot_video_player.a" godot_video_player.a
echo "==> iOS build complete: godot_video_player.a"
file godot_video_player.a
