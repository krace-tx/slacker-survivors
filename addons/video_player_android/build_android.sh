#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "${1:-}" == "--check" || "${1:-}" == "check" ]]; then
	echo "==> Verifying existing godot_video_player.aar..."
	BUILD_AAR="$SCRIPT_DIR/godot_video_player.aar"
elif [[ -x "$SCRIPT_DIR/gradlew" ]]; then
	GRADLE=("$SCRIPT_DIR/gradlew")
	echo "==> Building GodotVideoPlayer AAR with Gradle wrapper..."
	"${GRADLE[@]}" --no-daemon :assembleRelease
	BUILD_AAR="$(find "$SCRIPT_DIR/build/outputs/aar" -maxdepth 1 -type f -name '*.aar' -print -quit 2>/dev/null || true)"
elif command -v gradle >/dev/null 2>&1; then
	GRADLE=("$(command -v gradle)")
	echo "==> Building GodotVideoPlayer AAR with Gradle..."
	"${GRADLE[@]}" --no-daemon :assembleRelease
	BUILD_AAR="$(find "$SCRIPT_DIR/build/outputs/aar" -maxdepth 1 -type f -name '*.aar' -print -quit 2>/dev/null || true)"
elif command -v javac >/dev/null 2>&1 && command -v jar >/dev/null 2>&1; then
	echo "==> Gradle not found; compiling GodotVideoPlayer with javac/jar fallback..."
	DEPS_DIR="${ANDROID_DEPS_DIR:-/tmp/android-deps}"
	GODOT_LIB="${GODOT_LIB:-/tmp/godot-lib.jar}"
	if [[ ! -f "$DEPS_DIR/android.jar" || ! -f "$GODOT_LIB" ]]; then
		echo "error: dependencies missing in $DEPS_DIR. Please install Gradle or configure ANDROID_DEPS_DIR." >&2
		exit 1
	fi
	TMP_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/godot-video-android.XXXXXX")"
	trap 'rm -rf "$TMP_BUILD"' EXIT
	mkdir -p "$TMP_BUILD/classes" "$TMP_BUILD/aar"
	javac -source 17 -target 17 \
		-cp "$DEPS_DIR/android.jar:$GODOT_LIB:$DEPS_DIR/annotation-jvm-1.7.1.jar:$DEPS_DIR/media3-common.jar:$DEPS_DIR/media3-exoplayer.jar:$DEPS_DIR/media3-ui.jar" \
		-d "$TMP_BUILD/classes" \
		src/main/java/org/godotengine/plugin/android/videoplayer/GodotVideoPlayer.java
	jar cvf "$TMP_BUILD/aar/classes.jar" -C "$TMP_BUILD/classes" . >/dev/null
	cp src/main/AndroidManifest.xml "$TMP_BUILD/aar/AndroidManifest.xml"
	touch "$TMP_BUILD/aar/R.txt"
	(cd "$TMP_BUILD/aar" && zip -q -r -0 "$TMP_BUILD/godot_video_player.aar" AndroidManifest.xml classes.jar R.txt)
	mkdir -p "$SCRIPT_DIR/build/outputs/aar"
	cp "$TMP_BUILD/godot_video_player.aar" "$SCRIPT_DIR/build/outputs/aar/godot_video_player-release.aar"
	BUILD_AAR="$SCRIPT_DIR/build/outputs/aar/godot_video_player-release.aar"
else
	echo "error: Neither Gradle nor JDK (javac/jar) was found." >&2
	exit 1
fi

if [[ -z "$BUILD_AAR" || ! -f "$BUILD_AAR" ]]; then
	echo "error: Build completed without producing an AAR package." >&2
	exit 1
fi

TMP_AAR="$(mktemp "${TMPDIR:-/tmp}/godot_video_player.aar.XXXXXX")"
TMP_CLASSES="$TMP_AAR.classes.jar"
trap 'rm -f "$TMP_AAR" "$TMP_CLASSES"' EXIT
cp "$BUILD_AAR" "$TMP_AAR"

if ! unzip -p "$TMP_AAR" classes.jar > "$TMP_CLASSES" 2>/dev/null; then
	echo "error: generated AAR does not contain classes.jar." >&2
	exit 1
fi
if [[ ! -s "$TMP_CLASSES" ]]; then
	echo "error: generated classes.jar is empty; refusing to publish a non-functional plugin." >&2
	exit 1
fi
if ! jar tf "$TMP_CLASSES" | grep -q 'org/godotengine/plugin/android/videoplayer/GodotVideoPlayer.class'; then
	echo "error: GodotVideoPlayer.class is missing from generated classes.jar." >&2
	exit 1
fi

if [[ "$BUILD_AAR" != "$SCRIPT_DIR/godot_video_player.aar" ]]; then
	mv "$TMP_AAR" "$SCRIPT_DIR/godot_video_player.aar"
fi
trap - EXIT
rm -f "$TMP_CLASSES" "$TMP_AAR"
rm -rf "$SCRIPT_DIR/build"
echo "==> Android plugin package ready: $SCRIPT_DIR/godot_video_player.aar"
