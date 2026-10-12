@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 编辑器状态探查与动态脚本执行模块 (Editor Module)


func register_commands(registry: CommandRegistry) -> void:
	# 1. editor.state
	registry.register_command(
		"editor.state",
		"Get editor state including current scene, selected nodes, and playing status",
		{},
		_get_editor_state
	)
	registry.register_alias("get_editor_state", "editor.state")

	# 2. editor.eval
	registry.register_command(
		"editor.eval",
		"Dynamically evaluate GDScript code in the editor context and capture output",
		{
			"code": {"type": "string", "required": true, "description": "GDScript code block to execute in editor"},
		},
		_execute_editor_script
	)
	registry.register_alias("execute_editor_script", "editor.eval")


func _get_editor_state(_p: Dictionary) -> Variant:
	var root := ctx.get_scene_root()
	var cur_scene := root.scene_file_path if root != null else ""

	var script_editor := ctx.get_script_editor()
	var cur_script_res := script_editor.get_current_script() if script_editor != null else null
	var cur_script_path := cur_script_res.resource_path if cur_script_res != null else ""

	var selection := ctx.get_selection()
	var selected_paths: Array[String] = []
	if selection != null and root != null:
		for node in selection.get_selected_nodes():
			selected_paths.append(str(root.get_path_to(node)))

	return {
		"current_scene": cur_scene,
		"current_script": cur_script_path,
		"selected_nodes": selected_paths,
		"is_playing": ctx.is_playing_scene()
	}


func _execute_editor_script(p: Dictionary) -> Variant:
	var code: String = p.code
	if code.strip_edges().is_empty():
		return RpcError.invalid_params("Code cannot be empty")

	var script := GDScript.new()
	var script_template := """@tool
extends Node

var output: Array[String] = []
var result: Variant = null

func _custom_print(val: Variant) -> void:
	output.append(str(val))
	print(str(val))

func run() -> Variant:
	var scene := EditorInterface.get_edited_scene_root()
{user_code}
	return result
"""

	# 缩进用户代码
	var indented := ""
	for line in code.split("\n"):
		# 将代码中的 print 替换为代理输出函数
		var mod_line := line.replace("print(", "_custom_print(")
		indented += "\t" + mod_line + "\n"

	script.source_code = script_template.replace("{user_code}", indented)
	var err := script.reload()
	if err != OK:
		return RpcError.execution_error("Script compilation failed with error code: %d" % err)

	var runner := Node.new()
	runner.set_script(script)

	var scene_root := ctx.get_scene_root()
	if scene_root != null:
		scene_root.add_child(runner)
	else:
		var base_ctrl := ctx.get_base_control()
		if base_ctrl != null:
			base_ctrl.add_child(runner)

	var exec_result = runner.call("run")
	var captured_output: Array = runner.get("output")

	runner.get_parent().remove_child(runner)
	runner.queue_free()

	return {
		"output": captured_output,
		"result": exec_result
	}
