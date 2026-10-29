@tool
extends RefCounted

## 编辑器上下文代理 (Editor Context)
## 统一隔离 EditorInterface、UndoRedoManager 与节点树寻址。
## 为所有指令操作赋予完整的编辑器撤销/重做 (Ctrl+Z) 记录能力。

var _plugin: EditorPlugin = null


func _init(plugin: EditorPlugin = null) -> void:
	_plugin = plugin


func get_interface() -> EditorInterface:
	if _plugin != null and _plugin.has_method("get_editor_interface"):
		return _plugin.get_editor_interface()
	return null


func get_scene_root() -> Node:
	var iface := get_interface()
	return iface.get_edited_scene_root() if iface != null else null


func get_undo_redo() -> EditorUndoRedoManager:
	if _plugin != null and _plugin.has_method("get_undo_redo"):
		return _plugin.get_undo_redo()
	return null


func mark_scene_unsaved() -> void:
	var iface := get_interface()
	if iface != null:
		iface.mark_scene_as_unsaved()


func open_scene(path: String) -> void:
	var iface := get_interface()
	if iface != null:
		iface.open_scene_from_path(path)


func save_scene() -> void:
	var iface := get_interface()
	if iface != null:
		iface.save_scene()


func get_script_editor() -> ScriptEditor:
	var iface := get_interface()
	return iface.get_script_editor() if iface != null else null


func get_selection() -> EditorSelection:
	var iface := get_interface()
	return iface.get_selection() if iface != null else null


func is_playing_scene() -> bool:
	var iface := get_interface()
	return iface.is_playing_scene() if iface != null else false


func get_base_control() -> Control:
	var iface := get_interface()
	return iface.get_base_control() if iface != null else null


func reimport_files(files: PackedStringArray) -> void:
	var iface := get_interface()
	if iface != null:
		var fs := iface.get_resource_filesystem()
		if fs != null:
			fs.reimport_files(files)


## 解析场景中的节点路径（支持 /root、相对路径与点语法）
func resolve_node(path: String) -> Node:
	var root := get_scene_root()
	if root == null:
		return null

	if path == "/root" or path == "" or path == ".":
		return root

	var clean_path := path
	if clean_path.begins_with("/root/"):
		clean_path = clean_path.substr(6)
	elif clean_path.begins_with("/"):
		clean_path = clean_path.substr(1)

	# 支持场景唯一名称 (%UniqueName) 快捷寻址
	if clean_path.begins_with("%"):
		var by_unique := root.get_node_or_null(clean_path)
		if by_unique != null:
			return by_unique

	# 尝试直接相对当前根节点查找
	var target := root.get_node_or_null(clean_path)
	if target != null:
		return target

	# 尝试全场景树查找
	var tree := root.get_tree()
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null(path)

	return null


## 撤销/重做支持：添加子节点
func add_child_undoable(parent: Node, child: Node, action_name: String = "MCP: Add Node") -> void:
	var root := get_scene_root()
	var ur := get_undo_redo()
	if ur != null:
		ur.create_action(action_name)
		ur.add_do_method(parent, "add_child", child)
		if root != null:
			ur.add_do_property(child, "owner", root)
		ur.add_do_reference(child)
		ur.add_undo_method(parent, "remove_child", child)
		ur.commit_action()
	else:
		parent.add_child(child)
		if root != null:
			child.owner = root

	mark_scene_unsaved()


## 撤销/重做支持：删除节点
func remove_node_undoable(node: Node, action_name: String = "MCP: Delete Node") -> void:
	var parent := node.get_parent()
	if parent == null:
		return
	var root := get_scene_root()
	var ur := get_undo_redo()
	if ur != null:
		ur.create_action(action_name)
		ur.add_do_method(parent, "remove_child", node)
		ur.add_undo_method(parent, "add_child", node)
		if root != null:
			ur.add_undo_property(node, "owner", root)
		ur.add_undo_reference(node)
		ur.commit_action()
	else:
		parent.remove_child(node)
		node.queue_free()

	mark_scene_unsaved()


