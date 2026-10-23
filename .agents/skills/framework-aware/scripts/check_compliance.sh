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

# 5. Display layer decoupling & shared 3-pillar directory architecture
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

LEGACY_SHARED_MATCHES="$(grep -rnE --include="*.gd" --include="*.md" --include="*.tscn" 'shared/(define|components|models|constants|events|msvp)/' "${SEARCH_SRC_DOCS[@]}" 2>/dev/null || true)"
SHARED_UPWARD_MATCHES="$(grep -rnE --include="*.gd" 'res://src/game/(features|bootstrap)/' "$ROOT/src/game/shared" 2>/dev/null | grep -vE 'model/config/game_scenes\.gd' | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$LEGACY_SHARED_MATCHES" ] || [ -n "$SHARED_UPWARD_MATCHES" ]; then
	if [ -n "$LEGACY_SHARED_MATCHES" ]; then
		echo -e "${C_RED}[FAIL] Legacy shared path reference detected (use 'shared/model|service|component/'):${C_RESET}"
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
	echo -e "${C_GREEN}[PASS] Shared 3-pillar architecture (model/service/component & zero upward deps)${C_RESET}"
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
		"/Applications/Godot.app/Contents/MacOS/Godot" \
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

# 13. Asset topology, naming & dependency boundary (see src/assets/_doc_assets.md)
ASSET_ROOT="$ROOT/src/assets"
ASSET_FAILS=()
ASSET_WARNS=()
ASSET_FILE_COUNT=0
KNOWN_DOMAINS=" "

asset_spec() {
	# $1 = container key -> prints "<exts>|<prefixes>"
	case "$1" in
		textures)  echo "png svg webp jpg jpeg exr hdr tres|tex spr sht atl ui btn ico fx" ;;
		spines)    echo "skel spine-json atlas png tres|spn" ;;
		models)    echo "glb gltf bin|mdl skm" ;;
		materials) echo "tres|mat ptc" ;;
		shaders)   echo "gdshader gdshaderinc|shd" ;;
		themes)    echo "tres|thm sbx" ;;
		fonts)     echo "ttf otf woff woff2 tres|fnt" ;;
		audio/bgm) echo "ogg mp3|bgm" ;;
		audio/sfx) echo "wav ogg|sfx" ;;
		audio/vox) echo "ogg mp3|vox" ;;
		audio/amb) echo "ogg|amb" ;;
		videos)    echo "ogv mp4 webm|vid" ;;
		*)         echo "" ;;
	esac
}

