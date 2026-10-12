@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 场景与资源管理模块 (Scene & Resource Module)


func register_commands(registry: CommandRegistry) -> void:
	# 1. scene.create
	registry.register_command(
		"scene.create",
		"Create a new empty scene with specified root node type and save to disk",
		{
			"path": {"type": "string", "required": true, "description": "Scene file path (e.g. res://scenes/main.tscn)"},
			"root_node_type": {"type": "string", "default": "Node", "description": "Root node type (e.g. Node2D, Control, Node3D)"},
		},
		_create_scene
	)
	registry.register_alias("create_scene", "scene.create")

	# 2. scene.save
	registry.register_command(
		"scene.save",
		"Save the currently edited scene to disk",
		{
			"path": {"type": "string", "default": "", "description": "Optional path to save to (leaves blank to save current file)"},
		},
		_save_scene
	)
	registry.register_alias("save_scene", "scene.save")

	# 3. scene.open
	registry.register_command(
		"scene.open",
		"Open an existing scene in the Godot editor",
		{
			"path": {"type": "string", "required": true, "description": "Scene file path (e.g. res://scenes/main.tscn)"},
		},
		_open_scene
	)
	registry.register_alias("open_scene", "scene.open")

	# 4. scene.get_current
	registry.register_command(
		"scene.get_current",
		"Get metadata of the currently active edited scene",
		{},
		_get_current_scene
	)
	registry.register_alias("get_current_scene", "scene.get_current")

	# 5. resource.create
	registry.register_command(
		"resource.create",
		"Create a new resource and save to disk",
		{
			"resource_type": {"type": "string", "required": true, "description": "Resource class name (e.g. StyleBoxFlat, StandardMaterial3D)"},
			"resource_path": {"type": "string", "required": true, "description": "Resource save path (e.g. res://theme/box.tres)"},
			"properties": {"type": "dictionary", "default": {}, "description": "Optional initial property dictionary"},
		},
		_create_resource
	)
	registry.register_alias("create_resource", "resource.create")


func _create_scene(p: Dictionary) -> Variant:
	var path: String = p.path
	if not path.begins_with("res://"):
		path = "res://" + path
	if not path.ends_with(".tscn"):
		path += ".tscn"

	var root_type: String = p.root_node_type
	if not ClassDB.can_instantiate(root_type):
		return RpcError.invalid_params("Cannot instantiate root node type: %s" % root_type)

	var root: Node = ClassDB.instantiate(root_type)
	root.name = path.get_file().get_basename().capitalize().replace(" ", "")

	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		root.free()
		return RpcError.execution_error("Failed to pack new scene: %d" % pack_err)

	var save_err := ResourceSaver.save(packed, path)
	root.free()
	if save_err != OK:
		return RpcError.execution_error("Failed to save new scene: %d" % save_err)

	# 切换至新创建的场景
	ctx.open_scene(path)
	return {"scene_path": path, "root_node_type": root_type}


func _save_scene(p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return RpcError.execution_error("No scene is currently being edited")

	var path: String = p.get("path", "")
	if path.is_empty():
		path = root.scene_file_path

	if path.is_empty():
		return RpcError.invalid_params("Scene path cannot be empty for untitled scene")

	if not path.begins_with("res://"):
		path = "res://" + path
	if not path.ends_with(".tscn"):
		path += ".tscn"

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		return RpcError.execution_error("Failed to pack scene: %d" % pack_err)

	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		return RpcError.execution_error("Failed to save scene: %d" % save_err)

	ctx.save_scene()
	return {"scene_path": path}


func _open_scene(p: Dictionary) -> Variant:
	var path: String = p.path
	if not path.begins_with("res://"):
		path = "res://" + path
	if not FileAccess.file_exists(path):
		return RpcError.not_found("Scene file does not exist: %s" % path)

	ctx.open_scene(path)
	return {"scene_path": path}


func _get_current_scene(_p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	if root == null:
		return {
			"scene_path": "",
			"root_node_name": "",
			"root_node_type": ""
		}

	return {
		"scene_path": root.scene_file_path,
		"root_node_name": root.name,
		"root_node_type": root.get_class()
	}


func _create_resource(p: Dictionary) -> Variant:
	var res_type: String = p.resource_type
	var res_path: String = p.resource_path
	var props: Dictionary = p.properties

	if not ClassDB.can_instantiate(res_type):
		return RpcError.invalid_params("Cannot instantiate resource of type: %s" % res_type)

	var res = ClassDB.instantiate(res_type)
	if not res is Resource:
		return RpcError.invalid_params("Type %s is not a Resource" % res_type)

	for k in props.keys():
		res.set(k, ctx.parse_property_value(props[k]))

	var dir := res_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := ResourceSaver.save(res, res_path)
	if err != OK:
		return RpcError.execution_error("Failed to save resource: %d" % err)

	return {"resource_path": res_path, "resource_type": res_type}
