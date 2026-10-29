@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 场景与资源管理模块 (Scene & Resource Module)


func register_commands(registry: CommandRegistry) -> void:
	# 1. scene.create
	registry.register_command(
		"scene.create",
		"Create a new scene (from root node type or inherited base scene) and save to disk",
		{
			"path": {"type": "string", "required": true, "description": "Scene file path (e.g. res://scenes/main.tscn)"},
			"root_node_type": {"type": "string", "default": "Node", "description": "Root node type (e.g. Node2D, Control, Node3D)"},
			"root_node_name": {"type": "string", "default": "", "description": "Optional explicit root node name"},
			"base_scene_path": {"type": "string", "default": "", "description": "Optional base .tscn path for scene inheritance"},
			"root_script": {"type": "string", "default": "", "description": "Optional .gd script path to attach to root node"},
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

	var base_scene_path: String = str(p.get("base_scene_path", "")).strip_edges()
	var root_type: String = str(p.get("root_node_type", "Node")).strip_edges()
	var root_name: String = str(p.get("root_node_name", "")).strip_edges()
	var root_script_path: String = str(p.get("root_script", "")).strip_edges()

	var root: Node = null
	if not base_scene_path.is_empty():
		if not base_scene_path.begins_with("res://"):
			base_scene_path = "res://" + base_scene_path
		var base_packed := ResourceLoader.load(base_scene_path, "PackedScene") as PackedScene
		if base_packed == null:
			return RpcError.not_found("Base scene not found: %s" % base_scene_path)
		root = base_packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
		root_type = root.get_class()
	else:
		if not ClassDB.can_instantiate(root_type):
			return RpcError.invalid_params("Cannot instantiate root node type: %s" % root_type)
		root = ClassDB.instantiate(root_type)

	if not root_name.is_empty():
		root.name = root_name
	elif base_scene_path.is_empty():
		root.name = path.get_file().get_basename().capitalize().replace(" ", "")

	if not root_script_path.is_empty():
		if not root_script_path.begins_with("res://"):
			root_script_path = "res://" + root_script_path
		var scr := ResourceLoader.load(root_script_path, "Script", ResourceLoader.CACHE_MODE_REPLACE)
		if scr == null:
			root.free()
			return RpcError.not_found("Root script not found: %s" % root_script_path)
		root.set_script(scr)

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
	return {"scene_path": path, "root_node_type": root_type, "root_node_name": root_name}


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
		res.set(k, ctx.parse_property_value_for(res, k, props[k]))

	var dir := res_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := ResourceSaver.save(res, res_path)
	if err != OK:
		return RpcError.execution_error("Failed to save resource: %d" % err)

	return {"resource_path": res_path, "resource_type": res_type}
