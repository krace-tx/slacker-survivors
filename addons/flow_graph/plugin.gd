@tool
extends EditorPlugin

## FlowGraph 顶部主视口大画布插件门面（Main Screen & Resource Blueprint Plugin Facade）。[br]
##
## [b]核心设计：[/b][br]
## 1. 挂载于 Godot 编辑器顶部主视口栏（`2D / 3D / Script / Game / FlowGraph`），支持一键提取为独立系统窗口 <-> 无损嵌回主视口；[br]
## 2. 通过 `_handles` / `_edit` 协议嗅探（`to_flow_graph_ir` / `to_mermaid_ir`），双击任意 `FsmGraphDef` / `BTGraphDef` `.tres` 资源即自动在 FlowGraph 画布打开编辑；[br]
## 3. 联动 `GraphDebugBridge` 的后台失焦保活，实现运行期实时流转监控与停止后离线快照定格。

const WorkbenchScene: PackedScene = preload(FlowGraphContracts.SCENE_WORKBENCH)
const MermaidWorkbench = preload(FlowGraphContracts.SCRIPT_WORKBENCH)
const MermaidFloatingHost = preload(FlowGraphContracts.SCRIPT_FLOATING_HOST)
const MermaidEditorDebugger = preload(FlowGraphContracts.SCRIPT_EDITOR_DEBUGGER)
const MermaidResourceBridge = preload(FlowGraphContracts.SCRIPT_RESOURCE_BRIDGE)

const SETTING_GAME_EMBED_MODE: String = FlowGraphContracts.SETTING_GAME_EMBED_MODE

#region 私有字段

var _workbench: MermaidWorkbench = null
var _floating_host: MermaidFloatingHost = null
var _debugger: MermaidEditorDebugger = null
var _prev_embed_mode: int = 0
var _had_embed_setting: bool = false

#endregion


#region EditorPlugin 主视口与资源接管生命周期

func _enter_tree() -> void:
	_debugger = MermaidEditorDebugger.new()
	add_debugger_plugin(_debugger)

	_workbench = WorkbenchScene.instantiate() as MermaidWorkbench
	var main_screen: Control = EditorInterface.get_editor_main_screen()
	var base_ctrl: Control = EditorInterface.get_base_control()

	_floating_host = MermaidFloatingHost.new()
	_floating_host.setup(main_screen, base_ctrl, _workbench)

	_workbench.bind_debugger(_debugger)
	_workbench.standalone_window_toggled.connect(_apply_standalone_game_window_mode)

	var ed_settings: EditorSettings = EditorInterface.get_editor_settings()
	if ed_settings != null and not ed_settings.settings_changed.is_connected(_on_editor_settings_changed):
		ed_settings.settings_changed.connect(_on_editor_settings_changed)

	_cache_and_enable_standalone_window()
	call_deferred(&"_sync_main_screen_button_icon")


func _exit_tree() -> void:
	var ed_settings: EditorSettings = EditorInterface.get_editor_settings()
	if ed_settings != null and ed_settings.settings_changed.is_connected(_on_editor_settings_changed):
		ed_settings.settings_changed.disconnect(_on_editor_settings_changed)

	_restore_embed_mode_if_needed()

	if _floating_host != null:
		_floating_host.dispose()
		_floating_host = null

	if _debugger != null:
		remove_debugger_plugin(_debugger)
		_debugger = null

	if _workbench != null:
		_workbench.queue_free()
		_workbench = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "FlowGraph"


func _get_plugin_icon() -> Texture2D:
	return FlowGraphIcons.create_main_screen_icon()


func _make_visible(visible: bool) -> void:
	if _floating_host != null:
		_floating_host.on_main_screen_visibility_changed(visible)
	elif _workbench != null:
		_workbench.visible = visible


func _handles(object: Object) -> bool:
	return MermaidResourceBridge.is_supported_resource(object)


func _edit(object: Object) -> void:
	if object == null or _workbench == null:
		return
	if MermaidResourceBridge.is_supported_resource(object):
		_workbench.open_resource(object as Resource)

#endregion


#region 独立游戏窗口策略（防内嵌遮挡）

func _cache_and_enable_standalone_window() -> void:
	var ed_settings: EditorSettings = EditorInterface.get_editor_settings()
	if ed_settings == null or not ed_settings.has_setting(SETTING_GAME_EMBED_MODE):
		return
	_had_embed_setting = true
	_prev_embed_mode = int(ed_settings.get_setting(SETTING_GAME_EMBED_MODE))
	if _prev_embed_mode != -1:
		ed_settings.set_setting(SETTING_GAME_EMBED_MODE, -1)
	if _workbench != null:
		_workbench.set_standalone_check_state(true)


func _apply_standalone_game_window_mode(standalone_enabled: bool) -> void:
	var ed_settings: EditorSettings = EditorInterface.get_editor_settings()
	if ed_settings == null or not ed_settings.has_setting(SETTING_GAME_EMBED_MODE):
		return
	ed_settings.set_setting(SETTING_GAME_EMBED_MODE, -1 if standalone_enabled else 1)


func _restore_embed_mode_if_needed() -> void:
	if not _had_embed_setting:
		return
	var ed_settings: EditorSettings = EditorInterface.get_editor_settings()
	if ed_settings != null and ed_settings.has_setting(SETTING_GAME_EMBED_MODE):
		ed_settings.set_setting(SETTING_GAME_EMBED_MODE, _prev_embed_mode)


func _on_editor_settings_changed() -> void:
	_sync_main_screen_button_icon()


func _sync_main_screen_button_icon() -> void:
	FlowGraphIcons.sync_editor_main_screen_button(_get_plugin_name())

#endregion
