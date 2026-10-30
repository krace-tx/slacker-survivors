@tool
extends RefCounted

## 工作台图拓扑变更与撤销重做控制器（Workbench Graph Mutation & Undo Controller）。[br]
##
## 统一承接来自画布（智能落位建点、拉线空投建点连线、边中间插点、边反转、原位改名、拖拽）与检视器表单的全部图编辑命令，维护 [`FlowUndoStack`](../../command/flow_undo_stack.gd) 原子快照。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const FlowUndoStack = preload(FlowGraphContracts.SCRIPT_UNDO_STACK)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const MermaidGraphCanvas = preload(FlowGraphContracts.SCRIPT_CANVAS)
const MermaidInspectorPanel = preload(FlowGraphContracts.SCRIPT_INSPECTOR_PANEL)

const BT_DECORATOR_KINDS: PackedStringArray = [
	"Decorator", "Inverter", "Cooldown", "Repeat", "Repeater",
	"TimeLimit", "Timeout", "Limiter", "ForceSuccess", "ForceFailure",
	"AlwaysSucceed", "AlwaysFail", "Service",
]
const BT_SINGLE_CHILD_KINDS: PackedStringArray = [
	"Root", "Decorator", "Inverter", "Cooldown", "Repeat", "Repeater",
	"TimeLimit", "Timeout", "Limiter", "ForceSuccess", "ForceFailure",
	"AlwaysSucceed", "AlwaysFail", "Service",
]

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
		_canvas.edge_reversed_requested.connect(reverse_edge)
		_canvas.node_added_at.connect(add_node_at)
		_canvas.node_added_and_connected.connect(add_node_and_connect)
		_canvas.node_inserted_on_edge.connect(insert_node_on_edge)
		_canvas.palette_item_dropped.connect(handle_palette_drop)
		_canvas.node_title_edited_inline.connect(func(nid: String, nt: String) -> void: edit_node(nid, {"title": nt}))
		_canvas.node_deleted_requested.connect(delete_node)
		_canvas.node_duplicated_requested.connect(duplicate_node)
		_canvas.nodes_deleted_requested.connect(delete_nodes)
		_canvas.nodes_duplicated_requested.connect(duplicate_nodes)
		_canvas.initial_node_set_requested.connect(set_initial_node)
		_canvas.any_state_edge_toggled.connect(toggle_any_state_edge)
		_canvas.breakpoint_toggled.connect(toggle_breakpoint)
		_canvas.breakpoints_toggled_requested.connect(toggle_breakpoints)
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
	return _store != null and _undo_stack != null and _store.is_editable_mode() and _store.get_session_undo_key() != "" and _undo_stack.can_redo(_store.get_session_undo_key())

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


#region 画布智能建点、拉线空投连线、中间插点与检视器编辑动作

func add_node_at(kind: String, world_pos: Vector2) -> String:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return ""
	if kind.strip_edges() == MermaidGraphModel.BT_ROOT_KIND:
		var existing_root: String = g.find_bt_root_id()
		if not existing_root.is_empty():
			view_sync_requested.emit(false, false, existing_root)
			return existing_root
	record_before_edit()
	var new_id: String = _spawn_node_internal(g, kind, world_pos, false)
	_commit_mutation(true, new_id)
	return new_id


func add_node_and_connect(from_id: String, kind: String, world_pos: Vector2) -> String:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or from_id.strip_edges().is_empty() or g.find_node(from_id).is_empty():
		return ""
	var is_bt: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT)
	var src_kind: String = str(g.find_node(from_id).get("kind", "State"))
	var clean_target_kind: String = kind.split(":", false, 1)[0].strip_edges() if kind.contains(":") else kind.strip_edges()
	if not CanvasGeometry.can_node_emit_edge(src_kind, is_bt) or not CanvasGeometry.can_node_accept_edge(clean_target_kind, is_bt):
		return ""
	record_before_edit()
	var new_id: String = _spawn_node_internal(g, kind, world_pos, true)
	_connect_edge_with_schema_rules(g, from_id, new_id)
	_commit_mutation(true, new_id)
	return new_id


