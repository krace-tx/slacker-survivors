#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -x "$SCRIPT_DIR/gradlew" ]]; then
	GRADLE=("$SCRIPT_DIR/gradlew")
elif command -v gradle >/dev/null 2>&1; then
	GRADLE=("$(command -v gradle)")
else
	echo "error: Gradle was not found. Install Gradle or provide $SCRIPT_DIR/gradlew." >&2
	exit 1
fi

echo "==> Building GodotVideoPlayer AAR with Gradle..."
"${GRADLE[@]}" --no-daemon :assembleRelease

BUILD_AAR="$(find "$SCRIPT_DIR/build/outputs/aar" -maxdepth 1 -type f -name '*.aar' -print -quit 2>/dev/null || true)"
if [[ -z "$BUILD_AAR" || ! -f "$BUILD_AAR" ]]; then
	echo "error: Gradle completed without producing an AAR under build/outputs/aar." >&2
	exit 1
fi

TMP_AAR="$(mktemp "$SCRIPT_DIR/godot_video_player.aar.XXXXXX")"
trap 'rm -f "$TMP_AAR"' EXIT
cp "$BUILD_AAR" "$TMP_AAR"

if ! unzip -p "$TMP_AAR" classes.jar > "$TMP_AAR.classes.jar" 2>/dev/null; then
	echo "error: generated AAR does not contain classes.jar." >&2
	exit 1
fi
if [[ ! -s "$TMP_AAR.classes.jar" ]]; then
	echo "error: generated classes.jar is empty; refusing to publish a non-functional plugin." >&2
	exit 1
fi
if ! jar tf "$TMP_AAR.classes.jar" | grep -q 'org/godotengine/plugin/android/videoplayer/GodotVideoPlayer.class'; then
	echo "error: GodotVideoPlayer.class is missing from generated classes.jar." >&2
	exit 1
fi

mv "$TMP_AAR" "$SCRIPT_DIR/godot_video_player.aar"
rm -f "$TMP_AAR.classes.jar"
trap - EXIT
echo "==> Android plugin package ready: $SCRIPT_DIR/godot_video_player.aar"
