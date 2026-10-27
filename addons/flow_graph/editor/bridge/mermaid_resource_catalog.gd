@tool
extends RefCounted

## 项目图资源目录索引器（Project Graph Resource Catalog）。[br]
##
## [b]设计要点：[/b][br]
## 1. [b]零加载扫描[/b]：编辑器内直接遍历 `EditorFileSystem` 已建好的文件索引（文件类型与脚本类名均已缓存），全程不加载任何 `.tres`；[br]
## 2. [b]零耦合协议识别[/b]：不硬编码 `FsmGraphDef` / `BTGraphDef`，而是从全局类列表中自动找出「继承 `Resource` 且实现 `to_mermaid_ir` + `apply_mermaid_ir`」的类，新增图资源类型自动纳入；[br]
## 3. [b]增量刷新[/b]：监听 `filesystem_changed`（新建 / 删除 / 重命名 / 外部 git pull）与 `script_classes_updated`，合并为单次延迟重扫，仅在结果签名变化时发出 [signal catalog_changed]；[br]
## 4. [b]无编辑器回退[/b]：无头测试等非编辑器上下文改为遍历磁盘，并仅读取 `.tres` 首行头部的 `script_class` 判定类型。

signal catalog_changed()

const SCHEMA_FSM: StringName = &"fsm"
const SCHEMA_BT: StringName = &"bt"
const SCHEMA_OTHER: StringName = &"other"
const PROTOCOL_READ: StringName = &"to_mermaid_ir"
const PROTOCOL_WRITE: StringName = &"apply_mermaid_ir"
const PROTOCOL_READ_FG: StringName = &"to_flow_graph_ir"
const PROTOCOL_WRITE_FG: StringName = &"apply_flow_graph_ir"
const SKIP_DIR_PREFIXES: Array[String] = ["res://.godot", "res://addons/flow_graph"]

## `Array[Dictionary]`: `{"path": String, "file": String, "dir": String, "class": String, "schema": StringName}`，按路径排序
var entries: Array[Dictionary] = []
## `{String (class_name): StringName (schema)}`
var protocol_classes: Dictionary = {}

var _efs: EditorFileSystem = null
var _signature: String = ""
var _rescan_queued: bool = false


#region 生命周期

func setup() -> void:
	if Engine.is_editor_hint():
		_efs = EditorInterface.get_resource_filesystem()
		if _efs != null:
			_efs.filesystem_changed.connect(request_rescan)
			_efs.script_classes_updated.connect(_on_script_classes_updated)
	rescan(true)


func dispose() -> void:
	if _efs != null:
		if _efs.filesystem_changed.is_connected(request_rescan):
			_efs.filesystem_changed.disconnect(request_rescan)
		if _efs.script_classes_updated.is_connected(_on_script_classes_updated):
			_efs.script_classes_updated.disconnect(_on_script_classes_updated)
	_efs = null

#endregion


#region 公开查询与扫描

## 合并同一帧内的多次文件系统事件，下一空闲帧统一重扫。
func request_rescan() -> void:
	if _rescan_queued:
		return
	_rescan_queued = true
	_deferred_rescan.call_deferred()


## 立即重扫；结果变化（或 `force_signal`）时发出 [signal catalog_changed]，返回是否变化。
func rescan(force_signal: bool = false) -> bool:
	if protocol_classes.is_empty():
		protocol_classes = collect_protocol_classes()

	var found: Array[Dictionary] = []
	var root_dir: EditorFileSystemDirectory = _efs.get_filesystem() if _efs != null else null
	if root_dir != null:
		_walk_editor_index(root_dir, found)
	else:
		_walk_disk("res://", found)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["path"]) < str(b["path"]))

	var sig_parts: PackedStringArray = PackedStringArray()
	for e: Dictionary in found:
		sig_parts.append("%s|%s" % [str(e["path"]), str(e["class"])])
	var sig: String = "\n".join(sig_parts)
	var changed: bool = sig != _signature
	_signature = sig
	entries = found
	if changed or force_signal:
		catalog_changed.emit()
	return changed


func find_entry(path: String) -> Dictionary:
	for e: Dictionary in entries:
		if str(e["path"]) == path:
			return e
	return {}