func insert_node_on_edge(from_id: String, to_id: String, kind: String, world_pos: Vector2) -> String:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return ""
	var orig_ed: Dictionary = g.find_edge(from_id, to_id)
	if orig_ed.is_empty():
		return ""
	var is_bt: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT)
	var raw_k: String = kind.strip_edges() if not kind.strip_edges().is_empty() else "State"
	var base_k: String = raw_k.split(":", false, 1)[0] if raw_k.contains(":") else raw_k
	if not CanvasGeometry.can_node_emit_edge(base_k, is_bt) or not CanvasGeometry.can_node_accept_edge(base_k, is_bt):
		return ""

	record_before_edit()
	var orig_lbl: String = str(orig_ed.get("label", ""))
	var orig_prio: int = int(orig_ed.get("priority", 0))
	var orig_params: Dictionary = (orig_ed.get("params", {}) as Dictionary).duplicate(true)

	g.remove_edge(from_id, to_id)
	var new_id: String = _spawn_node_internal(g, raw_k, world_pos, false)
	g.add_edge(from_id, new_id, orig_lbl, orig_prio, false, orig_params)
	g.add_edge(new_id, to_id, "")
	if is_bt:
		g.reorder_bt_children_by_position(g.direction == &"TD" or g.direction == &"TB")
	_commit_mutation(true, new_id)
	return new_id


func handle_palette_drop(
	kind: String,
	preset: String,
	world_pos: Vector2,
	target_node_id: String,
	split_from_id: String,
	split_to_id: String
) -> String:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return ""
	if kind.strip_edges() == MermaidGraphModel.BT_ROOT_KIND:
		var existing_root: String = g.find_bt_root_id()
		if not existing_root.is_empty():
			view_sync_requested.emit(false, false, existing_root)
			return existing_root
		record_before_edit()
		var root_id: String = _spawn_node_internal(g, kind, world_pos, false, preset)
		if not target_node_id.is_empty() and target_node_id != root_id and not g.find_node(target_node_id).is_empty():
			_connect_edge_with_schema_rules(g, root_id, target_node_id)
		_commit_mutation(true, root_id)
		return root_id

	if not split_from_id.is_empty() and not split_to_id.is_empty() and preset != "interrupt":
		var split_id: String = insert_node_on_edge(split_from_id, split_to_id, kind, world_pos)
		if not split_id.is_empty() and preset == "subgraph":
			g.update_node_fields(split_id, {"title": FlowEditorI18n.t(&"drawer.init_submachine_title"), "params_patch": {"submachine": true}})
			_commit_mutation(true, split_id)
		return split_id

	if not target_node_id.is_empty() and preset != "interrupt" and not g.find_node(target_node_id).is_empty():
		var is_bt: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT)
		var src_kind: String = str(g.find_node(target_node_id).get("kind", "State"))
		if CanvasGeometry.can_node_emit_edge(src_kind, is_bt):
			record_before_edit()
			var down_pos: Vector2 = _compute_downstream_world_pos(g, target_node_id)
			var conn_id: String = _spawn_node_internal(g, kind, down_pos, true, preset)
			_connect_edge_with_schema_rules(g, target_node_id, conn_id)
			_commit_mutation(true, conn_id)
			return conn_id

	record_before_edit()
	var standalone_id: String = _spawn_node_internal(g, kind, world_pos, false, preset)
	_commit_mutation(true, standalone_id)
	return standalone_id


func add_node_from_drawer(kind: String, preset: String = "") -> String:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return ""
	if kind.strip_edges() == MermaidGraphModel.BT_ROOT_KIND:
		var existing_root: String = g.find_bt_root_id()
		if not existing_root.is_empty():
			view_sync_requested.emit(false, false, existing_root)
			return existing_root
		record_before_edit()
		var center_root_w: Vector2 = _canvas.get_viewport_center_world() if _canvas != null else Vector2(220.0, 160.0)
		var spawned_root: String = _spawn_node_internal(g, kind, center_root_w, false, preset)
		_commit_mutation(true, spawned_root)
		return spawned_root

	var parent_id: String = _resolve_drawer_auto_parent(g, preset)
	record_before_edit()
	if not parent_id.is_empty():
		var down_pos: Vector2 = _compute_downstream_world_pos(g, parent_id)
		var new_id: String = _spawn_node_internal(g, kind, down_pos, true, preset)
		_connect_edge_with_schema_rules(g, parent_id, new_id)
		_commit_mutation(true, new_id)
		return new_id

	var center_w: Vector2 = _canvas.get_viewport_center_world() if _canvas != null else Vector2(220.0, 160.0)
	var root_id: String = _spawn_node_internal(g, kind, center_w, false, preset)
	_commit_mutation(true, root_id)
	return root_id


