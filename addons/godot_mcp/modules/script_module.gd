@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 脚本管理模块 (Script Module)


func register_commands(registry: CommandRegistry) -> void:
	# 1. script.create
	registry.register_command(
		"script.create",
		"Create a new GDScript file and optionally attach it to a node",
		{
			"script_path": {"type": "string", "required": true, "description": "Script save path (e.g. res://scripts/player.gd)"},
			"content": {"type": "string", "required": true, "description": "GDScript source code"},
			"node_path": {"type": "string", "default": "", "description": "Optional node path to attach the script to"},
		},
		_create_script
	)
	registry.register_alias("create_script", "script.create")

	# 2. script.edit
	registry.register_command(
		"script.edit",
		"Edit an existing GDScript file",
		{
			"script_path": {"type": "string", "required": true, "description": "Script file path"},
			"content": {"type": "string", "required": true, "description": "New GDScript content"},
		},
		_edit_script
	)
	registry.register_alias("edit_script", "script.edit")

	# 3. script.get
	registry.register_command(
		"script.get",
		"Read GDScript content from file path or attached node",
		{
			"script_path": {"type": "string", "default": "", "description": "Script file path"},
			"node_path": {"type": "string", "default": "", "description": "Node path with script attached"},
		},
		_get_script
	)
	registry.register_alias("get_script", "script.get")

	# 4. script.template
	registry.register_command(
		"script.template",
		"Generate standard GDScript boilerplate template",
		{
			"extends_type": {"type": "string", "default": "Node", "description": "Base class (Node, Node2D, Control, etc.)"},
			"class_name": {"type": "string", "default": "", "description": "Optional class_name identifier"},
			"include_ready": {"type": "bool", "default": true, "description": "Include _ready()"},
			"include_process": {"type": "bool", "default": false, "description": "Include _process()"},
			"include_physics": {"type": "bool", "default": false, "description": "Include _physics_process()"},
			"include_input": {"type": "bool", "default": false, "description": "Include _input()"},
		},
		_create_template
	)
	registry.register_alias("create_script_template", "script.template")


func _create_script(p: Dictionary) -> Variant:
	var path: String = p.script_path
	if not path.begins_with("res://"):
		path = "res://" + path
	if not path.ends_with(".gd"):
		path += ".gd"

	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return RpcError.execution_error("Failed to open file for write: %s" % path)
	file.store_string(p.content)
	file.close()

	ctx.reimport_files(PackedStringArray([path]))

	var node_path: String = p.get("node_path", "")
	if not node_path.is_empty():
		var node := ctx.resolve_node(node_path)
		if node != null:
			var script_res = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
			if script_res != null:
				node.set_script(script_res)
				ctx.mark_scene_unsaved()

	return {"script_path": path}


func _edit_script(p: Dictionary) -> Variant:
	var path: String = p.script_path
	if not path.begins_with("res://"):
		path = "res://" + path
	if not FileAccess.file_exists(path):
		return RpcError.not_found("Script file does not exist: %s" % path)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return RpcError.execution_error("Failed to open file for write: %s" % path)
	file.store_string(p.content)
	file.close()

	ctx.reimport_files(PackedStringArray([path]))
	return {"script_path": path}


func _get_script(p: Dictionary) -> Variant:
	var path: String = p.get("script_path", "")
	var node_path: String = p.get("node_path", "")

	if path.is_empty() and not node_path.is_empty():
		var node := ctx.resolve_node(node_path)
		if node != null and node.get_script() != null:
			var scr: Script = node.get_script()
			path = scr.resource_path

	if path.is_empty():
		return RpcError.invalid_params("Either script_path or node_path with script must be provided")

	if not path.begins_with("res://"):
		path = "res://" + path

	if not FileAccess.file_exists(path):
		return RpcError.not_found("Script file does not exist: %s" % path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return RpcError.execution_error("Failed to read script: %s" % path)

	var content := file.get_as_text()
	file.close()

	return {"script_path": path, "content": content}


func _create_template(p: Dictionary) -> Variant:
	var out := ""
	var cls_name: String = p.get("class_name", "")
	if not cls_name.is_empty():
		out += "class_name %s\n" % cls_name

	out += "extends %s\n\n" % p.get("extends_type", "Node")

	if p.get("include_ready", true):
		out += "func _ready() -> void:\n\tpass\n\n"

	if p.get("include_process", false):
		out += "func _process(delta: float) -> void:\n\tpass\n\n"

	if p.get("include_physics", false):
		out += "func _physics_process(delta: float) -> void:\n\tpass\n\n"

	if p.get("include_input", false):
		out += "func _input(event: InputEvent) -> void:\n\tpass\n\n"

	return {"template": out.strip_edges()}
