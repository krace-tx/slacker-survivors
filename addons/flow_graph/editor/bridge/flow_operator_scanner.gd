@tool
extends RefCounted

## 项目算子、条件、事件与状态增量嗅探器（Zero-Instantiation Incremental GDScript Operator Scanner）。[br]
##
## [b]核心设计：[/b][br]
## 1. [b]零实例化增量扫描[/b]：按单文件 `mtime` 缓存解析结果，跳过 `res://.godot` 与全部插件目录 `res://addons`，仅重读发生变更的 `.gd` 脚本并自动清理已删除脚本缓存；[br]
## 2. [b]静态预编译正则[/b]：全局仅编译一次 `RegEx` 集合，兼容编译器显式注册、`BTBuilder` 链式注册以及 `# @flow_*` 声明式注解；[br]
## 3. [b]注释去噪过滤[/b]：代码匹配前自动剥离 `##` 文档注释与 `#` 废弃代码行，防止注释掉的旧算子污染检视器补全列表。

static var _cached_result: Dictionary = {}
static var _file_cache: Dictionary = {} ## {String (fpath): {"mtime": int, "actions": PackedStringArray, "conditions": PackedStringArray, "events": PackedStringArray, "states": PackedStringArray}}
static var _regex_bundle: Dictionary = {}
static var _has_scanned: bool = false
static var _dirty: bool = true


#region 公开扫描与缓存失效接口

## 获取最新候选词表；若尚未扫描或已被标记为脏，自动执行单文件级增量刷新。
static func get_cached() -> Dictionary:
	if not _has_scanned or _dirty:
		return _scan_internal("res://", true)
	return _clone_result(_cached_result)


## 标记算子缓存已过期（由文件系统变更回调低开销触发，延迟至下次 `get_cached()` 按需增量重扫）。
static func mark_dirty() -> void:
	_dirty = true


## 清空全部静态文件缓存与编译结果。
static func clear_cache() -> void:
	_file_cache.clear()
	_cached_result.clear()
	_has_scanned = false
	_dirty = true


## 强制刷新指定根目录并返回算子词表。
static func refresh(root_dir: String = "res://") -> Dictionary:
	if root_dir == "res://":
		_file_cache.clear()
	return _scan_internal(root_dir, root_dir == "res://")


## 扫描指定目录并返回 `{"actions": PackedStringArray, "conditions": PackedStringArray, "events": PackedStringArray, "states": PackedStringArray}`。
static func scan_project(root_dir: String = "res://") -> Dictionary:
	return _scan_internal(root_dir, root_dir == "res://")

#endregion


#region 内部增量扫描与注释安全提取

static func _scan_internal(root_dir: String, use_project_cache: bool) -> Dictionary:
	var rx_bundle: Dictionary = _get_regex_bundle()
	var gd_files: Array[String] = []
	_collect_gd_files_recursive(root_dir, root_dir, gd_files)

	var action_set: Dictionary = {}
	var cond_set: Dictionary = {}
	var event_set: Dictionary = {}
	var state_set: Dictionary = {}

	var now_unix: int = int(Time.get_unix_time_from_system())
	var seen_files: Dictionary = {}

	for fpath: String in gd_files:
		var entry: Dictionary = {}
		if use_project_cache:
			seen_files[fpath] = true
			var mtime: int = int(FileAccess.get_modified_time(fpath))
			var can_trust_mtime: bool = mtime > 0 and mtime < (now_unix - 1)
			if can_trust_mtime and _file_cache.has(fpath):
				var cached_entry: Dictionary = _file_cache[fpath] as Dictionary
				if int(cached_entry.get("mtime", -1)) == mtime:
					entry = cached_entry
			if entry.is_empty():
				entry = _parse_single_gd_file(fpath, mtime, rx_bundle)
				_file_cache[fpath] = entry
		else:
			entry = _parse_single_gd_file(fpath, 0, rx_bundle)

		_merge_tokens(entry.get("actions", PackedStringArray()) as PackedStringArray, action_set)
		_merge_tokens(entry.get("conditions", PackedStringArray()) as PackedStringArray, cond_set)
		_merge_tokens(entry.get("events", PackedStringArray()) as PackedStringArray, event_set)
		_merge_tokens(entry.get("states", PackedStringArray()) as PackedStringArray, state_set)

	if use_project_cache:
		for cached_key: Variant in _file_cache.keys():
			var cpath: String = str(cached_key)
			if not seen_files.has(cpath):
				_file_cache.erase(cpath)

	var result: Dictionary = {
		"actions": _sorted_packed_keys(action_set),
		"conditions": _sorted_packed_keys(cond_set),
		"events": _sorted_packed_keys(event_set),
		"states": _sorted_packed_keys(state_set),
	}
	if use_project_cache:
		_cached_result = _clone_result(result)
		_has_scanned = true
		_dirty = false
	return result