func delete_node(node_id: String) -> void:
	delete_nodes([node_id])


func delete_nodes(node_ids: Array[String]) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or node_ids.is_empty():
		return
	var targets: Array[String] = []
	for raw_id: String in node_ids:
		var cid: String = raw_id.strip_edges()
		if not cid.is_empty() and not targets.has(cid) and not g.find_node(cid).is_empty():
			targets.append(cid)
	if targets.is_empty():
		return
	record_before_edit()
	var removed_any: bool = false
	for cid: String in targets:
		if g.remove_node(cid):
			removed_any = true
			_store.migrate_breakpoint_on_node_change(cid, "")
	if removed_any:
		if _canvas != null:
			_canvas.set_breakpoints(_store.get_active_breakpoints())
		if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT:
			g.reorder_bt_children_by_position(g.direction == &"TD" or g.direction == &"TB")
		var cur_focus: String = _current_focus_id()
		_commit_mutation(true, "" if targets.has(cur_focus) else cur_focus)


func duplicate_node(node_id: String) -> String:
	var created: Array[String] = duplicate_nodes([node_id])
	return created[0] if not created.is_empty() else ""


func duplicate_nodes(node_ids: Array[String]) -> Array[String]:
	var created_ids: Array[String] = []
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or node_ids.is_empty():
		return created_ids
	var is_bt_dup: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT)
	var targets: Array[String] = []
	for raw_id: String in node_ids:
		var cid: String = raw_id.strip_edges()
		if cid.is_empty() or targets.has(cid):
			continue
		var src_nd: Dictionary = g.find_node(cid)
		if src_nd.is_empty():
			continue
		if is_bt_dup and str(src_nd.get("kind", "")) == MermaidGraphModel.BT_ROOT_KIND:
			continue
		targets.append(cid)
	if targets.is_empty():
		return created_ids

	record_before_edit()
	var orig_edges: Array[Dictionary] = g.edges.duplicate(true)
	var old_to_new: Dictionary = {}
	for src_id: String in targets:
		var new_id: String = g.duplicate_node(src_id, Vector2(48.0, 48.0))
		if not new_id.is_empty():
			old_to_new[src_id] = new_id
			created_ids.append(new_id)

	if created_ids.is_empty():
		return created_ids

	# 若批量复制多个节点，自动克隆选集内部的连接边以完整保留子拓扑结构
	if created_ids.size() > 1:
		for ed: Dictionary in orig_edges:
			if bool(ed.get("discovered", false)):
				continue
			var ef: String = str(ed.get("from", ""))
			var et: String = str(ed.get("to", ""))
			if old_to_new.has(ef) and old_to_new.has(et):
				g.add_edge(
					str(old_to_new[ef]),
					str(old_to_new[et]),
					str(ed.get("label", "")),
					int(ed.get("priority", 0)),
					false,
					(ed.get("params", {}) as Dictionary).duplicate(true)
				)
		if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT:
			g.reorder_bt_children_by_position(g.direction == &"TD" or g.direction == &"TB")

	var focus_id: String = created_ids[created_ids.size() - 1]
	_commit_mutation(true, focus_id)
	if _canvas != null and created_ids.size() > 1:
		_canvas.select_nodes(created_ids, focus_id, false)
	return created_ids


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
	var mutated: bool = false
	if patch.has("fsm_variant"):
		_apply_fsm_variant(g, node_id, str(patch["fsm_variant"]))
		mutated = true
	if patch.has("set_initial"):
		if bool(patch["set_initial"]):
			g.initial_node_id = node_id
		elif g.initial_node_id == node_id:
			_reassign_fsm_initial_excluding(g, node_id)
		mutated = true
	if patch.has("set_interrupt"):
		if bool(patch["set_interrupt"]):
			if g.find_edge("*", node_id).is_empty():
				g.add_edge("*", node_id, "")
			if g.initial_node_id == node_id:
				_reassign_fsm_initial_excluding(g, node_id)
		else:
			g.remove_edge("*", node_id)
		mutated = true

	var field_patch: Dictionary = patch.duplicate(true)
	field_patch.erase("fsm_variant")
	field_patch.erase("set_initial")
	field_patch.erase("set_interrupt")
	if field_patch.has("kind"):
		var next_k: String = str(field_patch["kind"])
		var def_p: Dictionary = _default_params_for_kind(next_k, node_id)
		if not def_p.is_empty():
			var cur_p: Dictionary = (g.find_node(node_id).get("params", {}) as Dictionary).duplicate(true)
			for dk: Variant in def_p.keys():
				if not cur_p.has(dk):
					cur_p[dk] = def_p[dk]
			field_patch["params"] = cur_p
	if not field_patch.is_empty() and g.update_node_fields(node_id, field_patch):
		mutated = true
	if mutated:
		_commit_mutation(true, node_id)


