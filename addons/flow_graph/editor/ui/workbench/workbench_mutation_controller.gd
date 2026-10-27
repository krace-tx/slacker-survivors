@tool
extends RefCounted

## 工作台图拓扑变更与撤销重做控制器（Workbench Graph Mutation & Undo Controller）。[br]
##
## 统一承接来自画布右键/拖拽、检视器原位表单与源码编辑器的全部图编辑命令，自动维护 [`FlowUndoStack`](../../command/flow_undo_stack.gd) 快照、重算布局路由、同步 `.tres` 脏状态并通知工作台刷新。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const FlowUndoStack = preload(FlowGraphContracts.SCRIPT_UNDO_STACK)
const MermaidGraphCanvas = preload(FlowGraphContracts.SCRIPT_CANVAS)
const MermaidInspectorPanel = preload(FlowGraphContracts.SCRIPT_INSPECTOR_PANEL)

signal view_sync_requested(full_rerender: bool, fit_view: bool, focus_node_id: String)
signal parse_hint_changed(err_msg: String)
signal breakpoint_changed(memory_id: int, node_id: String, enabled: bool)

var _store: MermaidSessionStore = null
var _undo_stack: FlowUndoStack = null
var _canvas: MermaidGraphCanvas = null
var _inspector: MermaidInspectorPanel = null


#region 依赖注入、双向信号接线与 Undo/Redo

func setup(store: MermaidSessionStore, undo_stack: FlowUndoStack, canvas: MermaidGraphCanvas, inspector: MermaidInspectorPanel) -> void:
	_store = store
	_undo_stack = undo_stack
	_canvas = canvas
	_inspector = inspector
	if _canvas != null:
		_canvas.before_graph_mutation.connect(record_before_edit)
		_canvas.graph_mutated.connect(_on_canvas_positions_mutated)
		_canvas.edge_connection_added.connect(add_edge)
		_canvas.edge_connection_removed.connect(remove_edge)
		_canvas.node_added_at.connect(add_node_at)
		_canvas.node_deleted_requested.connect(delete_node)
		_canvas.node_duplicated_requested.connect(duplicate_node)
		_canvas.initial_node_set_requested.connect(set_initial_node)
		_canvas.any_state_edge_toggled.connect(toggle_any_state_edge)
		_canvas.breakpoint_toggled.connect(toggle_breakpoint)
		_canvas.undo_requested.connect(undo)
		_canvas.redo_requested.connect(redo)
		_canvas.direction_toggle_requested.connect(toggle_direction)
		_canvas.auto_layout_requested.connect(auto_layout)
	if _inspector != null:
		_inspector.node_edit_committed.connect(edit_node)
		_inspector.node_rename_committed.connect(rename_node)
		_inspector.edge_edit_committed.connect(edit_edge)
		_inspector.edge_delete_committed.connect(remove_edge)
		_inspector.schema_edited.connect(edit_schema)
		_inspector.breakpoint_toggle_requested.connect(toggle_breakpoint)

func record_before_edit() -> void:
	if _store == null or _undo_stack == null or not _store.is_editable_mode():
		return
	var g: MermaidGraphModel = _store.get_active_graph()
	if g != null:
		if _canvas != null and not g.nodes.is_empty():
			_canvas.sync_positions_to_model(g)
		_undo_stack.record_before_edit(_store.get_session_undo_key(), g)

func can_undo() -> bool:
	return _store != null and _undo_stack != null and _store.is_editable_mode() and _undo_stack.can_undo(_store.get_session_undo_key())

func can_redo() -> bool:
	return _store != null and _undo_stack != null and _store.is_editable_mode() and _undo_stack.can_redo(_store.get_session_undo_key())

func undo() -> bool:
	if not can_undo():
		return false
	var g: MermaidGraphModel = _store.get_active_graph()
	if _canvas != null:
		_canvas.sync_positions_to_model(g)
	if not _undo_stack.undo_graph(_store.get_session_undo_key(), g):
		return false
	_commit_mutation(true, _current_focus_id())
	return true

