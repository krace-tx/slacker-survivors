#!/usr/bin/env bash
# ==============================================================================
# Framework Compliance Checker (Slacker Survivors) - Shell Edition
# ==============================================================================
# Automated quality gate for architectural boundaries, naming conventions,
# dependency injection rules, and full GDScript syntax compilation.
#
# Usage:
#   bash .agents/skills/framework-aware/scripts/check_compliance.sh
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_RESET='\033[0m'

echo -e "${C_CYAN}[Framework-Aware] Scanning architecture compliance: ${ROOT}${C_RESET}"
echo -e "${C_CYAN}--------------------------------------------------------${C_RESET}"

ERROR_COUNT=0
WARN_COUNT=0

existing_dirs() {
	local out=()
	for d in "$@"; do
		if [ -d "$d" ]; then
			out+=("$d")
		fi
	done
	echo "${out[@]}"
}

SEARCH_ALL=($(existing_dirs "$ROOT/src" "$ROOT/addons" "$ROOT/docs"))
SEARCH_SRC_DOCS=($(existing_dirs "$ROOT/src" "$ROOT/docs"))

# 1. Network facade convention: forbid deprecated App.network (use App.net)
NET_MATCHES="$(grep -rnE --include="*.gd" 'App\.network\b' "$ROOT/src" 2>/dev/null || true)"
if [ -n "$NET_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Deprecated 'App.network' usage detected (use 'App.net'):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$NET_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Network facade convention (App.net)${C_RESET}"
fi

# 2. Singular domain path rule: forbid infra/params/ (use infra/param/)
PARAMS_MATCHES="$(grep -rnE --include="*.gd" --include="*.md" --include="*.tscn" 'infra/params/' "${SEARCH_ALL[@]}" 2>/dev/null | grep -vE '\.md:[0-9]+:[[:space:]]*\|' || true)"
if [ -n "$PARAMS_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Deprecated plural path 'infra/params/' detected (use 'infra/param/'):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$PARAMS_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Singular domain path (infra/param/)${C_RESET}"
fi

# 3. Plural asset container path rule: forbid assets/video/ (use assets/videos/)
VIDEO_MATCHES="$(grep -rnE --include="*.gd" --include="*.md" --include="*.tscn" 'assets/video/' "${SEARCH_ALL[@]}" 2>/dev/null | grep -vE '\.md:[0-9]+:[[:space:]]*\|' || true)"
if [ -n "$VIDEO_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Deprecated singular path 'assets/video/' detected (use 'assets/videos/'):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$VIDEO_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Plural asset container path (assets/videos/)${C_RESET}"
fi

# 4. Logger module path rule: forbid modules/log/ (use modules/logger/)
LOGGER_MATCHES="$(grep -rnE --include="*.gd" --include="*.md" --include="*.tscn" 'modules/log/' "${SEARCH_ALL[@]}" 2>/dev/null || true)"
if [ -n "$LOGGER_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Deprecated module path 'modules/log/' detected (use 'modules/logger/'):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$LOGGER_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Logger module path (modules/logger/)${C_RESET}"
fi

# 5. Display layer decoupling & shared 4-pillar directory architecture
UI_DIALOG_MATCHES=""
if [ -d "$ROOT/src/framework/modules/display" ]; then
	UI_DIALOG_MATCHES="$(find "$ROOT/src/framework/modules/display" -type f \( -iname "*dialog*.gd" -o -iname "*modal*.gd" -o -iname "*toast*.gd" \) 2>/dev/null || true)"
fi
if [ -n "$UI_DIALOG_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Business dialog/toast scripts found in 'framework/modules/display' (move to 'src/game/shared/component/'):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$UI_DIALOG_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Display layer decoupling (dialogs isolated in shared/component/)${C_RESET}"
fi

LEGACY_SHARED_MATCHES="$(grep -rnE --include="*.gd" --include="*.md" --include="*.tscn" 'shared/(components|models|constants|events|msvp)/' "${SEARCH_SRC_DOCS[@]}" 2>/dev/null || true)"
SHARED_UPWARD_MATCHES="$(grep -rnE --include="*.gd" 'res://src/game/(features|bootstrap)/' "$ROOT/src/game/shared" 2>/dev/null | grep -vE 'define/generated/' | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$LEGACY_SHARED_MATCHES" ] || [ -n "$SHARED_UPWARD_MATCHES" ]; then
	if [ -n "$LEGACY_SHARED_MATCHES" ]; then
		echo -e "${C_RED}[FAIL] Legacy shared path reference detected (use 'shared/define|model|service|component/'):${C_RESET}"
		while IFS= read -r line; do
			echo -e "${C_RED}       - ${line}${C_RESET}"
			ERROR_COUNT=$((ERROR_COUNT + 1))
		done <<< "$LEGACY_SHARED_MATCHES"
	fi
	if [ -n "$SHARED_UPWARD_MATCHES" ]; then
		echo -e "${C_RED}[FAIL] Upward dependency from 'src/game/shared/' to 'features/' or 'bootstrap/' detected:${C_RESET}"
		while IFS= read -r line; do
			echo -e "${C_RED}       - ${line}${C_RESET}"
			ERROR_COUNT=$((ERROR_COUNT + 1))
		done <<< "$SHARED_UPWARD_MATCHES"
	fi
else
	echo -e "${C_GREEN}[PASS] Shared 4-pillar architecture (define/model/service/component & zero upward deps)${C_RESET}"
fi

# 6. Unidirectional dependency boundary: src/framework/ must never reference src/game/ or src/test/
REVERSE_DEP_MATCHES="$(grep -rnE --include="*.gd" 'res://src/(game|test)/' "$ROOT/src/framework" 2>/dev/null | grep -vE 'autoload/app\.gd:' | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$REVERSE_DEP_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Reverse dependency from 'src/framework/' to 'src/game/' or 'src/test/' detected:${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$REVERSE_DEP_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Unidirectional dependency boundary (zero game/test imports in framework)${C_RESET}"
fi

# 7. Explicit dependency injection: forbid implicit App.xxx calls inside modules/infra/util
HIDDEN_APP_MATCHES="$(grep -rnE --include="*.gd" '\bApp\.' "$ROOT/src/framework/modules" "$ROOT/src/framework/infra" "$ROOT/src/framework/util" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$HIDDEN_APP_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Implicit 'App.xxx' access inside 'framework/modules|infra|util' (use constructor DI):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$HIDDEN_APP_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Explicit dependency injection (zero implicit App.xxx in modules/infra/util)${C_RESET}"
fi

# 8. Core module dependency manifests (MODULE_ID / REQUIRED_MODULES / OPTIONAL_MODULES)
MODULE_IMPL_FILES=(
	"env/impl/runtime_environment.gd"
	"logger/impl/framework_logger.gd"
	"clock/impl/clock_system.gd"
	"asset/impl/asset_system.gd"
	"input/impl/input_system.gd"
	"haptic/impl/haptic_feedback.gd"
	"network/impl/network_client.gd"
	"storage/impl/storage_system.gd"
	"locale/impl/localization_system.gd"
	"scene/impl/scene_router.gd"
	"display/impl/display_system.gd"
	"audio/impl/audio_system.gd"
	"video/impl/video_player.gd"
)
MISSING_MANIFEST_COUNT=0
for rel_path in "${MODULE_IMPL_FILES[@]}"; do
	full_path="$ROOT/src/framework/modules/$rel_path"
	if [ ! -f "$full_path" ]; then
		echo -e "${C_RED}[FAIL] Missing core module implementation file: ${full_path}${C_RESET}"
		MISSING_MANIFEST_COUNT=$((MISSING_MANIFEST_COUNT + 1))
		continue
	fi
	if ! grep -qE 'const[[:space:]]+MODULE_ID\b' "$full_path" || \
	   ! grep -qE 'const[[:space:]]+REQUIRED_MODULES\b' "$full_path" || \
	   ! grep -qE 'const[[:space:]]+OPTIONAL_MODULES\b' "$full_path"; then
		echo -e "${C_RED}[FAIL] Incomplete dependency manifest (MODULE_ID / REQUIRED_MODULES / OPTIONAL_MODULES): ${rel_path}${C_RESET}"
		MISSING_MANIFEST_COUNT=$((MISSING_MANIFEST_COUNT + 1))
	fi
done
if [ "$MISSING_MANIFEST_COUNT" -gt 0 ]; then
	ERROR_COUNT=$((ERROR_COUNT + MISSING_MANIFEST_COUNT))
else
	echo -e "${C_GREEN}[PASS] Core module dependency manifests (13/13 modules verified)${C_RESET}"
fi

# 9. Facade boundary isolation: forbid referencing internal impl classes from src/game/
INTERNAL_CLASSES_PATTERN='\b(RuntimeEnvironment|FrameworkLogger|ClockSystem|AssetSystem|AssetCache|ResourceLoaderAdapter|StorageSystem|StorageCache|StorageMigrator|MemoryStorageDriver|DiskStorageDriver|RemoteStorageDriver|NetworkClient|RequestQueue|SceneRouter|SceneStack|SceneTransition|DisplaySystem|AudioSystem|BgmPlayer|SfxPool|LocalizationSystem|TranslationServerAdapter|HapticFeedback|InputSystem|InputDeviceTracker|InputRebindCapturer|InputMapAdapter|VideoPlayer)\b'
IMPL_LEAK_MATCHES="$(grep -rnE --include="*.gd" "$INTERNAL_CLASSES_PATTERN" "$ROOT/src/game" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$IMPL_LEAK_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Direct reference to internal 'impl/' class in 'src/game/' (program against 'Base*' facades):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$IMPL_LEAK_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Facade boundary isolation (zero internal impl leaks in src/game/)${C_RESET}"
fi

# 10. Codec, async & spine utilities consolidation
DEPRECATED_UTILS_MATCHES="$(grep -rnE --include="*.gd" '\b(FileCodecType|ImageFileCodec|Texture2DFileCodec|AsyncUtils|SpineUtils)\b|TimeUtils\.wait_safe' "$ROOT/src" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$DEPRECATED_UTILS_MATCHES" ]; then
	echo -e "${C_RED}[FAIL] Deprecated utility usage detected (FileCodecType/ImageFileCodec/Texture2DFileCodec/AsyncUtils/SpineUtils/TimeUtils.wait_safe):${C_RESET}"
	while IFS= read -r line; do
		echo -e "${C_RED}       - ${line}${C_RESET}"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	done <<< "$DEPRECATED_UTILS_MATCHES"
else
	echo -e "${C_GREEN}[PASS] Codec, async & spine consolidation (FileCodecUtils / ResourceCodecUtils / TaskScope / SpinePool)${C_RESET}"
fi

# 11. GDScript syntax & static type compilation (Godot Headless)
GODOT_EXE="${GODOT_BIN:-}"
if [ -z "$GODOT_EXE" ] || [ ! -f "$GODOT_EXE" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_EXE="$(command -v godot)"
	fi
fi
if [ -z "$GODOT_EXE" ] || [ ! -f "$GODOT_EXE" ]; then
	for candidate in \
		"/d/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe" \
		"D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe" \
		"/d/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe" \
		"D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"; do
		if [ -f "$candidate" ]; then
			GODOT_EXE="$candidate"
			break
		fi
	done
fi

if [ -n "$GODOT_EXE" ] && [ -f "$GODOT_EXE" ]; then
	SYNTAX_OUTPUT="$("$GODOT_EXE" --headless --quit --path "$ROOT" -s ".agents/skills/framework-aware/scripts/check_syntax.gd" 2>&1)"
	SYNTAX_EXIT=$?
	PASS_LINE="$(printf "%s\n" "$SYNTAX_OUTPUT" | tr -d '\r' | grep -E '^\[SYNTAX_PASS\][[:space:]]+[0-9]+' | head -n 1 || true)"
	if [ "$SYNTAX_EXIT" -eq 0 ] && [ -n "$PASS_LINE" ]; then
		SCRIPT_COUNT="${PASS_LINE#\[SYNTAX_PASS\] }"
		echo -e "${C_GREEN}[PASS] GDScript syntax & static type compilation (${SCRIPT_COUNT} scripts verified)${C_RESET}"
	else
		echo -e "${C_RED}[FAIL] GDScript syntax or static type compilation failed:${C_RESET}"
		printf "%s\n" "$SYNTAX_OUTPUT" | tr -d '\r' | grep -E 'SCRIPT ERROR:|Parse Error:|Compile Error:|\[SYNTAX_FAIL\]|[[:space:]]at:[[:space:]]' | while IFS= read -r err_line; do
			echo -e "${C_RED}       ${err_line}${C_RESET}"
		done
		ERROR_COUNT=$((ERROR_COUNT + 1))
	fi
else
	echo -e "${C_YELLOW}[WARN] Godot binary not found (set GODOT_BIN to enable full syntax compilation)${C_RESET}"
	WARN_COUNT=$((WARN_COUNT + 1))
fi

# 12. Raw print() warning (prefer App.logger)
PRINT_MATCHES="$(grep -rnE --include="*.gd" '^[[:space:]]*print\(' "$ROOT/src/framework" "$ROOT/src/game" 2>/dev/null || true)"
if [ -n "$PRINT_MATCHES" ]; then
	PRINT_COUNT="$(printf "%s\n" "$PRINT_MATCHES" | wc -l | tr -d ' ')"
	echo -e "${C_YELLOW}[WARN] Found ${PRINT_COUNT} raw print() call(s) (prefer App.logger)${C_RESET}"
	WARN_COUNT=$((WARN_COUNT + PRINT_COUNT))
else
	echo -e "${C_GREEN}[PASS] No raw print() statements found${C_RESET}"
fi

echo -e "${C_CYAN}--------------------------------------------------------${C_RESET}"
if [ "$ERROR_COUNT" -eq 0 ]; then
	echo -e "${C_GREEN}[OK] All compliance & syntax checks passed (${ERROR_COUNT} errors, ${WARN_COUNT} warnings)${C_RESET}"
	exit 0
else
	echo -e "${C_RED}[ERROR] Compliance check failed (${ERROR_COUNT} errors, ${WARN_COUNT} warnings)${C_RESET}"
	exit 1
fi