static func _apply_fsm_variant(g: MermaidGraphModel, node_id: String, variant: String) -> void:
	match variant:
		"State:initial":
			g.remove_edge("*", node_id)
			var p_init: Dictionary = g.find_node(node_id).get("params", {}) as Dictionary
			if str(p_init.get("sub_graph_path", "")).strip_edges().is_empty():
				g.update_node_fields(node_id, {"params_patch": {"submachine": null}})
			g.initial_node_id = node_id
		"State:interrupt":
			if g.find_edge("*", node_id).is_empty():
				g.add_edge("*", node_id, "")
			var p_int: Dictionary = g.find_node(node_id).get("params", {}) as Dictionary
			if str(p_int.get("sub_graph_path", "")).strip_edges().is_empty():
				g.update_node_fields(node_id, {"params_patch": {"submachine": null}})
			if g.initial_node_id == node_id:
				_reassign_fsm_initial_excluding(g, node_id)
		"State:subgraph":
			g.update_node_fields(node_id, {"params_patch": {"submachine": true}})
		_:
			g.remove_edge("*", node_id)
			g.update_node_fields(node_id, {"params_patch": {"submachine": null, "sub_graph_path": null}})
			if g.initial_node_id == node_id:
				_reassign_fsm_initial_excluding(g, node_id)


static func _reassign_fsm_initial_excluding(g: MermaidGraphModel, excluded_id: String) -> void:
	g.initial_node_id = ""
	for nd: Dictionary in g.nodes:
		var cid: String = str(nd.get("id", ""))
		if not cid.is_empty() and cid != excluded_id and g.find_edge("*", cid).is_empty():
			g.initial_node_id = cid
			return


