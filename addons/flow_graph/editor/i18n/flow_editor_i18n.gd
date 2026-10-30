@tool
class_name FlowEditorI18n
extends RefCounted

## FlowGraph 编辑器实时双语（中 / 英）国际化服务（Live Editor Localization Service）。[br]
##
## 默认自动读取 Godot `EditorSettings` 语言偏好，支持顶栏一键切换 `zh` ↔ `en` 并持久化至 `flow_graph/editor/language`，实时通知全部已订阅视图重绘。

const ZhTable = preload(FlowGraphContracts.SCRIPT_I18N_ZH)
const EnTable = preload(FlowGraphContracts.SCRIPT_I18N_EN)

const LOCALE_ZH: StringName = &"zh"
const LOCALE_EN: StringName = &"en"

static var _initialized: bool = false
static var _locale: StringName = LOCALE_ZH
## `Array[Dictionary]`: `{"ref": WeakRef, "cb": Callable}`
static var _listeners: Array[Dictionary] = []
static var _zh_hot_table: Dictionary = {}
static var _en_hot_table: Dictionary = {}
static var _checked_missing_keys: Dictionary = {}


#region 语言初始化、切换与弱引用订阅

static func get_locale() -> StringName:
	_ensure_init()
	return _locale


static func is_zh() -> bool:
	return get_locale() == LOCALE_ZH


static func is_english() -> bool:
	return get_locale() == LOCALE_EN


static func set_locale(next_locale: StringName, persist: bool = true) -> void:
	_ensure_init()
	var normalized: StringName = LOCALE_EN if String(next_locale).to_lower().begins_with("en") else LOCALE_ZH
	if _locale == normalized:
		return
	_locale = normalized
	if persist:
		_save_to_editor_settings(_locale)
	_notify_listeners()


static func toggle_locale(persist: bool = true) -> StringName:
	var target: StringName = LOCALE_EN if get_locale() == LOCALE_ZH else LOCALE_ZH
	set_locale(target, persist)
	return _locale


static func subscribe(owner: Object, callback: Callable) -> void:
	if owner == null or not callback.is_valid():
		return
	unsubscribe(owner)
	_listeners.append({"ref": weakref(owner), "cb": callback})


static func unsubscribe(owner: Object) -> void:
	var i: int = _listeners.size() - 1
	while i >= 0:
		var target: Object = (_listeners[i]["ref"] as WeakRef).get_ref()
		if target == null or target == owner:
			_listeners.remove_at(i)
		i -= 1

#endregion


#region 文案检索与领域枚举翻译

static func t(key: StringName, args: Array = []) -> String:
	_ensure_init()
	var dict: Dictionary = _resolve_table(_locale)
	if not dict.has(key) and Engine.is_editor_hint() and not _checked_missing_keys.has(key):
		_checked_missing_keys[key] = true
		_reload_tables_from_disk()
		dict = _resolve_table(_locale)
	var zh_fb: Dictionary = _resolve_table(LOCALE_ZH)
	var tmpl: String = str(dict.get(key, zh_fb.get(key, String(key))))
	if args.is_empty():
		return tmpl
	return tmpl % args


static func kind_label(kind: String) -> String:
	var k_name: StringName = StringName("kind.%s" % kind)
	_ensure_init()
	var dict: Dictionary = _resolve_table(_locale)
	if not dict.has(k_name) and Engine.is_editor_hint() and not _checked_missing_keys.has(k_name):
		_checked_missing_keys[k_name] = true
		_reload_tables_from_disk()
		dict = _resolve_table(_locale)
	if dict.has(k_name):
		return str(dict[k_name])
	return kind


static func state_label(state_code: String) -> String:
	var s_name: StringName = StringName("state.%s" % state_code)
	_ensure_init()
	var dict: Dictionary = _resolve_table(_locale)
	if dict.has(s_name):
		return str(dict[s_name])
	return state_code


static func _resolve_table(loc: StringName) -> Dictionary:
	if loc == LOCALE_EN:
		return _en_hot_table if not _en_hot_table.is_empty() else EnTable.TABLE
	return _zh_hot_table if not _zh_hot_table.is_empty() else ZhTable.TABLE


static func _reload_tables_from_disk() -> void:
	var zh_scr: Script = ResourceLoader.load(FlowGraphContracts.SCRIPT_I18N_ZH, "", ResourceLoader.CACHE_MODE_REPLACE) as Script
	if zh_scr != null and ("TABLE" in zh_scr.get_script_constant_map()):
		_zh_hot_table = zh_scr.get_script_constant_map()["TABLE"] as Dictionary
	var en_scr: Script = ResourceLoader.load(FlowGraphContracts.SCRIPT_I18N_EN, "", ResourceLoader.CACHE_MODE_REPLACE) as Script
	if en_scr != null and ("TABLE" in en_scr.get_script_constant_map()):
		_en_hot_table = en_scr.get_script_constant_map()["TABLE"] as Dictionary

#endregion


#region 内部持久化与广播

static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	if Engine.is_editor_hint():
		var es: EditorSettings = EditorInterface.get_editor_settings()
		if es != null:
			if es.has_setting(FlowGraphContracts.SETTING_EDITOR_LANGUAGE):
				var saved: String = str(es.get_setting(FlowGraphContracts.SETTING_EDITOR_LANGUAGE)).to_lower()
				_locale = LOCALE_EN if saved.begins_with("en") else LOCALE_ZH
				return
			if es.has_setting(FlowGraphContracts.SETTING_GODOT_LOCALE):
				var ed_lang: String = str(es.get_setting(FlowGraphContracts.SETTING_GODOT_LOCALE)).to_lower()
				_locale = LOCALE_ZH if ed_lang.begins_with("zh") else LOCALE_EN
				return
	var os_lang: String = OS.get_locale_language().to_lower()
	_locale = LOCALE_EN if (not os_lang.is_empty() and not os_lang.begins_with("zh")) else LOCALE_ZH


static func _save_to_editor_settings(lang: StringName) -> void:
	if not Engine.is_editor_hint():
		return
	var es: EditorSettings = EditorInterface.get_editor_settings()
	if es != null:
		es.set_setting(FlowGraphContracts.SETTING_EDITOR_LANGUAGE, String(lang))


static func _notify_listeners() -> void:
	var alive: Array[Dictionary] = []
	for rec: Dictionary in _listeners.duplicate():
		var obj: Object = (rec["ref"] as WeakRef).get_ref()
		var cb: Callable = rec["cb"] as Callable
		if obj != null and is_instance_valid(obj) and cb.is_valid():
			alive.append(rec)
			cb.call(_locale)
	_listeners = alive

#endregion