## 收集所有「继承 `Resource` 且实现图 IR 读写协议」的全局类。只加载这些候选类的脚本本身，不加载任何资源实例。
static func collect_protocol_classes() -> Dictionary:
	var by_name: Dictionary = {}
	for info: Dictionary in ProjectSettings.get_global_class_list():
		by_name[str(info.get("class", ""))] = info

	var out: Dictionary = {}
	for cname_v: Variant in by_name.keys():
		var cname: String = str(cname_v)
		if not _extends_resource(cname, by_name):
			continue
		var spath: String = str((by_name[cname] as Dictionary).get("path", ""))
		if spath.is_empty() or not ResourceLoader.exists(spath):
			continue
		var scr: Script = load(spath) as Script
		if scr != null:
			var has_fg: bool = _script_has_method(scr, PROTOCOL_READ_FG) and _script_has_method(scr, PROTOCOL_WRITE_FG)
			var has_mg: bool = _script_has_method(scr, PROTOCOL_READ) and _script_has_method(scr, PROTOCOL_WRITE)
			if has_fg or has_mg:
				out[cname] = infer_schema(cname)
	return out


## 依类名推断图种类，仅用于列表筛选；无法判断时归为 `SCHEMA_OTHER`。
static func infer_schema(cname: String) -> StringName:
	var lower: String = cname.to_lower()
	if lower.contains("fsm") or lower.contains("statemachine") or lower.contains("state_machine"):
		return SCHEMA_FSM
	if lower.begins_with("bt") or lower.contains("behavior") or lower.contains("behaviour"):
		return SCHEMA_BT
	return SCHEMA_OTHER

#endregion


#region 内部实现

func _deferred_rescan() -> void:
	_rescan_queued = false
	rescan(false)


func _on_script_classes_updated() -> void:
	protocol_classes.clear()
	request_rescan()


func _walk_editor_index(dir: EditorFileSystemDirectory, found: Array[Dictionary]) -> void:
	var dpath: String = dir.get_path()
	for prefix: String in SKIP_DIR_PREFIXES:
		if dpath.begins_with(prefix):
			return
	for i: int in range(dir.get_file_count()):
		var cls: String = dir.get_file_script_class_name(i)
		if not cls.is_empty() and protocol_classes.has(cls):
			found.append(_make_entry(dir.get_file_path(i), cls))
	for j: int in range(dir.get_subdir_count()):
		_walk_editor_index(dir.get_subdir(j), found)


func _walk_disk(dpath: String, found: Array[Dictionary]) -> void:
	for prefix: String in SKIP_DIR_PREFIXES:
		if dpath.begins_with(prefix):
			return
	var da: DirAccess = DirAccess.open(dpath)
	if da == null:
		return
	da.include_hidden = false
	da.list_dir_begin()
	var fname: String = da.get_next()
	while not fname.is_empty():
		if not fname.begins_with("."):
			var full: String = dpath.path_join(fname)
			if da.current_is_dir():
				_walk_disk(full, found)
			elif fname.get_extension() == "tres":
				var cls: String = _read_tres_script_class(full)
				if not cls.is_empty() and protocol_classes.has(cls):
					found.append(_make_entry(full, cls))
		fname = da.get_next()
	da.list_dir_end()


## 只读 `.tres` 第一行头部（`[gd_resource ... script_class="X" ...]`），不解析、不加载资源。
static func _read_tres_script_class(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var head: String = f.get_line()
	f.close()
	var key: String = "script_class=\""
	var idx: int = head.find(key)
	if idx < 0:
		return ""
	var start: int = idx + key.length()
	var stop: int = head.find("\"", start)
	return head.substr(start, stop - start) if stop > start else ""


func _make_entry(path: String, cls: String) -> Dictionary:
	return {
		"path": path,
		"file": path.get_file(),
		"dir": path.get_base_dir(),
		"class": cls,
		"schema": protocol_classes.get(cls, SCHEMA_OTHER) as StringName,
	}


static func _extends_resource(cname: String, by_name: Dictionary) -> bool:
	var cur: String = cname
	var guard: int = 0
	while by_name.has(cur) and guard < 32:
		cur = str((by_name[cur] as Dictionary).get("base", ""))
		guard += 1
	if cur.is_empty() or not ClassDB.class_exists(cur):
		return false
	return cur == "Resource" or ClassDB.is_parent_class(cur, "Resource")


static func _script_has_method(scr: Script, method_name: StringName) -> bool:
	var s: Script = scr
	while s != null:
		for md: Dictionary in s.get_script_method_list():
			if StringName(str(md.get("name", ""))) == method_name:
				return true
		s = s.get_base_script()
	return false

#endregion