func rename_node(old_id: String, new_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null:
		return
	if _canvas != null and not g.nodes.is_empty():
		_canvas.sync_positions_to_model(g)
	var pre_snap: Dictionary = g.to_snapshot_dict()
	if g.rename_node(old_id, new_id):
		_store.migrate_breakpoint_on_node_change(old_id, new_id)
		if _canvas != null:
			_canvas.set_breakpoints(_store.get_active_breakpoints())
		if _undo_stack != null:
			_undo_stack.push_snapshot(_store.get_session_undo_key(), pre_snap)
		_commit_mutation(true, new_id.strip_edges())


func add_edge(from_id: String, to_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or from_id == to_id or g.find_node(from_id).is_empty() or g.find_node(to_id).is_empty():
		return
	var is_bt: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT)
	var src_kind: String = str(g.find_node(from_id).get("kind", "State"))
	var dst_kind: String = str(g.find_node(to_id).get("kind", "State"))
	if not CanvasGeometry.can_node_emit_edge(src_kind, is_bt) or not CanvasGeometry.can_node_accept_edge(dst_kind, is_bt):
		return
	if is_bt and _is_reachable(g, to_id, from_id):
		return
	record_before_edit()
	_connect_edge_with_schema_rules(g, from_id, to_id)
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
	if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT:
		g.reorder_bt_children_by_position(g.direction == &"TD" or g.direction == &"TB")
	_store.refresh_editable_topology_plan()
	if _canvas != null:
		_canvas.sync_edge_defs_from_model(g)
	view_sync_requested.emit(false, false, _current_focus_id())


func reverse_edge(from_id: String, to_id: String) -> void:
	var g: MermaidGraphModel = _editable_graph_or_null()
	if g == null or from_id == "*" or from_id == to_id:
		return
	var orig_ed: Dictionary = g.find_edge(from_id, to_id)
	if orig_ed.is_empty():
		return
	if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT:
		return
	record_before_edit()
	var orig_lbl: String = str(orig_ed.get("label", ""))
	var orig_prio: int = int(orig_ed.get("priority", 0))
	var orig_params: Dictionary = (orig_ed.get("params", {}) as Dictionary).duplicate(true)
	g.remove_edge(from_id, to_id)
	g.add_edge(to_id, from_id, orig_lbl, orig_prio, false, orig_params)
	_store.refresh_editable_topology_plan()
	if _canvas != null:
		_canvas.sync_edge_defs_from_model(g)
	view_sync_requested.emit(false, false, to_id)


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
	toggle_breakpoints([node_id])


func toggle_breakpoints(node_ids: Array[String]) -> void:
	if _store == null or node_ids.is_empty():
		return
	var clean_ids: Array[String] = []
	for raw_id: String in node_ids:
		var cid: String = raw_id.strip_edges()
		if not cid.is_empty() and not clean_ids.has(cid):
			clean_ids.append(cid)
	if clean_ids.is_empty():
		return

	# 多选批量切换策略：若存在任一未设断点的节点则统一开启，全部已有断点时统一清除
	var any_missing: bool = false
	for cid: String in clean_ids:
		if not _store.has_breakpoint(cid):
			any_missing = true
			break

	for cid: String in clean_ids:
		var cur_on: bool = _store.has_breakpoint(cid)
		if (any_missing and not cur_on) or (not any_missing and cur_on):
			var next_on: bool = _store.toggle_breakpoint(cid)
			breakpoint_changed.emit(_store.get_selected_live_memory_id(), cid, next_on)

	if _canvas != null:
		_canvas.set_breakpoints(_store.get_active_breakpoints())
	view_sync_requested.emit(false, false, _current_focus_id())

#endregion


#region 内部智能落位、防重叠微移与模式约束辅助

func _spawn_node_internal(
	g: MermaidGraphModel,
	kind: String,
	world_pos: Vector2,
	align_input_port: bool,
	preset: String = ""
) -> String:
	var raw_k: String = kind.strip_edges()
	var eff_preset: String = preset.strip_edges()
	if raw_k.contains(":"):
		var parts: PackedStringArray = raw_k.split(":", false, 1)
		raw_k = parts[0]
		if eff_preset.is_empty() and parts.size() > 1:
			eff_preset = parts[1]
	var clean_kind: String = raw_k if not raw_k.is_empty() else "State"

	var was_empty: bool = g.nodes.is_empty()
	if was_empty and g.schema == MermaidGraphModel.SCHEMA_GENERIC:
		g.diagram_type = MermaidGraphModel.TYPE_STATE_V2 if clean_kind == "State" else MermaidGraphModel.TYPE_FLOWCHART
		g.schema = MermaidGraphModel.SCHEMA_FSM if clean_kind == "State" else MermaidGraphModel.SCHEMA_BT
	var is_fsm: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM)

	# 行为树显式根节点保障：唯一 Root 防重、为旧树前置插入 Root，以及空画布创建任意 BT 节点时自动生成并挂载 Root
	if not is_fsm:
		if clean_kind == MermaidGraphModel.BT_ROOT_KIND:
			var existing_root: String = g.find_bt_root_id()
			if not existing_root.is_empty():
				return existing_root
			var prev_entry: String = g.initial_node_id
			var root_spawn_w: Vector2 = world_pos
			if not prev_entry.is_empty() and not g.find_node(prev_entry).is_empty():
				var prev_pos: Vector2 = g.find_node(prev_entry).get("pos", world_pos) as Vector2
				var is_v_prev: bool = (g.direction == &"TD" or g.direction == &"TB")
				root_spawn_w = prev_pos + (Vector2(60.0, -96.0) if is_v_prev else Vector2(-168.0, 20.0))
			var root_id: String = g.generate_unique_node_id("root")
			var root_title: String = FlowEditorI18n.kind_label(MermaidGraphModel.BT_ROOT_KIND)
			var root_pos: Vector2 = _compute_smart_spawn_pos(g, root_id, root_title, root_spawn_w, false)
			g.ensure_node(root_id, root_title, MermaidGraphModel.default_shape_for_kind(MermaidGraphModel.BT_ROOT_KIND), MermaidGraphModel.BT_ROOT_KIND, root_pos, true, {})
			g.initial_node_id = root_id
			if not prev_entry.is_empty() and not g.find_node(prev_entry).is_empty() and g.find_incoming_edges(prev_entry).is_empty():
				g.add_edge(root_id, prev_entry, "")
			return root_id

		if was_empty:
			var is_vert_bt: bool = (g.direction == &"TD" or g.direction == &"TB")
			var auto_root_id: String = g.generate_unique_node_id("root")
			var auto_root_title: String = FlowEditorI18n.kind_label(MermaidGraphModel.BT_ROOT_KIND)
			var root_offset: Vector2 = Vector2(0.0, -108.0) if is_vert_bt else Vector2(-196.0, 0.0)
			var auto_root_pos: Vector2 = _compute_smart_spawn_pos(g, auto_root_id, auto_root_title, world_pos + root_offset, false)
			g.ensure_node(auto_root_id, auto_root_title, MermaidGraphModel.default_shape_for_kind(MermaidGraphModel.BT_ROOT_KIND), MermaidGraphModel.BT_ROOT_KIND, auto_root_pos, true, {})
			g.initial_node_id = auto_root_id

	var new_id: String = g.generate_unique_node_id("state_" if is_fsm else "n")
	var init_title: String = new_id if is_fsm else FlowEditorI18n.kind_label(clean_kind)
	var init_params: Dictionary = _default_params_for_kind(clean_kind, new_id)
	if is_fsm and eff_preset == "subgraph":
		init_title = FlowEditorI18n.t(&"drawer.init_submachine_title")
		init_params["submachine"] = true
	var spawn_pos: Vector2 = _compute_smart_spawn_pos(g, new_id, init_title, world_pos, align_input_port)
	g.ensure_node(
		new_id, init_title,
		MermaidGraphModel.default_shape_for_kind(clean_kind), clean_kind,
		spawn_pos, true, init_params
	)
	if is_fsm:
		if g.initial_node_id.is_empty() and g.nodes.size() == 1 and eff_preset != "interrupt":
			g.initial_node_id = new_id
		if eff_preset == "interrupt" and g.find_edge("*", new_id).is_empty():
			g.add_edge("*", new_id, "")
	else:
		var bt_root_id: String = g.find_bt_root_id()
		if was_empty and not bt_root_id.is_empty() and bt_root_id != new_id:
			g.add_edge(bt_root_id, new_id, "")
		elif g.initial_node_id.is_empty() and g.nodes.size() == 1:
			g.initial_node_id = new_id
	return new_id


