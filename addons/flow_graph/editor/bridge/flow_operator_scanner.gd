@tool
extends RefCounted

## 项目算子、条件、事件与状态自动嗅探器（Zero-Instantiation GDScript Operator Scanner）。[br]
##
## 基于纯文本正则扫描项目 `.gd` 脚本（自动跳过 `res://.godot` 与 `res://addons/flow_graph`），提取已注册的 `actions`、`conditions`、`events` 与 `states` 供编辑器原位补全使用。

const SKIP_DIR_PREFIXES: Array[String] = ["res://.godot", "res://addons/flow_graph"]

static var _cached_result: Dictionary = {}
static var _has_scanned: bool = false


#region 公开扫描与缓存接口

static func get_cached() -> Dictionary:
	if not _has_scanned:
		return refresh()
	return _clone_result(_cached_result)


static func refresh(root_dir: String = "res://") -> Dictionary:
	var scanned: Dictionary = scan_project(root_dir)
	if root_dir == "res://":
		_cached_result = _clone_result(scanned)
		_has_scanned = true
	return scanned


static func scan_project(root_dir: String = "res://") -> Dictionary:
	var action_set: Dictionary = {}
	var cond_set: Dictionary = {}
	var event_set: Dictionary = {}
	var state_set: Dictionary = {}

	var regex_bundle: Dictionary = _compile_regexes()
	var gd_files: Array[String] = []
	_collect_gd_files_recursive(root_dir, gd_files)

	for fpath: String in gd_files:
		var content: String = FileAccess.get_file_as_string(fpath)
		if content.is_empty():
			continue
		_collect_matches(content, regex_bundle["action_call"] as RegEx, action_set)
		_collect_matches(content, regex_bundle["action_anno"] as RegEx, action_set)
		_collect_matches(content, regex_bundle["cond_call"] as RegEx, cond_set)
		_collect_matches(content, regex_bundle["cond_anno"] as RegEx, cond_set)
		_collect_matches(content, regex_bundle["event_call"] as RegEx, event_set)
		_collect_matches(content, regex_bundle["event_anno"] as RegEx, event_set)
		_collect_matches(content, regex_bundle["state_call"] as RegEx, state_set)
		_collect_matches(content, regex_bundle["state_anno"] as RegEx, state_set)

	var result: Dictionary = {
		"actions": _sorted_packed_keys(action_set),
		"conditions": _sorted_packed_keys(cond_set),
		"events": _sorted_packed_keys(event_set),
		"states": _sorted_packed_keys(state_set),
	}
	if root_dir == "res://":
		_cached_result = _clone_result(result)
		_has_scanned = true
	return result

#endregion


#region 内部目录遍历与正则提取

static func _collect_gd_files_recursive(dir_path: String, out_files: Array[String]) -> void:
	for prefix: String in SKIP_DIR_PREFIXES:
		if dir_path.begins_with(prefix):
			return
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return
	da.include_hidden = false
	da.list_dir_begin()
	var fname: String = da.get_next()
	while not fname.is_empty():
		if not fname.begins_with("."):
			var full_path: String = dir_path.path_join(fname)
			if da.current_is_dir():
				_collect_gd_files_recursive(full_path, out_files)
			elif fname.ends_with(".gd"):
				out_files.append(full_path)
		fname = da.get_next()
	da.list_dir_end()


static func _compile_regexes() -> Dictionary:
	var rx_action_call := RegEx.new()
	rx_action_call.compile("register_(?:action|service)\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']")

	var rx_action_anno := RegEx.new()
	rx_action_anno.compile("#\\s*@flow_action\\s+([A-Za-z0-9_./:-]+)")

	var rx_cond_call := RegEx.new()
	rx_cond_call.compile("register_condition\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']")

	var rx_cond_anno := RegEx.new()
	rx_cond_anno.compile("#\\s*@flow_condition\\s+([A-Za-z0-9_./:-]+)")

	var rx_event_call := RegEx.new()
	rx_event_call.compile("fire_event\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']")

	var rx_event_anno := RegEx.new()
	rx_event_anno.compile("#\\s*@flow_event\\s+([A-Za-z0-9_./:-]+)")

	var rx_state_call := RegEx.new()
	rx_state_call.compile("add_(?:callable|state)\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']")

	var rx_state_anno := RegEx.new()
	rx_state_anno.compile("#\\s*@flow_state\\s+([A-Za-z0-9_./:-]+)")

	return {
		"action_call": rx_action_call,
		"action_anno": rx_action_anno,
		"cond_call": rx_cond_call,
		"cond_anno": rx_cond_anno,
		"event_call": rx_event_call,
		"event_anno": rx_event_anno,
		"state_call": rx_state_call,
		"state_anno": rx_state_anno,
	}


static func _collect_matches(content: String, rx: RegEx, target_set: Dictionary) -> void:
	var matches: Array[RegExMatch] = rx.search_all(content)
	for m: RegExMatch in matches:
		var token: String = m.get_string(1).strip_edges()
		if not token.is_empty():
			target_set[token] = true


static func _sorted_packed_keys(dict_set: Dictionary) -> PackedStringArray:
	var arr: Array[String] = []
	for k: Variant in dict_set.keys():
		arr.append(str(k))
	arr.sort()
	return PackedStringArray(arr)


static func _clone_result(src: Dictionary) -> Dictionary:
	return {
		"actions": (src.get("actions", PackedStringArray()) as PackedStringArray).duplicate(),
		"conditions": (src.get("conditions", PackedStringArray()) as PackedStringArray).duplicate(),
		"events": (src.get("events", PackedStringArray()) as PackedStringArray).duplicate(),
		"states": (src.get("states", PackedStringArray()) as PackedStringArray).duplicate(),
	}

#endregion