## 撤销/重做支持：更新属性
func set_property_undoable(node: Node, property: String, new_val: Variant, action_name: String = "MCP: Set Property") -> void:
	var old_val: Variant = node.get(property)
	var ur := get_undo_redo()
	if ur != null:
		ur.create_action(action_name)
		ur.add_do_property(node, property, new_val)
		ur.add_undo_property(node, property, old_val)
		ur.commit_action()
	else:
		node.set(property, new_val)

	mark_scene_unsaved()


## 基于目标对象属性元数据的强类型安全解析（自动处理 res:// 资源加载、#Hex 颜色与 StringName/NodePath）
func parse_property_value_for(target: Object, property: String, val: Variant) -> Variant:
	if typeof(val) == TYPE_DICTIONARY:
		var d_raw: Dictionary = val
		if d_raw.has("$resource"):
			var rpath := String(d_raw.get("$resource", "")).strip_edges()
			return ResourceLoader.load(rpath) if not rpath.is_empty() else null
		if d_raw.has("$color"):
			var hex := String(d_raw.get("$color", "")).strip_edges()
			return Color.html(hex) if Color.html_is_valid(hex) else Color.WHITE

	var expected_type: int = TYPE_NIL
	if target != null:
		for prop in target.get_property_list():
			if String(prop.get("name", "")) == property:
				expected_type = int(prop.get("type", TYPE_NIL))
				break

	if expected_type == TYPE_OBJECT:
		if val == null:
			return null
		if typeof(val) == TYPE_STRING:
			var spath := String(val).strip_edges()
			if spath.is_empty():
				return null
			if spath.begins_with("res://"):
				return ResourceLoader.load(spath)

	if expected_type == TYPE_COLOR and typeof(val) == TYPE_STRING:
		var shex := String(val).strip_edges()
		if Color.html_is_valid(shex):
			return Color.html(shex)

	if expected_type == TYPE_STRING_NAME and typeof(val) == TYPE_STRING:
		return StringName(val)

	if expected_type == TYPE_NODE_PATH and typeof(val) == TYPE_STRING:
		return NodePath(val)

	if expected_type == TYPE_VECTOR2I:
		if typeof(val) == TYPE_DICTIONARY and val.has("x") and val.has("y"):
			return Vector2i(int(val.x), int(val.y))
		if typeof(val) == TYPE_STRING and String(val).contains(","):
			var vparts := String(val).split(",")
			if vparts.size() == 2:
				return Vector2i(int(vparts[0]), int(vparts[1]))

	return parse_property_value(val)


## 属性值解析转换（支持将 JSON 字符串或标量转换为 Godot 原生类型如 Vector2/Color 等）
func parse_property_value(val: Variant) -> Variant:
	if typeof(val) == TYPE_STRING:
		var s: String = val.strip_edges()
		# 尝试解析 JSON 格式的对象/数组
		if (s.begins_with("{") and s.ends_with("}")) or (s.begins_with("[") and s.ends_with("]")):
			var json := JSON.new()
			if json.parse(s) == OK:
				return json.get_data()
		# Vector2 格式: "100, 200"
		if s.contains(",") and not s.contains(":"):
			var parts := s.split(",")
			if parts.size() == 2:
				return Vector2(float(parts[0]), float(parts[1]))
			elif parts.size() == 3:
				return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			elif parts.size() == 4:
				return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
	elif typeof(val) == TYPE_DICTIONARY:
		var d: Dictionary = val
		if d.has("x") and d.has("y") and not d.has("z"):
			return Vector2(float(d.x), float(d.y))
		elif d.has("x") and d.has("y") and d.has("z"):
			return Vector3(float(d.x), float(d.y), float(d.z))
		elif d.has("r") and d.has("g") and d.has("b"):
			return Color(float(d.r), float(d.g), float(d.b), float(d.get("a", 1.0)))

	return val