func _resolve_drawer_auto_parent(g: MermaidGraphModel, preset: String) -> String:
	if preset == "interrupt":
		return ""
	var focus_id: String = _current_focus_id()
	if focus_id.is_empty() or g.find_node(focus_id).is_empty():
		var bt_root_id: String = g.find_bt_root_id() if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT else ""
		if not bt_root_id.is_empty() and g.find_outgoing_edges(bt_root_id).is_empty():
			return bt_root_id
		return ""
	if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM:
		return focus_id

	# BT 智能挂载：根节点/空装饰器挂载唯一子节点；组合节点直接追加；叶节点/已满单子节点自动回溯至最近父组合节点并列追加
	var cur_id: String = focus_id
	var visited: Dictionary = {}
	while not cur_id.is_empty() and not visited.has(cur_id):
		visited[cur_id] = true
		var nd: Dictionary = g.find_node(cur_id)
		if nd.is_empty():
			break
		var k_s: String = str(nd.get("kind", ""))
		if BT_SINGLE_CHILD_KINDS.has(k_s):
			if g.find_outgoing_edges(cur_id).is_empty():
				return cur_id
		elif CanvasGeometry.can_node_emit_edge(k_s, true):
			return cur_id
		var parent_id: String = ""
		for ed: Dictionary in g.edges:
			var ef: String = str(ed.get("from", ""))
			if str(ed.get("to", "")) == cur_id and ef != "*":
				parent_id = ef
				break
		cur_id = parent_id
	return ""