func redo() -> bool:
	if not can_redo():
		return false
	var g: MermaidGraphModel = _store.get_active_graph()
	if _canvas != null:
		_canvas.sync_positions_to_model(g)
	if not _undo_stack.redo_graph(_store.get_session_undo_key(), g):
		return false
	_commit_mutation(true, _current_focus_id())
	return true

#endregion


#region 画布与检视器原位图编辑动作

func add_node_at(kind: String, world_pos: Vector2) -> String:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return ""
	record_before_edit()
	var clean_kind: String = kind.strip_edges() if not kind.strip_edges().is_empty() else "State"
	if g.nodes.is_empty() and g.schema == MermaidGraphModel.SCHEMA_GENERIC:
		g.diagram_type = MermaidGraphModel.TYPE_STATE_V2 if clean_kind == "State" else MermaidGraphModel.TYPE_FLOWCHART
		g.schema = MermaidGraphModel.SCHEMA_FSM if clean_kind == "State" else MermaidGraphModel.SCHEMA_BT
	var is_fsm: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM)
	var new_id: String = g.generate_unique_node_id("state_" if is_fsm else "n")
	g.ensure_node(
		new_id, new_id if is_fsm else clean_kind,
		MermaidGraphModel.default_shape_for_kind(clean_kind), clean_kind,
		world_pos, true, _default_params_for_kind(clean_kind, new_id)
	)
	if g.initial_node_id.is_empty() and g.nodes.size() == 1:
		g.initial_node_id = new_id
	_commit_mutation(true, new_id)
	return new_id

