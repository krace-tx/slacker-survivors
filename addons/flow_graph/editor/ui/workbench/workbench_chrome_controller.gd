@tool
extends RefCounted

## 工作台外围壳层辅助器：窗口菜单、资源文件对话框、脚本跳转与外部文件系统防抖监听（Workbench Chrome Controller）。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)

const WIN_ID_FLOAT_WORKBENCH: int = 1
const WIN_ID_FLOAT_TOPMOST: int = 2
const WIN_ID_STANDALONE: int = 3
const WIN_ID_TOPMOST: int = 4

signal standalone_window_toggled(enabled: bool)
signal float_workbench_toggled(enabled: bool)
signal float_topmost_toggled(enabled: bool)
signal dialog_open_selected(path: String)
signal dialog_save_selected(path: String)
signal external_check_triggered(force_hash: bool)

var is_floating_window: bool = false
var float_topmost_enabled: bool = false
var standalone_enabled: bool = true
var topmost_enabled: bool = false

var _host_node: Node = null
var _window_menu_btn: MenuButton = null
var _file_dialog: EditorFileDialog = null
var _dialog_is_save_mode: bool = false
var _ext_check_queued: bool = false
var _ext_check_force_hash: bool = false


func setup(host_node: Node, window_menu_btn: MenuButton) -> void:
	_host_node = host_node
	_window_menu_btn = window_menu_btn
	if _window_menu_btn != null and _window_menu_btn.get_popup() != null:
		rebuild_window_menu_items()
		if not _window_menu_btn.get_popup().id_pressed.is_connected(on_window_menu_id_pressed):
			_window_menu_btn.get_popup().id_pressed.connect(on_window_menu_id_pressed)

	if Engine.is_editor_hint() and host_node != null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_refresh_dialog_filters()
		_file_dialog.file_selected.connect(_on_file_dialog_selected)
		host_node.add_child(_file_dialog)
	bind_filesystem_watcher()


func dispose() -> void:
	unbind_filesystem_watcher()
	_host_node = null


func apply_locale() -> void:
	_apply_workbench_controls_locale()
	rebuild_window_menu_items()
	_refresh_dialog_filters()


func _apply_workbench_controls_locale() -> void:
	if _host_node == null:
		return
	_set_btn_copy("%LangToggleBtn", &"lang.toggle_text", &"lang.toggle_tip")
	_set_ctrl_tip("%InstanceSelect", &"toolbar.session_tip")
	_set_btn_copy("%OpenResBtn", &"toolbar.open_res", &"toolbar.open_res_tip")
	_set_ctrl_tip("%SaveResBtn", &"toolbar.save_res_tip")
	_set_ctrl_tip("%UndoBtn", &"toolbar.undo_tip")
	_set_ctrl_tip("%RedoBtn", &"toolbar.redo_tip")
	_set_ctrl_tip("%PauseBtn", &"toolbar.pause_tip")
	_set_ctrl_tip("%StepBtn", &"toolbar.step_tip")
	_set_ctrl_tip("%DirToggleBtn", &"toolbar.dir_tip")
	_set_btn_copy("%AutoLayoutBtn", &"toolbar.layout", &"toolbar.layout_tip")
	_set_ctrl_tip("%SnapToggleBtn", &"toolbar.snap_tip")
	_set_ctrl_tip("%LabelsToggleBtn", &"toolbar.labels_tip")
	_set_ctrl_tip("%MinimapToggleBtn", &"toolbar.minimap_tip")
	_set_ctrl_tip("%WindowMenuBtn", &"toolbar.window_tip")
	_set_ctrl_tip("%ToggleSidebarBtn", &"toolbar.sidebar_tip")
	_set_ctrl_tip("%ZoomOutBtn", &"toolbar.zoom_out_tip")
	_set_ctrl_tip("%ZoomResetBtn", &"toolbar.zoom_reset_tip")
	_set_ctrl_tip("%ZoomInBtn", &"toolbar.zoom_in_tip")
	_set_ctrl_tip("%FitViewBtn", &"toolbar.fit_view_tip")
	_set_btn_copy("%TabTelemetryBtn", &"dock.tab_inspector", &"dock.tab_inspector_tip")
	_set_btn_copy("%TabResourcesBtn", &"dock.tab_resources", &"dock.tab_resources_tip")
	_set_btn_copy("%TabSourceBtn", &"dock.tab_source", &"dock.tab_source_tip")
	var code_ed: CodeEdit = _host_node.get_node_or_null("%CodeEditor") as CodeEdit
	if code_ed != null:
		code_ed.placeholder_text = FlowEditorI18n.t(&"dock.code_placeholder")


func _set_btn_copy(node_path: String, text_key: StringName, tip_key: StringName) -> void:
	var btn: Button = _host_node.get_node_or_null(node_path) as Button
	if btn != null:
		btn.text = FlowEditorI18n.t(text_key)
		btn.tooltip_text = FlowEditorI18n.t(tip_key)


func _set_ctrl_tip(node_path: String, tip_key: StringName) -> void:
	var ctrl: Control = _host_node.get_node_or_null(node_path) as Control
	if ctrl != null:
		ctrl.tooltip_text = FlowEditorI18n.t(tip_key)