in_list() {
	# $1 = needle, $2 = space separated list
	case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

if [ -d "$ASSET_ROOT" ]; then
	while IFS= read -r -d '' file; do
		name="$(basename "$file")"
		case "$name" in
			*.import|*.uid|.gitkeep|.gdignore|_doc_*.md) continue ;;
		esac
		ASSET_FILE_COUNT=$((ASSET_FILE_COUNT + 1))
		rel="${file#"$ASSET_ROOT"/}"
		IFS='/' read -r -a parts <<< "$rel"
		container="${parts[0]}"
		offset=1
		if [ "$container" = "audio" ] && [ "${#parts[@]}" -ge 2 ]; then
			container="audio/${parts[1]}"
			offset=2
		fi
		spec="$(asset_spec "$container")"
		if [ -z "$spec" ]; then
			ASSET_FAILS+=("Unknown media container '$container' -> $rel")
			continue
		fi
		depth=$(( ${#parts[@]} - offset ))
		if [ "$depth" -lt 2 ] || [ "$depth" -gt 3 ]; then
			ASSET_FAILS+=("Invalid depth (expect <container>/<domain>/[<group>/]<file>) -> $rel")
			continue
		fi
		domain="${parts[$offset]}"
		in_list "$domain" "$KNOWN_DOMAINS" || KNOWN_DOMAINS="$KNOWN_DOMAINS$domain "
		if [[ "$name" != *.* ]] || [[ "$name" == .* ]]; then
			ASSET_FAILS+=("Missing extension -> $rel")
			continue
		fi
		stem="${name%%.*}"
		ext="${name#*.}"
		exts="${spec%%|*}"
		prefixes="${spec#*|}"
		if ! in_list "$ext" "$exts"; then
			ASSET_FAILS+=("Extension '.$ext' not allowed in '$container/' (DCC sources belong in art/) -> $rel")
			continue
		fi
		if ! [[ "$stem" =~ ^[a-z][a-z0-9]*(_[a-z0-9]+)*$ ]] || [ "${#stem}" -gt 64 ]; then
			ASSET_FAILS+=("Stem must be lowercase snake_case <= 64 chars -> $rel")
			continue
		fi
		IFS='_' read -r -a tokens <<< "$stem"
		bad_token=""
		for tk in "${tokens[@]}"; do
			if in_list "$tk" "final new old copy tmp temp bak backup test" || [[ "$tk" =~ ^v[0-9]+$ ]] || [[ "$tk" =~ ^[0-9]$ ]]; then
				bad_token="$tk"
				break
			fi
		done
		if [ -n "$bad_token" ]; then
			ASSET_FAILS+=("Forbidden/invalid token '$bad_token' (no version words, numbers need >= 2 digits) -> $rel")
			continue
		fi
		if ! in_list "${tokens[0]}" "$prefixes"; then
			ASSET_FAILS+=("Prefix '${tokens[0]}_' not allowed in '$container/' (allowed: $prefixes) -> $rel")
			continue
		fi
		head="${tokens[0]}_${domain}_"
		if [[ "$stem" != "$head"* ]] || [ "${#stem}" -le "${#head}" ]; then
			ASSET_FAILS+=("Name must be '<prefix>_${domain}_<subject>...' (domain token == folder) -> $rel")
			continue
		fi
	done < <(find "$ASSET_ROOT" -type f -print0 2>/dev/null)

	for d in $KNOWN_DOMAINS; do
		if [ "$d" != "shared" ] && [ ! -d "$ROOT/src/game/features/$d" ]; then
			ASSET_WARNS+=("Asset domain '$d' has no matching src/game/features/$d/")
		fi
	done
fi

# 13b. Framework must never reference business assets
FW_ASSET_REFS="$(grep -rnE --include="*.gd" --include="*.tscn" --include="*.tres" 'res://src/assets/' "$ROOT/src/framework" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$FW_ASSET_REFS" ]; then
	while IFS= read -r line; do
		ASSET_FAILS+=("Framework references business asset -> ${line%%:*}")
	done <<< "$FW_ASSET_REFS"
fi

# 13c. Game layer asset ownership: features/<f> -> {<f>, shared}; shared & bootstrap -> {shared}
GAME_ROOT="$ROOT/src/game"
GAME_ASSET_REFS="$(grep -rnoE --include="*.gd" --include="*.tscn" --include="*.tres" 'res://src/assets/[A-Za-z0-9_./-]+' "$GAME_ROOT" 2>/dev/null || true)"
if [ -n "$GAME_ASSET_REFS" ]; then
	while IFS= read -r line; do
		code_path="${line%%:*}"
		rest="${line#*:}"
		line_no="${rest%%:*}"
		asset_path="${rest#*:}"
		src_line="$(sed -n "${line_no}p" "$code_path" 2>/dev/null)"
		if [[ "$src_line" =~ ^[[:space:]]*# ]]; then
			continue
		fi
		rel_code="${code_path#"$GAME_ROOT"/}"
		IFS='/' read -r -a code_parts <<< "$rel_code"
		allowed="shared"
		if [ "${code_parts[0]}" = "features" ] && [ "${#code_parts[@]}" -ge 2 ]; then
			allowed="shared ${code_parts[1]}"
		fi
		asset_rel="${asset_path#res://src/assets/}"
		IFS='/' read -r -a a_parts <<< "$asset_rel"
		dom_idx=1
		[ "${a_parts[0]}" = "audio" ] && dom_idx=2
		dom="<none>"
		if [ "${#a_parts[@]}" -gt $((dom_idx + 1)) ]; then
			dom="${a_parts[$dom_idx]}"
		fi
		if ! in_list "$dom" "$allowed"; then
			ASSET_FAILS+=("Cross-domain asset reference (domain '$dom' not in [$allowed]) -> $code_path:$line_no")
		fi
	done <<< "$GAME_ASSET_REFS"
fi

if [ "${#ASSET_FAILS[@]}" -gt 0 ]; then
	echo -e "${C_RED}[FAIL] Asset topology / naming / ownership violations (see src/assets/_doc_assets.md):${C_RESET}"
	for msg in "${ASSET_FAILS[@]}"; do
		echo -e "${C_RED}       - ${msg}${C_RESET}"
	done
	ERROR_COUNT=$((ERROR_COUNT + ${#ASSET_FAILS[@]}))
else
	echo -e "${C_GREEN}[PASS] Asset topology, naming & ownership (${ASSET_FILE_COUNT} assets verified)${C_RESET}"
fi
if [ "${#ASSET_WARNS[@]}" -gt 0 ]; then
	for msg in "${ASSET_WARNS[@]}"; do
		echo -e "${C_YELLOW}[WARN] ${msg}${C_RESET}"
	done
	WARN_COUNT=$((WARN_COUNT + ${#ASSET_WARNS[@]}))
fi

# 14. Global class reference: forbid redundant preload/load aliases of scripts that already declare class_name
ALIAS_FAILS=()
SCRIPT_LOAD_REFS="$(grep -rnoE --include="*.gd" '\b(pre)?load\([[:space:]]*"res://src/[^"]+\.gd"[[:space:]]*\)' "$ROOT/src" 2>/dev/null || true)"
if [ -n "$SCRIPT_LOAD_REFS" ]; then
	while IFS= read -r line; do
		code_path="${line%%:*}"
		rest="${line#*:}"
		line_no="${rest%%:*}"
		call="${rest#*:}"
		src_line="$(sed -n "${line_no}p" "$code_path" 2>/dev/null)"
		if [[ "$src_line" =~ ^[[:space:]]*# ]]; then
			continue
		fi
		target="$(printf '%s' "$call" | sed -E 's/.*"(res:\/\/[^"]+)".*/\1/')"
		target_file="$ROOT/${target#res://}"
		if [ -f "$target_file" ]; then
			class_name="$(grep -m1 -oE '^class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$target_file" | awk '{print $2}')"
			if [ -n "$class_name" ]; then
				ALIAS_FAILS+=("${code_path}:${line_no} -> use global '${class_name}' instead of loading '${target}'")
			fi
		fi
	done <<< "$SCRIPT_LOAD_REFS"
fi
if [ "${#ALIAS_FAILS[@]}" -gt 0 ]; then
	echo -e "${C_RED}[FAIL] Redundant script preload/load alias of a global class_name (reference the class directly):${C_RESET}"
	for msg in "${ALIAS_FAILS[@]}"; do
		echo -e "${C_RED}       - ${msg}${C_RESET}"
	done
	ERROR_COUNT=$((ERROR_COUNT + ${#ALIAS_FAILS[@]}))
else
	echo -e "${C_GREEN}[PASS] Global class reference (zero redundant preload aliases of class_name scripts)${C_RESET}"
fi

# 15. Sandbox persistence topology & Tier-2 domain ownership (user:// & StorageItem)
SANDBOX_FAILS=()
GAME_USER_REFS="$(grep -rnE --include="*.gd" --include="*.tscn" --include="*.tres" '"user://' "$GAME_ROOT" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -n "$GAME_USER_REFS" ]; then
	while IFS= read -r line; do
		SANDBOX_FAILS+=("Raw 'user://' literal in game layer (use StorageItem.for_config / for_save) -> ${line%%:*}")
	done <<< "$GAME_USER_REFS"
fi
while IFS= read -r gd_file; do
	[ -z "$gd_file" ] && continue
	rel="${gd_file#"$GAME_ROOT"/}"
	IFS='/' read -r -a parts <<< "$rel"
	if ! [[ "$rel" =~ (^|/)model/(.+/)?[a-z0-9_]+_model\.gd$ ]]; then
		sc_hit="$(grep -nE 'StorageItem\.(new|for_config|for_save)[[:space:]]*\(' "$gd_file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
		if [ -n "$sc_hit" ]; then
			SANDBOX_FAILS+=("StorageItem constructed outside *_model.gd -> $gd_file")
		fi
	fi
	dom_line="$(grep -m1 -E 'const[[:space:]]+STORAGE_DOMAIN([[:space:]]*:[[:space:]]*StringName)?[[:space:]]*=[[:space:]]*&"[^"]+"' "$gd_file" 2>/dev/null || true)"
	if [ -n "$dom_line" ] && ! [[ "$dom_line" =~ ^[[:space:]]*# ]]; then
		declared_dom="$(printf '%s' "$dom_line" | sed -E 's/.*&"([^"]+)".*/\1/')"
		expected_dom=""
		if [ "${parts[0]}" = "shared" ]; then
			expected_dom="shared"
		elif [ "${parts[0]}" = "features" ] && [ "${#parts[@]}" -ge 2 ]; then
			expected_dom="${parts[1]}"
		fi
		if [ -n "$expected_dom" ] && [ "$declared_dom" != "$expected_dom" ]; then
			SANDBOX_FAILS+=("Tier-2 STORAGE_DOMAIN mismatch (expected '&\"$expected_dom\"', got '&\"$declared_dom\"') -> $gd_file")
		fi
	fi
done < <(find "$GAME_ROOT" -type f -name "*.gd" 2>/dev/null | sort)

if [ "${#SANDBOX_FAILS[@]}" -gt 0 ]; then
	echo -e "${C_RED}[FAIL] Sandbox persistence topology & Tier-2 domain violations:${C_RESET}"
	for msg in "${SANDBOX_FAILS[@]}"; do
		echo -e "${C_RED}       - ${msg}${C_RESET}"
	done
	ERROR_COUNT=$((ERROR_COUNT + ${#SANDBOX_FAILS[@]}))
else
	echo -e "${C_GREEN}[PASS] Sandbox persistence topology & Tier-2 domain ownership (user:// & StorageItem)${C_RESET}"
fi

echo -e "${C_CYAN}--------------------------------------------------------${C_RESET}"
if [ "$ERROR_COUNT" -eq 0 ]; then
	echo -e "${C_GREEN}[OK] All compliance & syntax checks passed (${ERROR_COUNT} errors, ${WARN_COUNT} warnings)${C_RESET}"
	exit 0
else
	echo -e "${C_RED}[ERROR] Compliance check failed (${ERROR_COUNT} errors, ${WARN_COUNT} warnings)${C_RESET}"
	exit 1
fi