func delete_node(node_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or node_id.strip_edges().is_empty() or g.find_node(node_id).is_empty():
		return
	record_before_edit()
	if g.remove_node(node_id):
		_commit_mutation(true, "" if _current_focus_id() == node_id else _current_focus_id())

func duplicate_node(node_id: String) -> String:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or node_id.strip_edges().is_empty() or g.find_node(node_id).is_empty():
		return ""
	record_before_edit()
	var new_id: String = g.duplicate_node(node_id)
	if not new_id.is_empty():
		_commit_mutation(true, new_id)
	return new_id

func set_initial_node(node_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or g.find_node(node_id).is_empty() or g.initial_node_id == node_id:
		return
	record_before_edit()
	g.initial_node_id = node_id
	_commit_mutation(true, node_id)

func toggle_any_state_edge(node_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or node_id.strip_edges().is_empty() or g.find_node(node_id).is_empty():
		return
	record_before_edit()
	if not g.find_edge("*", node_id).is_empty():
		g.remove_edge("*", node_id)
	else:
		g.add_edge("*", node_id, "")
	_commit_mutation(true, node_id)

func edit_node(node_id: String, patch: Dictionary) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or patch.is_empty() or g.find_node(node_id).is_empty():
		return
	record_before_edit()
	if g.update_node_fields(node_id, patch):
		_commit_mutation(true, node_id)

func rename_node(old_id: String, new_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return
	if _canvas != null and not g.nodes.is_empty():
		_canvas.sync_positions_to_model(g)
	var pre_snap: Dictionary = g.to_snapshot_dict()
	if g.rename_node(old_id, new_id):
		if _undo_stack != null:
			_undo_stack.push_snapshot(_store.get_session_undo_key(), pre_snap)
		_commit_mutation(true, new_id.strip_edges())

func add_edge(from_id: String, to_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return
	record_before_edit()
	g.add_edge(from_id, to_id, "")
	_store.refresh_editable_topology_plan()
	if _canvas != null:
		_canvas.sync_edge_defs_from_model(g)
	view_sync_requested.emit(false, false, _current_focus_id())

func remove_edge(from_id: String, to_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or g.find_edge(from_id, to_id).is_empty():
		return
	record_before_edit()
	g.remove_edge(from_id, to_id)
	_store.refresh_editable_topology_plan()
	if _canvas != null:
		_canvas.sync_edge_defs_from_model(g)
	view_sync_requested.emit(false, false, _current_focus_id())

func edit_edge(from_id: String, to_id: String, patch: Dictionary) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or patch.is_empty() or g.find_edge(from_id, to_id).is_empty():
		return
	record_before_edit()
	if g.update_edge_fields(from_id, to_id, patch):
		_commit_mutation(true, _current_focus_id())

func edit_schema(new_schema: Array[Dictionary]) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return
	record_before_edit()
	g.blackboard_schema = new_schema.duplicate(true)
	_commit_mutation(false, _current_focus_id())

func apply_code_text(source: String) -> bool:
	var prev_g: MermaidGraphModel = _editable_graph_or_null()
	if prev_g == null:
		return false
	var prev_snap: Dictionary = prev_g.to_snapshot_dict()
	var res: Dictionary = _store.apply_source_to_active(source, false)
	if not bool(res.get("ok", false)):
		parse_hint_changed.emit(FlowEditorI18n.t(&"dock.syntax_hint", [str(res.get("error", ""))]))
		return false
	if _undo_stack != null and not prev_snap.is_empty():
		_undo_stack.push_snapshot(_store.get_session_undo_key(), prev_snap)
	parse_hint_changed.emit("")
	view_sync_requested.emit(true, false, _current_focus_id())
	return true

func toggle_direction() -> void:
	if _store == null:
		return
	if _store.is_editable_mode():
		record_before_edit()
	_store.relayout_active(true)
	view_sync_requested.emit(true, true, _current_focus_id())

func auto_layout() -> void:
	if _store == null or _store.get_active_graph() == null or _store.get_active_graph().nodes.is_empty():
		return
	if _store.is_editable_mode():
		record_before_edit()
	_store.relayout_active(false)
	view_sync_requested.emit(true, true, _current_focus_id())

func toggle_breakpoint(node_id: String) -> void:
	if _store == null or node_id.strip_edges().is_empty():
		return
	var next_on: bool = _store.toggle_breakpoint(node_id)
	if _canvas != null:
		_canvas.set_breakpoints(_store.get_active_breakpoints())
	breakpoint_changed.emit(_store.get_selected_live_memory_id(), node_id.strip_edges(), next_on)
	view_sync_requested.emit(false, false, _current_focus_id())

#endregion


#region 内部辅助方法

func _editable_graph_or_null() -> MermaidGraphModel:
	return _store.get_active_graph() if (_store != null and not _store.is_read_only_topology()) else null

func _on_canvas_positions_mutated() -> void:
	if _store == null or _store.get_active_graph() == null:
		return
	if _canvas != null:
		_canvas.sync_positions_to_model(_store.get_active_graph())
	if _store.is_resource_selected():
		_store.sync_active_resource_mutation()
	view_sync_requested.emit(false, false, _current_focus_id())

func _commit_mutation(full_rerender: bool, focus_node_id: String) -> void:
	_store.refresh_editable_topology_plan()
	parse_hint_changed.emit("")
	view_sync_requested.emit(full_rerender, false, focus_node_id)

func _current_focus_id() -> String:
	return _canvas.get_selected_node_id() if _canvas != null else ""

static func _default_params_for_kind(kind: String, new_id: String) -> Dictionary:
	match kind:
		"Action": return {"action_key": new_id}
		"Cooldown": return {"cooldown_sec": 1.0, "jitter_sec": 0.0}
		"Wait": return {"duration_sec": 0.5, "jitter_sec": 0.0}
		"Repeater": return {"repeat_count": 3, "abort_on_failure": true}
		"TimeLimit": return {"timeout_sec": 3.0}
		"Service": return {"service_key": "", "interval_sec": 0.25, "jitter_sec": 0.05}
		_: return {}

#endregion