func _compute_downstream_world_pos(g: MermaidGraphModel, from_id: String) -> Vector2:
	var src_nd: Dictionary = g.find_node(from_id)
	var src_pos: Vector2 = src_nd.get("pos", Vector2.ZERO) as Vector2
	var src_sz: Vector2 = MermaidMetrics.estimate_node_size(src_nd)
	var src_rect := Rect2(src_pos, src_sz)
	var sibling_cnt: int = g.find_outgoing_edges(from_id).size()
	var is_vert: bool = (g.direction == &"TD" or g.direction == &"TB")
	if is_vert:
		return Vector2(src_rect.get_center().x + float(sibling_cnt) * 192.0, src_rect.end.y + 68.0)
	return Vector2(src_rect.end.x + 84.0, src_rect.get_center().y + float(sibling_cnt) * 56.0)


func _compute_smart_spawn_pos(
	g: MermaidGraphModel,
	new_id: String,
	init_title: String,
	world_pos: Vector2,
	align_input_port: bool
) -> Vector2:
	var est_sz: Vector2 = MermaidMetrics.estimate_node_size({"id": new_id, "title": init_title})
	var is_vert: bool = (g.direction == &"TD" or g.direction == &"TB")
	var pos: Vector2 = world_pos - est_sz * 0.5
	if align_input_port:
		pos = Vector2(world_pos.x - est_sz.x * 0.5, world_pos.y) if is_vert else Vector2(world_pos.x, world_pos.y - est_sz.y * 0.5)
	if _canvas != null and _canvas.snapping_enabled:
		pos = pos.snapped(Vector2(16.0, 16.0))

	# 防堆叠避让：若同一位置已有节点重叠，沿副轴自动平推一格净空
	var nudge_step: Vector2 = Vector2(192.0, 0.0) if is_vert else Vector2(0.0, 56.0)
	for _attempt: int in range(10):
		var candidate_rect := Rect2(pos, est_sz).grow(-4.0)
		var hit_existing: bool = false
		for nd: Dictionary in g.nodes:
			var other_pos: Vector2 = nd.get("pos", Vector2.ZERO) as Vector2
			var other_sz: Vector2 = MermaidMetrics.estimate_node_size(nd)
			if candidate_rect.intersects(Rect2(other_pos, other_sz)):
				hit_existing = true
				break
		if not hit_existing:
			break
		pos += nudge_step
	return pos


func _connect_edge_with_schema_rules(g: MermaidGraphModel, from_id: String, to_id: String) -> void:
	var is_bt: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT)
	if is_bt:
		var src_kind: String = str(g.find_node(from_id).get("kind", ""))
		# BT 根节点与装饰器最多只允许 1 个子节点：重新拉线时自动重定向，无需先手动删旧边
		if BT_SINGLE_CHILD_KINDS.has(src_kind):
			for old_ed: Dictionary in g.find_outgoing_edges(from_id):
				var old_to: String = str(old_ed.get("to", ""))
				if old_to != to_id:
					g.remove_edge(from_id, old_to)
		# BT 每个子节点最多归属 1 个父节点：若已被其他父节点连接则平滑迁移归属
		for ed_in: Dictionary in g.edges.duplicate():
			var ef: String = str(ed_in.get("from", ""))
			var et: String = str(ed_in.get("to", ""))
			if et == to_id and ef != "*" and ef != from_id:
				g.remove_edge(ef, et)
	g.add_edge(from_id, to_id, "")
	if is_bt:
		g.reorder_bt_children_by_position(g.direction == &"TD" or g.direction == &"TB")


static func _is_reachable(g: MermaidGraphModel, start_id: String, goal_id: String) -> bool:
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == goal_id:
			return true
		for ed: Dictionary in g.edges:
			if str(ed.get("from", "")) == cur:
				var nxt: String = str(ed.get("to", ""))
				if not nxt.is_empty() and not visited.has(nxt):
					visited[nxt] = true
					queue.append(nxt)
	return false


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
		"UtilitySelector": return {"momentum": 0.10, "min_score": 0.01, "top_k": 1}
		"Cooldown": return {"cooldown_sec": 1.0, "jitter_sec": 0.0}
		"Wait": return {"duration_sec": 0.5, "jitter_sec": 0.0}
		"Repeater": return {"repeat_count": 3, "abort_on_failure": true}
		"TimeLimit": return {"timeout_sec": 3.0}
		"Service": return {"service_key": "", "interval_sec": 0.25, "jitter_sec": 0.05}
		_: return {}

#endregion
