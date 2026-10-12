@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 项目元数据与文件树查询模块 (Project Module)


func register_commands(registry: CommandRegistry) -> void:
	# 1. project.info
	registry.register_command(
		"project.info",
		"Get project information and engine metadata",
		{},
		_get_project_info
	)
	registry.register_alias("get_project_info", "project.info")

	# 2. project.list_files
	registry.register_command(
		"project.list_files",
		"List project files filtered by extensions",
		{
			"extensions": {"type": "array", "default": [], "description": "Optional list of extensions (e.g. ['tscn', 'gd'])"},
		},
		_list_files
	)
	registry.register_alias("list_project_files", "project.list_files")

	# 3. project.settings
	registry.register_command(
		"project.settings",
		"Query project settings optionally filtered by prefix",
		{
			"prefix": {"type": "string", "default": "", "description": "Optional setting prefix (e.g. 'application/', 'display/')"},
		},
		_get_settings
	)
	registry.register_alias("get_project_settings", "project.settings")


func _get_project_info(_p: Dictionary) -> Variant:
	var proj_name = ProjectSettings.get_setting("application/config/name", "Untitled Project")
	var proj_version = ProjectSettings.get_setting("application/config/version", "1.0.0")
	var proj_path = ProjectSettings.globalize_path("res://")
	var v_info = Engine.get_version_info()

	var root := ctx.get_scene_root()
	var cur_scene := root.scene_file_path if root != null else ""

	return {
		"project_name": proj_name,
		"project_version": proj_version,
		"project_path": proj_path,
		"godot_version": {
			"major": v_info.get("major", 0),
			"minor": v_info.get("minor", 0),
			"patch": v_info.get("patch", 0),
			"status": v_info.get("status", "")
		},
		"current_scene": cur_scene
	}


func _list_files(p: Dictionary) -> Variant:
	var extensions: Array = p.get("extensions", [])
	var files: Array[String] = []
	var queue: Array[String] = ["res://"]

	while not queue.is_empty():
		var current_path = queue.pop_front()
		var dir := DirAccess.open(current_path)
		if dir == null:
			continue

		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if dir.current_is_dir():
				if not file_name.begins_with(".") and file_name != "addons":
					queue.append(current_path.path_join(file_name))
			else:
				var ext := file_name.get_extension().to_lower()
				if extensions.is_empty() or extensions.has(ext):
					files.append(current_path.path_join(file_name))
			file_name = dir.get_next()

	return {"files": files}


func _get_settings(p: Dictionary) -> Variant:
	var prefix: String = p.get("prefix", "")
	var settings := {}

	for prop in ProjectSettings.get_property_list():
		var name: String = prop.name
		if prefix.is_empty() or name.begins_with(prefix):
			settings[name] = ProjectSettings.get_setting(name)

	return {"settings": settings}
