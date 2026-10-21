@tool
extends RefCounted

## 路由级场景扫描与继承链自省器（Scene Scanner）。[br]
##
## [b]核心职责：[/b][br]
## 1. 递归扫描 [code]res://src/game/[/code] 下的 [code].tscn[/code] 文件；[br]
## 2. 轻量解析 [code].tscn[/code] 头部关联脚本与继承基类（[BaseScene] / [BaseDialog]），结合目录约定将其精准归入 `scenes`、`dialogs`、`components` 三大命名空间；[br]
## 3. 自动忽略各业务模块内部的私有局部子控件与 [code]res://src/test/[/code] 测试场景，防止生成表膨胀。

const SHARED_COMPONENT_PREFIX: String = "res://src/game/shared/component/"


#region Public API
## 扫描指定目录并返回分类后的路由字典。[br]
## @return 返回字典：{"scenes": Dictionary, "dialogs": Dictionary, "components": Dictionary}
static func scan(scan_root: String, planned_scenes: Dictionary = {}) -> Dictionary:
	var scenes: Dictionary = planned_scenes.duplicate()
	var dialogs: Dictionary = {}
	var components: Dictionary = {}

	_scan_dir_recursive(scan_root, scenes, dialogs, components)

	return {
		"scenes": scenes,
		"dialogs": dialogs,
		"components": components,
	}
#endregion


#region Internal Directory & TSCN Introspection
static func _scan_dir_recursive(
	dir_path: String,
	scenes: Dictionary,
	dialogs: Dictionary,
	components: Dictionary
) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var full_path := dir_path.path_join(entry)
			if dir.current_is_dir():
				_scan_dir_recursive(full_path, scenes, dialogs, components)
			elif entry.ends_with(".tscn"):
				_classify_tscn(full_path, scenes, dialogs, components)
		entry = dir.get_next()
	dir.list_dir_end()


static func _classify_tscn(
	tscn_path: String,
	scenes: Dictionary,
	dialogs: Dictionary,
	components: Dictionary
) -> void:
	var file_stem := tscn_path.get_file().get_basename()
	var root_base := _inspect_tscn_root_script_base(tscn_path)

	# 1. 模态弹窗判定：文件名以 _dialog 结尾，或根节点脚本继承自 BaseDialog
	if file_stem.ends_with("_dialog") or root_base == &"BaseDialog":
		var key := _to_const_key(file_stem, "_dialog")
		dialogs[key] = tscn_path
		return

	# 2. 顶层场景判定：文件名以 _scene 结尾，或根节点脚本继承自 BaseScene
	if file_stem.ends_with("_scene") or root_base == &"BaseScene":
		var key := _to_const_key(file_stem, "_scene")
		scenes[key] = tscn_path
		return

	# 3. 跨模块通用组件预制件：位于 res://src/game/shared/component/ 下
	if tscn_path.begins_with(SHARED_COMPONENT_PREFIX):
		var key := _to_const_key(file_stem, "")
		components[key] = tscn_path


## 轻量读取 .tscn 文本前 120 行，提取根节点挂载脚本的继承基类名（耗时 < 1ms，零节点实例化）
static func _inspect_tscn_root_script_base(tscn_path: String) -> StringName:
	var file := FileAccess.open(tscn_path, FileAccess.READ)
	if file == null:
		return &""

	var ext_scripts: Dictionary = {}
	var root_script_id: String = ""
	var in_root_node := false
	var line_count := 0

	while not file.eof_reached() and line_count < 120:
		var line := file.get_line().strip_edges()
		line_count += 1

		if line.begins_with("[ext_resource") and line.contains("type=\"Script\""):
			var path_val := _extract_attr(line, "path")
			var id_val := _extract_attr(line, "id")
			if not path_val.is_empty() and not id_val.is_empty():
				ext_scripts[id_val] = path_val
		elif line.begins_with("[node "):
			if not line.contains("parent="):
				in_root_node = true
				if line.contains("script = ExtResource("):
					root_script_id = _extract_ext_resource_id(line)
					break
			else:
				if in_root_node:
					break
		elif in_root_node and line.begins_with("script = ExtResource("):
			root_script_id = _extract_ext_resource_id(line)
			break

	if root_script_id.is_empty() or not ext_scripts.has(root_script_id):
		return &""

	var script_path: String = ext_scripts[root_script_id]
	return _inspect_gd_extends(script_path)


static func _inspect_gd_extends(script_path: String) -> StringName:
	if not FileAccess.file_exists(script_path):
		return &""
	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return &""
	var line_count := 0
	while not file.eof_reached() and line_count < 30:
		var line := file.get_line().strip_edges()
		line_count += 1
		if line.begins_with("extends "):
			var base_name := line.substr(8).strip_edges().get_slice(" ", 0).get_slice("\t", 0)
			return StringName(base_name)
	return &""


static func _extract_attr(line: String, attr_name: String) -> String:
	var token := attr_name + "=\""
	var start := line.find(token)
	if start == -1:
		return ""
	start += token.length()
	var end := line.find("\"", start)
	if end == -1:
		return ""
	return line.substr(start, end - start)


static func _extract_ext_resource_id(line: String) -> String:
	var token := "ExtResource(\""
	var start := line.find(token)
	if start == -1:
		return ""
	start += token.length()
	var end := line.find("\")", start)
	if end == -1:
		return ""
	return line.substr(start, end - start)


static func _to_const_key(stem: String, strip_suffix: String) -> String:
	var cleaned := stem
	if not strip_suffix.is_empty() and cleaned.ends_with(strip_suffix) and cleaned.length() > strip_suffix.length():
		cleaned = cleaned.substr(0, cleaned.length() - strip_suffix.length())
	return cleaned.to_snake_case().to_upper()
#endregion
