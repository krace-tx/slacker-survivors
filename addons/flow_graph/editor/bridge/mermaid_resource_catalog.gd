@tool
extends RefCounted

## 项目图资源目录索引器（Project Graph Resource Catalog）。[br]
##
## [b]设计要点：[/b][br]
## 1. [b]零加载扫描[/b]：编辑器内直接遍历 `EditorFileSystem` 已建好的文件索引（跳过 `.godot` 与全部 `res://addons`），全程不加载任何 `.tres`；[br]
## 2. [b]协议继承链识别[/b]：复用 [`MermaidResourceBridge.collect_protocol_descriptors`](mermaid_resource_bridge.gd)，自动识别实现图 IR 读写协议的基类及自定义业务子类；[br]
## 3. [b]增量刷新与算子联动[/b]：监听 `filesystem_changed` 与 `script_classes_updated` 合并为单帧重扫，同步标记 [`FlowOperatorScanner.mark_dirty`](flow_operator_scanner.gd)，并维护 `O(1)` 路径索引表；[br]
## 4. [b]无编辑器回退[/b]：非编辑器上下文遍历磁盘，仅读取 `.tres` 头部声明块提取 `script_class` 或 `Script` 外部引用路径。

signal catalog_changed()

const MermaidResourceBridge = preload(FlowGraphContracts.SCRIPT_RESOURCE_BRIDGE)
const FlowOperatorScanner = preload(FlowGraphContracts.SCRIPT_OPERATOR_SCANNER)

const SCHEMA_FSM: StringName = FlowGraphContracts.SCHEMA_FSM
const SCHEMA_BT: StringName = FlowGraphContracts.SCHEMA_BT
const SCHEMA_OTHER: StringName = FlowGraphContracts.SCHEMA_OTHER

## `Array[Dictionary]`: `{"path": String, "file": String, "dir": String, "class": String, "schema": StringName}`，按路径排序
var entries: Array[Dictionary] = []
## `{String (class_name): StringName (schema)}`
var protocol_classes: Dictionary = {}

var _script_path_to_class: Dictionary = {} ## {String (script_path): String (class_name)}
var _entry_by_path: Dictionary = {} ## {String (resource_path): Dictionary}
var _efs: EditorFileSystem = null
var _signature: String = ""
var _rescan_queued: bool = false


#region 生命周期

func setup() -> void:
	if Engine.is_editor_hint():
		_efs = EditorInterface.get_resource_filesystem()
		if _efs != null:
			if not _efs.filesystem_changed.is_connected(request_rescan):
				_efs.filesystem_changed.connect(request_rescan)
			if not _efs.script_classes_updated.is_connected(_on_script_classes_updated):
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

## 合并同一帧内的多次文件系统事件，标记算子缓存过期并在下一空闲帧统一重扫。
func request_rescan() -> void:
	FlowOperatorScanner.mark_dirty()
	if _rescan_queued:
		return
	_rescan_queued = true
	_deferred_rescan.call_deferred()


## 立即重扫；结果变化（或 `force_signal`）时发出 [signal catalog_changed]，返回是否变化。
func rescan(force_signal: bool = false) -> bool:
	if force_signal:
		FlowOperatorScanner.mark_dirty()
	if protocol_classes.is_empty():
		_rebuild_protocol_maps()

	var found: Array[Dictionary] = []
	var root_dir: EditorFileSystemDirectory = _efs.get_filesystem() if _efs != null else null
	if root_dir != null:
		_walk_editor_index(root_dir, found)
	else:
		_walk_disk("res://", found)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["path"]) < str(b["path"]))

	var next_map: Dictionary = {}
	var sig_parts: PackedStringArray = PackedStringArray()
	for e: Dictionary in found:
		var epath: String = str(e["path"])
		next_map[epath] = e
		sig_parts.append("%s|%s|%s" % [epath, str(e["class"]), String(e["schema"] as StringName)])
	var sig: String = "\n".join(sig_parts)
	var changed: bool = sig != _signature
	_signature = sig
	entries = found
	_entry_by_path = next_map
	if changed or force_signal:
		catalog_changed.emit()
	return changed


## `O(1)` 按资源路径检索目录条目；未命中返回空字典。
func find_entry(path: String) -> Dictionary:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty() or not _entry_by_path.has(clean_path):
		return {}
	return _entry_by_path[clean_path] as Dictionary


## 收集所有「继承 `Resource` 且实现图 IR 读写协议」的全局类及其推断 Schema。
static func collect_protocol_classes() -> Dictionary:
	var descriptors: Dictionary = MermaidResourceBridge.collect_protocol_descriptors()
	var out: Dictionary = {}
	for cname_v: Variant in descriptors.keys():
		var cname: String = str(cname_v)
		var desc: Dictionary = descriptors[cname] as Dictionary
		out[cname] = desc.get("schema", SCHEMA_OTHER) as StringName
	return out