static func _parse_single_gd_file(fpath: String, mtime: int, rx_bundle: Dictionary) -> Dictionary:
	var content: String = FileAccess.get_file_as_string(fpath)
	if content.is_empty():
		return {
			"mtime": mtime,
			"actions": PackedStringArray(),
			"conditions": PackedStringArray(),
			"events": PackedStringArray(),
			"states": PackedStringArray(),
		}

	var f_actions: Dictionary = {}
	var f_conds: Dictionary = {}
	var f_events: Dictionary = {}
	var f_states: Dictionary = {}

	# 1. 提取显式单井号声明式注解（# @flow_*）
	if content.contains("@flow_"):
		_collect_matches(content, rx_bundle["action_anno"] as RegEx, f_actions)
		_collect_matches(content, rx_bundle["cond_anno"] as RegEx, f_conds)
		_collect_matches(content, rx_bundle["event_anno"] as RegEx, f_events)
		_collect_matches(content, rx_bundle["state_anno"] as RegEx, f_states)

	# 2. 剥离注释后提取真实代码注册调用（杜绝已注释代码污染候选词表）
	var code_only: String = _strip_gd_comments(content)
	if not code_only.is_empty():
		_collect_matches(code_only, rx_bundle["action_call"] as RegEx, f_actions)
		_collect_matches(code_only, rx_bundle["bt_service_call"] as RegEx, f_actions)
		_collect_matches(code_only, rx_bundle["bt_action_call"] as RegEx, f_actions)
		_collect_matches(code_only, rx_bundle["cond_call"] as RegEx, f_conds)
		_collect_matches(code_only, rx_bundle["bt_cond_call"] as RegEx, f_conds)
		_collect_matches(code_only, rx_bundle["event_call"] as RegEx, f_events)
		_collect_matches(code_only, rx_bundle["state_call"] as RegEx, f_states)

	return {
		"mtime": mtime,
		"actions": _sorted_packed_keys(f_actions),
		"conditions": _sorted_packed_keys(f_conds),
		"events": _sorted_packed_keys(f_events),
		"states": _sorted_packed_keys(f_states),
	}


static func _strip_gd_comments(content: String) -> String:
	var clean_lines: PackedStringArray = PackedStringArray()
	for raw_line: String in content.split("\n"):
		var trimmed: String = raw_line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue
		if raw_line.find("#") < 0:
			clean_lines.append(raw_line)
		else:
			var stripped: String = _strip_inline_comment(raw_line)
			if not stripped.strip_edges().is_empty():
				clean_lines.append(stripped)
	return "\n".join(clean_lines)


static func _strip_inline_comment(line: String) -> String:
	var in_single: bool = false
	var in_double: bool = false
	var escaped: bool = false
	var n: int = line.length()
	for i: int in range(n):
		var ch: String = line[i]
		if escaped:
			escaped = false
			continue
		if ch == "\\" and (in_single or in_double):
			escaped = true
			continue
		if ch == "'" and not in_double:
			in_single = not in_single
		elif ch == "\"" and not in_single:
			in_double = not in_double
		elif ch == "#" and not in_single and not in_double:
			return line.substr(0, i)
	return line


static func _collect_gd_files_recursive(
	dir_path: String,
	scan_root: String,
	out_files: Array[String]
) -> void:
	if FlowGraphContracts.is_skipped_scan_dir(dir_path, scan_root):
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
				_collect_gd_files_recursive(full_path, scan_root, out_files)
			elif fname.ends_with(".gd"):
				out_files.append(full_path)
		fname = da.get_next()
	da.list_dir_end()


static func _get_regex_bundle() -> Dictionary:
	if not _regex_bundle.is_empty():
		return _regex_bundle

	_regex_bundle = {
		"action_call": _compile_rx("\\bregister_(?:action|service)\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']"),
		"bt_service_call": _compile_rx("\\.service\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']"),
		"bt_action_call": _compile_rx("\\.action\\s*\\(\\s*(?:&?[\"'][^\"']*[\"']|[^,()]+)\\s*,\\s*[^,()]+\\s*,\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']"),
		"action_anno": _compile_rx("(?:^|[^#])#\\s*@flow_action\\s+([A-Za-z0-9_./:-]+)"),
		"cond_call": _compile_rx("\\bregister_condition\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']"),
		"bt_cond_call": _compile_rx("\\.condition\\s*\\(\\s*(?:&?[\"'][^\"']*[\"']|[^,()]+)\\s*,\\s*[^,()]+\\s*,\\s*&?[\"']!?([A-Za-z0-9_./:-]+)[\"']"),
		"cond_anno": _compile_rx("(?:^|[^#])#\\s*@flow_condition\\s+([A-Za-z0-9_./:-]+)"),
		"event_call": _compile_rx("\\bfire_event\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']"),
		"event_anno": _compile_rx("(?:^|[^#])#\\s*@flow_event\\s+([A-Za-z0-9_./:-]+)"),
		"state_call": _compile_rx("\\badd_(?:callable|state)\\s*\\(\\s*&?[\"']([A-Za-z0-9_./:-]+)[\"']"),
		"state_anno": _compile_rx("(?:^|[^#])#\\s*@flow_state\\s+([A-Za-z0-9_./:-]+)"),
	}
	return _regex_bundle


static func _compile_rx(pattern: String) -> RegEx:
	var rx := RegEx.new()
	rx.compile(pattern)
	return rx


static func _collect_matches(content: String, rx: RegEx, target_set: Dictionary) -> void:
	var matches: Array[RegExMatch] = rx.search_all(content)
	for m: RegExMatch in matches:
		var token: String = m.get_string(1).strip_edges()
		if not token.is_empty():
			target_set[token] = true


static func _merge_tokens(tokens: PackedStringArray, target_set: Dictionary) -> void:
	for token: String in tokens:
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
