@tool
extends EditorPlugin

## Rev2D Godot 4 编辑器集成插件（挂载 `Project -> Tools` 快捷菜单并托管 `addons/rev2d/runtime/`）。[br]
##
## [b]提供能力：[/b][br]
## 1. [code]Rev2D: 打开可视化骨骼编辑器 (Web UI)[/code]：通过 `rev2d edit` 拉起本地 `127.0.0.1:4777` 实时骨骼编辑器并直接载入 `art/spines` 工作区；[br]
## 2. [code]Rev2D: 重新构建并导出 Spine 骨骼[/code]：一键运行 `art/spines/` 构建管线并刷新 Godot 资源文件系统。

const _TOOL_OPEN_WEB: String = "Rev2D: 打开可视化骨骼编辑器 (Web UI)"
const _TOOL_REBUILD_SPINE: String = "Rev2D: 重新构建并导出 Spine 骨骼"
const _WEB_EDITOR_URL: String = "http://127.0.0.1:4777"

var _web_server_pid: int = -1


func _enter_tree() -> void:
	add_tool_menu_item(_TOOL_OPEN_WEB, _on_open_web_editor)
	add_tool_menu_item(_TOOL_REBUILD_SPINE, _on_rebuild_spine_exports)


func _exit_tree() -> void:
	remove_tool_menu_item(_TOOL_OPEN_WEB)
	remove_tool_menu_item(_TOOL_REBUILD_SPINE)
	if _web_server_pid > 0 and OS.is_process_running(_web_server_pid):
		OS.kill(_web_server_pid)
		_web_server_pid = -1


func _on_open_web_editor() -> void:
	var node_bin: String = _resolve_binary(["/opt/homebrew/bin/node", "/usr/local/bin/node", "node"])
	var rev2d_cli: String = ProjectSettings.globalize_path("res://addons/rev2d/runtime/bin/rev2d.js")
	var spines_root: String = ProjectSettings.globalize_path("res://art/spines")
	var default_model: String = ProjectSettings.globalize_path("res://art/spines/spine_stage/hero_knight.r2d.json")

	if _web_server_pid > 0 and OS.is_process_running(_web_server_pid):
		OS.shell_open(_WEB_EDITOR_URL)
		return

	var args := PackedStringArray([rev2d_cli, "edit"])
	if FileAccess.file_exists(default_model):
		args.append(default_model)
	if DirAccess.dir_exists_absolute(spines_root):
		args.append_array(["--root", spines_root])
	args.append_array(["--port", "4777"])
	_web_server_pid = OS.create_process(node_bin, args)


func _on_rebuild_spine_exports() -> void:
	var node_bin: String = _resolve_binary(["/opt/homebrew/bin/node", "/usr/local/bin/node", "node"])
	var build_script: String = ProjectSettings.globalize_path("res://art/spines/spine_stage/build_spine_exports.mjs")
	if not FileAccess.file_exists(build_script):
		push_warning("[Rev2D] Build script not found: %s" % build_script)
		return

	var output: Array = []
	var exit_code: int = OS.execute(node_bin, PackedStringArray([build_script]), output, true)
	if exit_code != 0:
		push_error("[Rev2D] Spine export failed (code %d): %s" % [exit_code, "\n".join(PackedStringArray(output))])
		return

	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()


func _resolve_binary(candidates: Array[String]) -> String:
	for candidate: String in candidates:
		if candidate.begins_with("/") and FileAccess.file_exists(candidate):
			return candidate
	return candidates[candidates.size() - 1]