func _refresh_dialog_filters() -> void:
	if _file_dialog != null:
		_file_dialog.clear_filters()
		_file_dialog.add_filter(FlowEditorI18n.t(&"window.dialog_filter"))


func rebuild_window_menu_items() -> void:
	if _window_menu_btn == null or _window_menu_btn.get_popup() == null:
		return
	var popup: PopupMenu = _window_menu_btn.get_popup()
	popup.clear()
	popup.add_item(FlowEditorI18n.t(&"window.dock_back") if is_floating_window else FlowEditorI18n.t(&"window.pop_out"), WIN_ID_FLOAT_WORKBENCH)
	popup.add_check_item(FlowEditorI18n.t(&"window.float_topmost"), WIN_ID_FLOAT_TOPMOST)
	var float_top_idx: int = popup.get_item_index(WIN_ID_FLOAT_TOPMOST)
	popup.set_item_checked(float_top_idx, float_topmost_enabled)
	popup.set_item_disabled(float_top_idx, not is_floating_window)
	popup.add_separator()
	popup.add_check_item(FlowEditorI18n.t(&"window.standalone_game"), WIN_ID_STANDALONE)
	popup.set_item_checked(popup.get_item_index(WIN_ID_STANDALONE), standalone_enabled)
	popup.add_check_item(FlowEditorI18n.t(&"window.game_topmost"), WIN_ID_TOPMOST)
	popup.set_item_checked(popup.get_item_index(WIN_ID_TOPMOST), topmost_enabled)


func on_window_menu_id_pressed(id: int, debugger: RefCounted = null) -> void:
	if _window_menu_btn == null or _window_menu_btn.get_popup() == null:
		return
	var popup: PopupMenu = _window_menu_btn.get_popup()
	var idx: int = popup.get_item_index(id)
	if idx < 0:
		return
	if id == WIN_ID_FLOAT_WORKBENCH:
		float_workbench_toggled.emit(not is_floating_window)
		return
	var next_checked: bool = not popup.is_item_checked(idx)
	popup.set_item_checked(idx, next_checked)
	if id == WIN_ID_FLOAT_TOPMOST:
		float_topmost_enabled = next_checked
		float_topmost_toggled.emit(next_checked)
	elif id == WIN_ID_STANDALONE:
		standalone_enabled = next_checked
		standalone_window_toggled.emit(next_checked)
	elif id == WIN_ID_TOPMOST:
		topmost_enabled = next_checked
		if debugger != null and debugger.is_game_running():
			debugger.set_game_window_topmost(next_checked)


func popup_open_dialog() -> void:
	if _file_dialog != null:
		_dialog_is_save_mode = false
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.title = FlowEditorI18n.t(&"window.dialog_open_title")
		_file_dialog.popup_file_dialog()


func popup_export_dialog(active_g: MermaidGraphModel) -> void:
	if _file_dialog == null or active_g == null:
		return
	_dialog_is_save_mode = true
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = FlowEditorI18n.t(&"window.dialog_export_title")
	var prefix: String = "def_fsm_" if active_g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM else "def_bt_"
	var base_title: String = active_g.title if not active_g.title.is_empty() and active_g.title != "mermaid_graph" else "blueprint"
	var clean_name: String = base_title.to_snake_case()
	_file_dialog.current_file = "%s.tres" % (clean_name if clean_name.begins_with("def_") else (prefix + clean_name))
	_file_dialog.popup_file_dialog()


func _on_file_dialog_selected(path: String) -> void:
	if _dialog_is_save_mode:
		dialog_save_selected.emit(path)
	else:
		dialog_open_selected.emit(path)


static func jump_to_script(file_path: String, line_num: int) -> void:
	if Engine.is_editor_hint() and not file_path.is_empty() and ResourceLoader.exists(file_path):
		var scr: Script = load(file_path) as Script
		if scr != null:
			EditorInterface.set_main_screen_editor("Script")
			EditorInterface.edit_script(scr, maxi(1, line_num), 0, true)


func bind_filesystem_watcher() -> void:
	if not Engine.is_editor_hint() or EditorInterface.get_resource_filesystem() == null:
		return
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if not efs.filesystem_changed.is_connected(_on_fs_changed):
		efs.filesystem_changed.connect(_on_fs_changed)
	if not efs.resources_reimported.is_connected(_on_res_reimported):
		efs.resources_reimported.connect(_on_res_reimported)


func unbind_filesystem_watcher() -> void:
	if not Engine.is_editor_hint() or EditorInterface.get_resource_filesystem() == null:
		return
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs.filesystem_changed.is_connected(_on_fs_changed):
		efs.filesystem_changed.disconnect(_on_fs_changed)
	if efs.resources_reimported.is_connected(_on_res_reimported):
		efs.resources_reimported.disconnect(_on_res_reimported)


func _on_fs_changed() -> void:
	queue_external_check(true)


func _on_res_reimported(_resources: PackedStringArray) -> void:
	queue_external_check(true)


func queue_external_check(force_hash: bool) -> void:
	if force_hash:
		_ext_check_force_hash = true
	if not _ext_check_queued:
		_ext_check_queued = true
		_flush_external_check.call_deferred()


func _flush_external_check() -> void:
	var force_h: bool = _ext_check_force_hash
	_ext_check_queued = false
	_ext_check_force_hash = false
	external_check_triggered.emit(force_h)
