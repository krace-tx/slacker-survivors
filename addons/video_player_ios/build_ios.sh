#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "${1:-}" == "--check" || "${1:-}" == "check" ]]; then
	echo "==> Verifying existing godot_video_player.a..."
	if [[ ! -f "$SCRIPT_DIR/godot_video_player.a" ]]; then
		echo "error: godot_video_player.a does not exist" >&2
		exit 1
	fi
	if ! nm -gU "$SCRIPT_DIR/godot_video_player.a" | grep -q '_register_avplayer_types'; then
		echo "error: registration entry point was not exported by the archive" >&2
		exit 1
	fi
	echo "==> godot_video_player.a is valid and exports _register_avplayer_types."
	exit 0
fi

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
		"/tmp/godot-source" \
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
	"-fmodules-cache-path=${TMPDIR:-/tmp}/clang-module-cache"
	"-fobjc-arc"
	"-fobjc-exceptions"
	"-fmodules"
	"-fcxx-modules"
	"-std=c++17"
	"-DPTRCALL_ENABLED"
	"-DTYPED_METHOD_BIND"
)

if [[ ! -f "$GODOT_HEADERS/core/disabled_classes.gen.h" ]]; then
	touch "$GODOT_HEADERS/core/disabled_classes.gen.h"
fi
if [[ ! -f "$GODOT_HEADERS/core/object/gdvirtual.gen.inc" && -f "$GODOT_HEADERS/core/object/make_virtuals.py" ]]; then
	(cd "$GODOT_HEADERS/core/object" && python3 -c "import make_virtuals; make_virtuals.run(['gdvirtual.gen.inc'], [], {})")
fi

# Keep the old archive intact if compilation fails.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/godot-video-ios.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Compiling GodotVideoPlayer.mm for iOS ($ARCH, $TARGET)..."
clang++ -c \
	"${BUILD_FLAGS[@]}" \
	-I"$GODOT_HEADERS/platform/ios" \
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