## 依类名与继承信息推断图种类；无法判断时归为 `SCHEMA_OTHER`。
static func infer_schema(cname: String) -> StringName:
	return MermaidResourceBridge.infer_schema_for_class(cname)

#endregion


#region 内部索引遍历与头部解析

func _rebuild_protocol_maps() -> void:
	protocol_classes.clear()
	_script_path_to_class.clear()
	var descriptors: Dictionary = MermaidResourceBridge.collect_protocol_descriptors()
	for cname_v: Variant in descriptors.keys():
		var cname: String = str(cname_v)
		var desc: Dictionary = descriptors[cname] as Dictionary
		var spath: String = str(desc.get("path", ""))
		protocol_classes[cname] = desc.get("schema", SCHEMA_OTHER) as StringName
		if not spath.is_empty():
			_script_path_to_class[spath] = cname

	# 兜底：若工程尚未建立全局类缓存，注入内置运行时 AST 映射以保障无头环境可用
	if not protocol_classes.has("FsmGraphDef") and FileAccess.file_exists(FlowGraphContracts.SCRIPT_RUNTIME_FSM_DEF):
		protocol_classes["FsmGraphDef"] = SCHEMA_FSM
		_script_path_to_class[FlowGraphContracts.SCRIPT_RUNTIME_FSM_DEF] = "FsmGraphDef"
	if not protocol_classes.has("BTGraphDef") and FileAccess.file_exists(FlowGraphContracts.SCRIPT_RUNTIME_BT_DEF):
		protocol_classes["BTGraphDef"] = SCHEMA_BT
		_script_path_to_class[FlowGraphContracts.SCRIPT_RUNTIME_BT_DEF] = "BTGraphDef"


func _deferred_rescan() -> void:
	_rescan_queued = false
	rescan(false)


func _on_script_classes_updated() -> void:
	protocol_classes.clear()
	_script_path_to_class.clear()
	request_rescan()


func _walk_editor_index(dir: EditorFileSystemDirectory, found: Array[Dictionary]) -> void:
	var dpath: String = dir.get_path()
	if FlowGraphContracts.is_skipped_scan_dir(dpath):
		return
	for i: int in range(dir.get_file_count()):
		var fpath: String = dir.get_file_path(i)
		var cls: String = dir.get_file_script_class_name(i)
		if cls.is_empty() and fpath.get_extension().to_lower() == "tres":
			cls = _read_tres_script_class(fpath, _script_path_to_class)
		if not cls.is_empty() and protocol_classes.has(cls):
			found.append(_make_entry(fpath, cls))
	for j: int in range(dir.get_subdir_count()):
		_walk_editor_index(dir.get_subdir(j), found)


func _walk_disk(dpath: String, found: Array[Dictionary]) -> void:
	if FlowGraphContracts.is_skipped_scan_dir(dpath):
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
			elif fname.get_extension().to_lower() == "tres":
				var cls: String = _read_tres_script_class(full, _script_path_to_class)
				if not cls.is_empty() and protocol_classes.has(cls):
					found.append(_make_entry(full, cls))
		fname = da.get_next()
	da.list_dir_end()


## 仅扫描 `.tres` 顶部声明块（最多 24 行，遇到 `[resource]` 正文立即终止），优先读取 `script_class`，缺失时回退匹配 `Script` 外部引用路径。
static func _read_tres_script_class(path: String, script_path_map: Dictionary = {}) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var line_budget: int = 24
	while not f.eof_reached() and line_budget > 0:
		line_budget -= 1
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("[gd_resource"):
			var sc: String = _extract_quoted_attr(line, "script_class=\"")
			if not sc.is_empty():
				f.close()
				return sc
		elif line.begins_with("[ext_resource") and line.contains("type=\"Script\""):
			if not script_path_map.is_empty():
				var spath: String = _extract_quoted_attr(line, "path=\"")
				if not spath.is_empty() and script_path_map.has(spath):
					f.close()
					return str(script_path_map[spath])
		elif line.begins_with("[resource]") or line.begins_with("[sub_resource"):
			break
	f.close()
	return ""


static func _extract_quoted_attr(line: String, attr_prefix: String) -> String:
	var idx: int = line.find(attr_prefix)
	if idx < 0:
		return ""
	var start: int = idx + attr_prefix.length()
	var stop: int = line.find("\"", start)
	return line.substr(start, stop - start) if stop > start else ""


func _make_entry(path: String, cls: String) -> Dictionary:
	return {
		"path": path,
		"file": path.get_file(),
		"dir": path.get_base_dir(),
		"class": cls,
		"schema": protocol_classes.get(cls, SCHEMA_OTHER) as StringName,
	}

#endregion
