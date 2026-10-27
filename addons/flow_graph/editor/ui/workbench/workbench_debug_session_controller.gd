@tool
extends RefCounted

## 工作台运行期调试、60 帧时间轴回放与 IPC 指令控制器（Workbench Debug & Replay Session Controller）。[br]
##
## 负责绑定 [`MermaidEditorDebugger`](../../debugger/mermaid_editor_debugger.gd)，处理运行期实例注册/注销、实时遥测帧下发、历史回放自动暂停、断点同步、黑板热改（`set_var`）、事件注入（`fire_event`）及 `.tres` 热重载广播。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const MermaidGraphCanvas = preload(FlowGraphContracts.SCRIPT_CANVAS)
const MermaidInspectorPanel = preload(FlowGraphContracts.SCRIPT_INSPECTOR_PANEL)
const WorkbenchNavScrubberBar = preload(FlowGraphContracts.SCRIPT_WB_NAV_BAR)

const IconPause: Texture2D = FlowGraphIcons.STATUS_PAUSE
const IconPlay: Texture2D = FlowGraphIcons.STATUS_PLAY

signal render_requested(fit_view: bool)
signal dropdown_rebuild_requested()
signal dock_tab_switch_requested(tab_id: int)

var debugger: RefCounted = null
var _store: MermaidSessionStore = null
var _canvas: MermaidGraphCanvas = null
var _inspector: MermaidInspectorPanel = null
var _nav_bar: WorkbenchNavScrubberBar = null
var _pause_btn: Button = null


func setup(
	store: MermaidSessionStore,
	canvas: MermaidGraphCanvas,
	inspector: MermaidInspectorPanel,
	nav_bar: WorkbenchNavScrubberBar,
	pause_btn: Button
) -> void:
	_store = store
	_canvas = canvas
	_inspector = inspector
	_nav_bar = nav_bar
	_pause_btn = pause_btn


func bind_debugger(debugger_plugin: RefCounted, on_session_changed: Callable = Callable()) -> void:
	debugger = debugger_plugin
	if debugger == null:
		return
	if on_session_changed.is_valid():
		debugger.session_active_changed.connect(on_session_changed)
	else:
		debugger.session_active_changed.connect(func(on: bool) -> void: on_session_active_changed(on, false, 0))
	debugger.instance_registered.connect(on_instance_registered)
	debugger.instance_unregistered.connect(on_instance_unregistered)
	debugger.topology_received.connect(on_topology_received)
	debugger.frame_received.connect(on_frame_received)
	debugger.edge_flow_received.connect(on_edge_flow_received)


func update_pause_btn_visual(is_paused: bool) -> void:
	if _pause_btn != null:
		_pause_btn.text = FlowEditorI18n.t(&"toolbar.resume") if is_paused else FlowEditorI18n.t(&"toolbar.pause")
		_pause_btn.icon = IconPlay if is_paused else IconPause


func notify_hot_reload_if_running(saved_path: String) -> void:
	if saved_path.is_empty() or debugger == null or not debugger.is_game_running() or _store == null:
		return
	var active_g: MermaidGraphModel = _store.get_active_graph()
	if active_g != null:
		debugger.send_hot_reload_resource(saved_path, active_g.to_topology_dict())


func sync_breakpoint(memory_id: int, node_id: String, enabled: bool) -> void:
	if debugger != null and memory_id != 0:
		debugger.send_instance_command(memory_id, &"set_breakpoint", {"node_id": node_id, "enabled": enabled})


func on_scrub_index_changed(idx: int) -> void:
	if _store == null:
		return
	_store.set_scrub_index(idx)
	if idx >= 0 and _store.is_live_selected():
		var raw_f: Dictionary = _store.get_active_record().get("frame", {}) as Dictionary
		if not bool(raw_f.get("paused", false)):
			raw_f["paused"] = true
			if _pause_btn != null:
				_pause_btn.set_pressed_no_signal(true)
			update_pause_btn_visual(true)
			if debugger != null:
				debugger.send_instance_command(_store.get_selected_live_memory_id(), &"set_pause", {"paused": true})
	var disp_frame: Dictionary = _store.get_active_display_frame()
	if _canvas != null:
		_canvas.apply_frame_telemetry(disp_frame)
	if _inspector != null:
		_inspector.refresh_live_telemetry(_store, disp_frame)
	if _nav_bar != null:
		_nav_bar.sync_state(_store)


