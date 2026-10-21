@tool
extends EditorPlugin

## 场景契约注入器插件门面（Scene Define Generator Plugin Facade）。[br]
##
## 对齐 `addons/locate_in_filesystem` 的分层架构：
## - `plugin.gd`：顶层门面，负责组装 `core/` 服务与 `ui/` 底部栏面板、桥接 `EditorInterface` 与文件系统信号；
## - `core/`：无 UI 依赖的场景扫描器（`scene_scanner.gd`）与幂等代码生成服务（`define_service.gd`）；
## - `ui/`：底部栏交互面板视图（`define_bottom_panel.gd`）。

const DefineService = preload("core/define_service.gd")
const DefineBottomPanel = preload("ui/define_bottom_panel.gd")

const BOTTOM_PANEL_TITLE: String = "Scene Defines"
const DEBOUNCE_SEC: float = 0.30

#region State
var _service: DefineService = null
var _panel: DefineBottomPanel = null
var _debounce_timer: Timer = null
#endregion


#region Lifecycle
func _enter_tree() -> void:
	_service = DefineService.new()
	_panel = DefineBottomPanel.new()

	_panel.scan_requested.connect(_on_scan_requested)
	_panel.inject_requested.connect(_on_inject_requested)
	_panel.open_script_requested.connect(_on_open_script_requested)
	_panel.scene_activated.connect(_on_scene_activated)

	add_control_to_bottom_panel(_panel, BOTTOM_PANEL_TITLE)

	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = DEBOUNCE_SEC
	_debounce_timer.timeout.connect(_on_filesystem_debounced)
	add_child(_debounce_timer)

	var efs := EditorInterface.get_resource_filesystem()
	if efs != null and not efs.filesystem_changed.is_connected(_schedule_refresh):
		efs.filesystem_changed.connect(_schedule_refresh)


func _exit_tree() -> void:
	var efs := EditorInterface.get_resource_filesystem()
	if efs != null and efs.filesystem_changed.is_connected(_schedule_refresh):
		efs.filesystem_changed.disconnect(_schedule_refresh)

	if _debounce_timer != null:
		_debounce_timer.queue_free()
		_debounce_timer = null

	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null

	_service = null
#endregion


#region Signal Handlers & Coordination
func _on_scan_requested() -> void:
	if _service == null or _panel == null:
		return
	var snap := _service.preview()
	_panel.render_snapshot(snap)


func _on_inject_requested() -> void:
	if _service == null or _panel == null:
		return
	var res := _service.inject()
	if bool(res.get("changed", false)):
		var efs := EditorInterface.get_resource_filesystem()
		if efs != null:
			efs.scan()
	_panel.render_snapshot(_service.preview())
	_panel.show_inject_feedback(res)


func _on_open_script_requested() -> void:
	if _service == null:
		return
	if not FileAccess.file_exists(DefineService.OUTPUT_PATH):
		_on_inject_requested()
	var script_res := ResourceLoader.load(DefineService.OUTPUT_PATH) as Script
	if script_res != null:
		EditorInterface.edit_script(script_res)


func _on_scene_activated(scene_path: String) -> void:
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		return
	var fs_dock := EditorInterface.get_file_system_dock()
	if fs_dock != null:
		fs_dock.navigate_to_path(scene_path)
	EditorInterface.open_scene_from_path(scene_path)


func _schedule_refresh() -> void:
	if _debounce_timer != null and is_inside_tree():
		_debounce_timer.start(DEBOUNCE_SEC)


func _on_filesystem_debounced() -> void:
	if _panel == null or _service == null:
		return
	if _panel.is_auto_inject_enabled():
		_on_inject_requested()
	else:
		_on_scan_requested()
#endregion
