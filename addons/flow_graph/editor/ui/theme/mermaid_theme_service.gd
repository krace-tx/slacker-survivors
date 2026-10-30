@tool
extends RefCounted

## Godot 4 编辑器主题实时同步服务（Live Editor Theme Service）。[br]
##
## 插件内唯一访问 `EditorInterface` 主题与 `EditorSettings` 语法配色的入口：[br]
## 1. 编辑器内读取 `Editor` 主题类型下的 `base_color / accent_color / dark_color_1~3 / font_color / success|warning|error_color` 与 `text_editor/theme/highlighting/*`；[br]
## 2. 非编辑器上下文（无头测试、独立运行）自动回退为 Godot 4 默认暗色预设；[br]
## 3. 以内容签名去重，仅在配色真实变化时递增 [method version]，供画布调色板与工作台样式器做惰性重建。

const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

const THEME_TYPE: StringName = &"Editor"
const HL_PREFIX: String = "text_editor/theme/highlighting/"

static var _tokens: MermaidThemeTokens = null
static var _signature: String = ""
static var _version: int = 0


#region 公开查询接口

static func tokens() -> MermaidThemeTokens:
	if _tokens == null:
		refresh()
	return _tokens


static func version() -> int:
	if _tokens == null:
		refresh()
	return _version


## 重新采样编辑器主题；配色发生变化时返回 `true`。
static func refresh() -> bool:
	var t := MermaidThemeTokens.new()
	_read_editor_overrides(t)
	t.derive()
	var sig: String = t.signature()
	if _tokens != null and sig == _signature:
		return false
	_tokens = t
	_signature = sig
	_version += 1
	return true


static func editor_settings_or_null() -> EditorSettings:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_settings()

#endregion


#region 编辑器主题与语法配色采样

static func _read_editor_overrides(t: MermaidThemeTokens) -> void:
	if not Engine.is_editor_hint():
		return

	var th: Theme = EditorInterface.get_editor_theme()
	if th != null:
		t.base = _theme_color(th, &"base_color", t.base)
		t.accent = _theme_color(th, &"accent_color", t.accent)
		t.dark1 = _theme_color(th, &"dark_color_1", t.dark1)
		t.dark2 = _theme_color(th, &"dark_color_2", t.dark2)
		t.dark3 = _theme_color(th, &"dark_color_3", t.dark3)
		t.font = _theme_color(th, &"font_color", t.font)
		t.mono = _theme_color(th, &"mono_color", t.mono)
		t.success = _theme_color(th, &"success_color", t.success)
		t.warning = _theme_color(th, &"warning_color", t.warning)
		t.error = _theme_color(th, &"error_color", t.error)

	var es: EditorSettings = EditorInterface.get_editor_settings()
	if es != null:
		t.code_bg = _setting_color(es, "background_color", t.code_bg)
		t.code_text = _setting_color(es, "text_color", t.code_text)
		t.code_line_number = _setting_color(es, "line_number_color", t.code_line_number)
		t.code_current_line = _setting_color(es, "current_line_color", t.code_current_line)
		t.code_caret = _setting_color(es, "caret_color", t.code_caret)
		t.code_selection = _setting_color(es, "selection_color", t.code_selection)
		t.code_keyword = _setting_color(es, "keyword_color", t.code_keyword)
		t.code_control_flow = _setting_color(es, "control_flow_keyword_color", t.code_control_flow)
		t.code_engine_type = _setting_color(es, "engine_type_color", t.code_engine_type)
		t.code_comment = _setting_color(es, "comment_color", t.code_comment)
		t.code_string = _setting_color(es, "string_color", t.code_string)
		t.code_number = _setting_color(es, "number_color", t.code_number)
		t.code_symbol = _setting_color(es, "symbol_color", t.code_symbol)
		t.code_function = _setting_color(es, "function_color", t.code_function)
		t.code_member = _setting_color(es, "member_variable_color", t.code_member)


static func _theme_color(th: Theme, name: StringName, fallback: Color) -> Color:
	if th.has_color(name, THEME_TYPE):
		return th.get_color(name, THEME_TYPE)
	return fallback


static func _setting_color(es: EditorSettings, key: String, fallback: Color) -> Color:
	var full_key: String = HL_PREFIX + key
	if not es.has_setting(full_key):
		return fallback
	var v: Variant = es.get_setting(full_key)
	if v is Color:
		return v as Color
	return fallback

#endregion