func on_session_active_changed(is_active: bool, topmost_enabled: bool, current_dock_tab: int) -> void:
	if not is_active:
		_store.archive_live_sessions_to_snapshots()
		dropdown_rebuild_requested.emit()
		if (_store.is_snapshot_selected() or _store.is_resource_selected()) and current_dock_tab == 2:
			dock_tab_switch_requested.emit(0)
		render_requested.emit(false)
	elif topmost_enabled and debugger != null:
		debugger.set_game_window_topmost(true)


func on_instance_registered(memory_id: int, descriptor: Dictionary, topology: Dictionary, frame: Dictionary) -> void:
	var auto_switched: bool = _store.register_live_instance(memory_id, descriptor, topology, frame)
	if debugger != null and _store.breakpoints_by_key.has(str(memory_id)):
		for bp_id: String in (_store.breakpoints_by_key[str(memory_id)] as Array[String]):
			debugger.send_instance_command(memory_id, &"set_breakpoint", {"node_id": bp_id, "enabled": true})
	if auto_switched:
		dock_tab_switch_requested.emit(0)
	dropdown_rebuild_requested.emit()
	if auto_switched or _store.get_selected_live_memory_id() == memory_id:
		render_requested.emit(true)


func on_instance_unregistered(memory_id: int) -> void:
	var changed: bool = _store.unregister_live_instance(memory_id)
	dropdown_rebuild_requested.emit()
	if changed:
		dock_tab_switch_requested.emit(0 if (_store.is_live_selected() or _store.is_snapshot_selected() or _store.is_resource_selected()) else 2)
		render_requested.emit(false)


func on_topology_received(memory_id: int, topology: Dictionary) -> void:
	if _store.update_live_topology(memory_id, topology):
		render_requested.emit(false)


func on_frame_received(memory_id: int, frame: Dictionary) -> void:
	if _store.update_live_frame(memory_id, frame) and _canvas != null:
		var is_paused: bool = bool(frame.get("paused", false))
		if _pause_btn != null and _pause_btn.button_pressed != is_paused:
			_pause_btn.set_pressed_no_signal(is_paused)
			update_pause_btn_visual(is_paused)
		if _nav_bar != null:
			_nav_bar.sync_state(_store)
		if not _store.is_scrubbing():
			_canvas.apply_frame_telemetry(frame)
			if _inspector != null:
				_inspector.refresh_live_telemetry(_store, frame)


func on_edge_flow_received(memory_id: int, from_id: String, to_id: String, _label: String) -> void:
	if _store.get_selected_live_memory_id() == memory_id and _canvas != null and not _store.is_scrubbing():
		_canvas.trigger_edge_pulse(from_id, to_id)


func send_pause(paused: bool) -> void:
	var mid: int = _store.get_selected_live_memory_id()
	if debugger != null and mid != 0:
		update_pause_btn_visual(paused)
		debugger.send_instance_command(mid, &"set_pause", {"paused": paused})


func send_step() -> void:
	var mid: int = _store.get_selected_live_memory_id()
	if debugger != null and mid != 0:
		if _pause_btn != null:
			_pause_btn.set_pressed_no_signal(true)
		update_pause_btn_visual(true)
		debugger.send_instance_command(mid, &"step_once", {})


func send_force_node(node_id: String, params: Dictionary) -> void:
	var mid: int = _store.get_selected_live_memory_id()
	if debugger != null and mid != 0:
		var payload: Dictionary = {"node_id": node_id}
		if params.has("action_key"):
			payload["action_key"] = str(params["action_key"])
		debugger.send_instance_command(mid, &"force_node", payload)


func send_set_var(var_key: String, raw_value: Variant, type_hint: String) -> void:
	var mid: int = _store.get_selected_live_memory_id()
	if debugger != null and mid != 0 and not var_key.is_empty():
		debugger.send_instance_command(mid, &"set_var", {"key": var_key, "value": raw_value, "type": type_hint})


func send_fire_event(event_name: String) -> void:
	var mid: int = _store.get_selected_live_memory_id()
	if debugger != null and mid != 0 and not event_name.is_empty():
		debugger.send_instance_command(mid, &"fire_event", {"event": event_name, "payload": {}})
