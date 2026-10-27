@tool
extends Control

## Mermaid 多态轻量 2D 矢量流转画布门面（2D Vector Graph Canvas Facade）。[br]
##
## 负责视口状态与子模块装配协调；几何计算、边路由、运行期脉冲、指针快捷键、右键菜单、快速搜索建点与原位改名分别委派至独立子控制器。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const CanvasEdgeRouter = preload(FlowGraphContracts.SCRIPT_CANVAS_EDGE_ROUTER)
const CanvasPainter = preload(FlowGraphContracts.SCRIPT_CANVAS_PAINTER)
const CanvasContextMenu = preload(FlowGraphContracts.SCRIPT_CANVAS_CONTEXT_MENU)
const CanvasQuickNodePicker = preload(FlowGraphContracts.SCRIPT_CANVAS_QUICK_PICKER)
const CanvasInlineRenamer = preload(FlowGraphContracts.SCRIPT_CANVAS_INLINE_RENAMER)
const CanvasSelectionModel = preload(FlowGraphContracts.SCRIPT_CANVAS_SELECTION)
const CanvasInputController = preload(FlowGraphContracts.SCRIPT_CANVAS_INPUT_CTRL)
const CanvasTelemetryState = preload(FlowGraphContracts.SCRIPT_CANVAS_TELEMETRY)


#region 信号定义与公开属性

signal graph_mutated()
signal before_graph_mutation()
signal edge_connection_added(from_id: String, to_id: String)
signal edge_connection_removed(from_id: String, to_id: String)
signal edge_reversed_requested(from_id: String, to_id: String)
signal node_force_requested(node_id: String, params: Dictionary)
signal node_inspected(node_id: String)
signal view_zoom_changed(new_zoom: float)

signal node_added_at(kind: String, world_pos: Vector2)
signal node_added_and_connected(from_id: String, kind: String, world_pos: Vector2)
signal node_inserted_on_edge(from_id: String, to_id: String, kind: String, world_pos: Vector2)
signal palette_item_dropped(kind: String, preset: String, world_pos: Vector2, target_node_id: String, split_from_id: String, split_to_id: String)
signal node_drawer_toggle_requested()
signal node_title_edited_inline(node_id: String, new_title: String)
signal node_deleted_requested(node_id: String)
signal node_duplicated_requested(node_id: String)
signal nodes_deleted_requested(node_ids: Array[String])
signal nodes_duplicated_requested(node_ids: Array[String])
signal initial_node_set_requested(node_id: String)
signal any_state_edge_toggled(node_id: String)
signal breakpoint_toggled(node_id: String)
signal breakpoints_toggled_requested(node_ids: Array[String])
signal sub_graph_open_requested(sub_graph_path: String, node_id: String)
signal undo_requested()
signal redo_requested()
signal direction_toggle_requested()
signal auto_layout_requested()

var ui_scale: float = 1.0:
	set(v):
		var next_s: float = clampf(v, 0.75, 3.0)
		if not is_equal_approx(ui_scale, next_s):
			var prev_s: float = maxf(ui_scale, 0.01)
			ui_scale = next_s
			zoom = clampf(zoom * (ui_scale / prev_s), 0.35 * ui_scale, 2.60 * ui_scale)
			queue_redraw()

var zoom: float = 1.0:
	set(v):
		var s: float = maxf(ui_scale, 0.75)
		var clamped: float = clampf(v, 0.35 * s, 2.60 * s)
		if not is_equal_approx(zoom, clamped):
			zoom = clamped
			_sync_inline_renamer_rect()
			view_zoom_changed.emit(zoom)
			queue_redraw()

var scroll_offset: Vector2 = Vector2.ZERO:
	set(v):
		if scroll_offset != v:
			scroll_offset = v
			_sync_inline_renamer_rect()
			queue_redraw()

var snapping_enabled: bool = true:
	set(v):
		snapping_enabled = v
		queue_redraw()

var minimap_enabled: bool = true:
	set(v):
		minimap_enabled = v
		queue_redraw()

var show_all_labels: bool = false:
	set(v):
		show_all_labels = v
		queue_redraw()

var breakpoint_node_ids: Dictionary = {}

#endregion


#region 内部运行态字段

var _palette: CanvasThemePalette = null
var _context_menu: CanvasContextMenu = null
var _quick_picker: CanvasQuickNodePicker = null
var _inline_renamer: CanvasInlineRenamer = null
var _selection: CanvasSelectionModel = CanvasSelectionModel.new()
var _input_ctrl: CanvasInputController = null
var _telemetry: CanvasTelemetryState = CanvasTelemetryState.new()
var _graph_ref: MermaidGraphModel = null
var _plan: Dictionary = {}
var _live_mode: bool = false
var _read_only_topology: bool = false
var _routes_dirty: bool = false

var _nodes: Dictionary = {}
var _node_draw_order: Array[String] = []
var _routed_edges: Array[Dictionary] = []
var _edge_by_key: Dictionary = {}
var _has_any_state_zone: bool = false
var _any_zone_rect: Rect2 = Rect2()
var _any_origin_boxes: Array[Rect2] = []

var _last_inspected_node_id: String = ""
var _last_inspected_edge_key: String = ""
var _drag_start_positions: Dictionary = {}
var _hovered_node_id: String = ""
var _hovered_port_node_id: String = ""
var _hovered_portal_key: String = ""
var _hovered_edge_key: String = ""
var _connecting_from_id: String = ""
var _connecting_mouse_world: Vector2 = Vector2.ZERO
var _snap_target_node_id: String = ""
var _snap_target_valid: bool = true

#endregion


#region 生命周期与子模块接线

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_palette = CanvasThemePalette.new()
	_ensure_controllers()


func _ensure_controllers() -> void:
	if _context_menu == null:
		_context_menu = CanvasContextMenu.new()
		_context_menu.setup(self)
		_context_menu.quick_picker_requested.connect(func(spos: Vector2i, wpos: Vector2) -> void: _open_quick_picker(spos, wpos, "", ""))
		_context_menu.node_drawer_toggle_requested.connect(func() -> void: node_drawer_toggle_requested.emit())
		_context_menu.node_rename_requested.connect(start_inline_rename)
		_context_menu.node_append_child_requested.connect(_on_append_downstream_requested)
		_context_menu.node_delete_requested.connect(func(nid: String) -> void: _emit_nodes_delete([nid]))
		_context_menu.node_duplicate_requested.connect(func(nid: String) -> void: _emit_nodes_duplicate([nid]))
		_context_menu.nodes_delete_requested.connect(_emit_nodes_delete)
		_context_menu.nodes_duplicate_requested.connect(_emit_nodes_duplicate)
		_context_menu.initial_node_set_requested.connect(func(nid: String) -> void: initial_node_set_requested.emit(nid))
		_context_menu.any_state_edge_toggled.connect(func(nid: String) -> void: any_state_edge_toggled.emit(nid))
		_context_menu.breakpoint_toggled.connect(func(nid: String) -> void: _emit_breakpoints_toggle([nid]))
		_context_menu.breakpoints_toggle_requested.connect(_emit_breakpoints_toggle)
		_context_menu.sub_graph_open_requested.connect(func(sp: String, nid: String) -> void: sub_graph_open_requested.emit(sp, nid))
		_context_menu.node_force_requested.connect(func(nid: String, p: Dictionary) -> void: node_force_requested.emit(nid, p))
		_context_menu.edge_inspect_requested.connect(_on_ctx_edge_inspect)
		_context_menu.edge_insert_node_requested.connect(_on_ctx_edge_insert_node)
		_context_menu.edge_reverse_requested.connect(func(f: String, t: String) -> void: edge_reversed_requested.emit(f, t))
		_context_menu.edge_delete_requested.connect(func(f: String, t: String) -> void:
			_selection.select_edge("")
			edge_connection_removed.emit(f, t)
		)
		_context_menu.direction_toggle_requested.connect(_on_ctx_direction_toggle)
		_context_menu.auto_layout_requested.connect(_on_ctx_auto_layout)
		_context_menu.fit_view_requested.connect(fit_graph_view)

	if _quick_picker == null:
		_quick_picker = CanvasQuickNodePicker.new()
		_quick_picker.setup(self)
		_quick_picker.node_kind_chosen.connect(_on_quick_picker_chosen)
		_quick_picker.picker_closed.connect(_on_quick_picker_closed)

	if _inline_renamer == null:
		_inline_renamer = CanvasInlineRenamer.new()
		_inline_renamer.setup(self)
		_inline_renamer.rename_committed.connect(func(nid: String, nt: String) -> void: node_title_edited_inline.emit(nid, nt))

	if _input_ctrl == null:
		_input_ctrl = CanvasInputController.new()
		_input_ctrl.scroll_delta_requested.connect(func(d: Vector2) -> void: scroll_offset += d)
		_input_ctrl.zoom_at_requested.connect(_zoom_at_screen_point)
		_input_ctrl.minimap_pan_requested.connect(func(tw: Vector2) -> void: scroll_offset = tw * zoom - size * 0.5)
		_input_ctrl.frame_or_fit_requested.connect(frame_selection_or_fit)
		_input_ctrl.selection_visual_changed.connect(_on_selection_visual_changed)
		_input_ctrl.portal_hub_jumped.connect(_on_input_portal_hub_jumped)
		_input_ctrl.hover_state_changed.connect(_on_input_hover_changed)
		_input_ctrl.connection_preview_changed.connect(_on_input_connection_preview)
		_input_ctrl.wire_dropped_on_blank.connect(_on_input_wire_dropped_on_blank)
		_input_ctrl.quick_picker_requested.connect(_open_quick_picker)
		_input_ctrl.inline_rename_requested.connect(start_inline_rename)
		_input_ctrl.append_downstream_requested.connect(_on_append_downstream_requested)
		_input_ctrl.edge_connection_added.connect(_on_input_edge_added)
		_input_ctrl.edge_connection_removed.connect(func(f: String, t: String) -> void: edge_connection_removed.emit(f, t))
		_input_ctrl.group_drag_started.connect(_on_input_group_drag_started)
		_input_ctrl.group_dragged_by.connect(_on_input_group_dragged_by)
		_input_ctrl.group_drag_finished.connect(_on_input_group_drag_finished)
		_input_ctrl.node_force_requested.connect(func(nid: String, p: Dictionary) -> void: node_force_requested.emit(nid, p))
		_input_ctrl.sub_graph_open_requested.connect(func(sp: String, nid: String) -> void: sub_graph_open_requested.emit(sp, nid))
		_input_ctrl.node_context_menu_requested.connect(_on_input_node_context_menu)
		_input_ctrl.edge_context_menu_requested.connect(_on_input_edge_context_menu)
		_input_ctrl.blank_context_menu_requested.connect(_on_input_blank_context_menu)
		_input_ctrl.nodes_deleted_requested.connect(_emit_nodes_delete)
		_input_ctrl.nodes_duplicated_requested.connect(_emit_nodes_duplicate)
		_input_ctrl.breakpoints_toggle_requested.connect(_emit_breakpoints_toggle)
		_input_ctrl.undo_requested.connect(func() -> void: undo_requested.emit())
		_input_ctrl.redo_requested.connect(func() -> void: redo_requested.emit())


func _process(delta: float) -> void:
	if _telemetry.tick(delta):
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_EXIT and _input_ctrl != null:
		_input_ctrl.on_focus_lost(self, _selection)
	elif what == NOTIFICATION_DRAG_END and _connecting_from_id.is_empty():
		if not _snap_target_node_id.is_empty() or not _hovered_edge_key.is_empty():
			_snap_target_node_id = ""
			_hovered_edge_key = ""
			queue_redraw()


func apply_locale() -> void:
	if _context_menu != null:
		_context_menu.apply_locale()
	if _quick_picker != null and _quick_picker.is_open():
		_quick_picker.close_picker()
	tooltip_text = ""
	queue_redraw()

#endregion


#region 公开渲染、视野缩放与运行期遥测 API

func render_graph(
	graph: MermaidGraphModel,
	live_mode: bool,
	precomputed_plan: Dictionary = {},
	read_only_topology: bool = false
) -> void:
	if _inline_renamer != null and _inline_renamer.is_active():
		_inline_renamer.cancel_and_close()
	_graph_ref = graph
	_live_mode = live_mode
	_read_only_topology = live_mode or read_only_topology
	_nodes.clear()
	_node_draw_order.clear()
	_routed_edges.clear()
	_edge_by_key.clear()
	_telemetry.clear()
	_connecting_from_id = ""
	_snap_target_node_id = ""
	_hovered_port_node_id = ""
	_routes_dirty = false
	if _input_ctrl != null:
		_input_ctrl.reset_interaction_state()

	if graph == null or graph.nodes.is_empty():
		_plan = {}
		_has_any_state_zone = false
		_selection.clear_all()
		_last_inspected_node_id = ""
		tooltip_text = ""
		queue_redraw()
		return

	_plan = precomputed_plan if not precomputed_plan.is_empty() else MermaidLayout.analyze_topology(graph)
	var interrupt_set: Dictionary = _plan.get("interrupt_set", {}) as Dictionary
	var terminal_set: Dictionary = _collect_fsm_terminal_ids(graph)

	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		var sz: Vector2 = MermaidMetrics.estimate_node_size(nd)
		var pos: Vector2 = nd.get("pos", Vector2.ZERO) as Vector2
		var p_copy: Dictionary = (nd.get("params", {}) as Dictionary).duplicate(true)
		var sub_p: String = str(p_copy.get("sub_graph_path", nd.get("sub_graph_path", ""))).strip_edges()
		_nodes[nid] = {
			"id": nid, "title": str(nd.get("title", nid)),
			"kind": str(nd.get("kind", "State")), "shape": str(nd.get("shape", "rect")),
			"rect": Rect2(pos, sz), "is_initial": nid == graph.initial_node_id,
			"is_interrupt": interrupt_set.has(nid), "is_terminal": terminal_set.has(nid),
			"sub_graph_path": sub_p, "params": p_copy,
		}
		_node_draw_order.append(nid)

	if not _hovered_node_id.is_empty() and not _nodes.has(_hovered_node_id):
		_hovered_node_id = ""

	_rebuild_routes()
	_selection.prune_invalid(_nodes, _edge_by_key)
	_last_inspected_node_id = _selection.primary_node_id
	queue_redraw()


static func _collect_fsm_terminal_ids(graph: MermaidGraphModel) -> Dictionary:
	var out: Dictionary = {}
	if graph == null or graph.diagram_type != MermaidGraphModel.TYPE_STATE_V2:
		return out
	var has_out: Dictionary = {}
	for ed: Dictionary in graph.edges:
		var f: String = str(ed.get("from", ""))
		if f != "*" and f != str(ed.get("to", "")):
			has_out[f] = true
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		if not has_out.has(nid) and nid != graph.initial_node_id:
			out[nid] = true
	return out


func set_breakpoints(ids: Array) -> void:
	breakpoint_node_ids.clear()
	for id_v: Variant in ids:
		var clean_id: String = str(id_v).strip_edges()
		if not clean_id.is_empty():
			breakpoint_node_ids[clean_id] = true
	queue_redraw()


func get_connection_list() -> Array[Dictionary]:
	_ensure_routes_fresh()
	var out: Array[Dictionary] = []
	for ed: Dictionary in _routed_edges:
		if int(ed.get("route", CanvasGeometry.ROUTE_STRAIGHT)) != CanvasGeometry.ROUTE_ANY_BUS:
			out.append({
				"from_node": StringName(str(ed["from"])), "from_port": 0,
				"to_node": StringName(str(ed["to"])), "to_port": 0,
			})
	return out


func fit_graph_view() -> void:
	_ensure_routes_fresh()
	var s: float = maxf(ui_scale, 0.75)
	if _nodes.is_empty():
		zoom = s
		scroll_offset = Vector2.ZERO
		return
	var bounds: Rect2 = _compute_world_bounds()
	var content_sz: Vector2 = bounds.size + Vector2(96.0, 88.0)
	var view_sz: Vector2 = size if size.x > 120.0 * s else Vector2(960.0 * s, 600.0 * s)
	var fit_z: float = minf(view_sz.x / maxf(content_sz.x, 1.0), view_sz.y / maxf(content_sz.y, 1.0))
	zoom = clampf(fit_z, 0.45 * s, 1.18 * s)
	scroll_offset = bounds.get_center() * zoom - view_sz * 0.5
	queue_redraw()


func zoom_step(factor: float) -> void:
	var s: float = maxf(ui_scale, 0.75)
	var view_sz: Vector2 = size if size.x > 80.0 * s else Vector2(960.0 * s, 600.0 * s)
	_zoom_at_screen_point(view_sz * 0.5, factor)


func reset_zoom_100() -> void:
	var s: float = maxf(ui_scale, 0.75)
	var view_sz: Vector2 = size if size.x > 80.0 * s else Vector2(960.0 * s, 600.0 * s)
	var center_w: Vector2 = screen_to_world(view_sz * 0.5)
	zoom = s
	scroll_offset = center_w * zoom - view_sz * 0.5
	queue_redraw()


func get_display_zoom_percent() -> int:
	return roundi((zoom / maxf(ui_scale, 0.01)) * 100.0)


func get_viewport_center_world() -> Vector2:
	var s: float = maxf(ui_scale, 0.75)
	var view_sz: Vector2 = size if size.x > 80.0 * s else Vector2(820.0 * s, 540.0 * s)
	return screen_to_world(view_sz * 0.5)


func frame_selection_or_fit() -> void:
	if _selection.get_selected_count() <= 0:
		fit_graph_view()
		return
	var has_rect: bool = false
	var sel_bounds := Rect2()
	for nid: String in _selection.selected_node_ids:
		if _nodes.has(nid):
			var nr: Rect2 = (_nodes[nid] as Dictionary)["rect"] as Rect2
			sel_bounds = nr if not has_rect else sel_bounds.merge(nr)
			has_rect = true
	if not has_rect:
		fit_graph_view()
		return
	var s: float = maxf(ui_scale, 0.75)
	var content_sz: Vector2 = sel_bounds.size + Vector2(128.0, 112.0)
	var view_sz: Vector2 = size if size.x > 120.0 * s else Vector2(960.0 * s, 600.0 * s)
	var fit_z: float = minf(view_sz.x / maxf(content_sz.x, 1.0), view_sz.y / maxf(content_sz.y, 1.0))
	zoom = clampf(fit_z, 0.45 * s, 1.18 * s)
	scroll_offset = sel_bounds.get_center() * zoom - view_sz * 0.5
	queue_redraw()


func select_and_focus_node(node_id: String, pan_to_center: bool = false) -> void:
	if node_id.is_empty() or not _nodes.has(node_id):
		_selection.clear_all()
		_last_inspected_node_id = ""
		_last_inspected_edge_key = ""
		queue_redraw()
		return
	_selection.select_single_node(node_id)
	_last_inspected_node_id = node_id
	_last_inspected_edge_key = ""
	if pan_to_center:
		var s: float = maxf(ui_scale, 0.75)
		var view_sz: Vector2 = size if size.x > 80.0 * s else Vector2(960.0 * s, 600.0 * s)
		var nr: Rect2 = (_nodes[node_id] as Dictionary)["rect"] as Rect2
		scroll_offset = nr.get_center() * zoom - view_sz * 0.5
	queue_redraw()


func select_nodes(node_ids: Array[String], preferred_primary: String = "", emit_inspect: bool = false) -> void:
	var valid_ids: Array[String] = []
	for nid: String in node_ids:
		if _nodes.has(nid):
			valid_ids.append(nid)
	_selection.select_nodes(valid_ids, preferred_primary)
	_last_inspected_edge_key = ""
	if emit_inspect and _selection.primary_node_id != _last_inspected_node_id:
		_last_inspected_node_id = _selection.primary_node_id
		node_inspected.emit(_last_inspected_node_id)
	else:
		_last_inspected_node_id = _selection.primary_node_id
	queue_redraw()


func start_inline_rename(node_id: String) -> void:
	if _read_only_topology or node_id.is_empty() or not _nodes.has(node_id):
		return
	_ensure_controllers()
	var nd: Dictionary = _nodes[node_id] as Dictionary
	var cur_title: String = str(nd.get("title", node_id))
	var w_rect: Rect2 = nd["rect"] as Rect2
	_selection.select_single_node(node_id)
	_last_inspected_node_id = node_id
	_inline_renamer.open_for_node(node_id, cur_title, w_rect, zoom, scroll_offset, ui_scale)
	queue_redraw()


func get_selected_node_id() -> String:
	return _selection.primary_node_id


func get_selected_node_ids() -> Array[String]:
	return _selection.selected_node_ids.duplicate()


func get_selected_edge_key() -> String:
	return _selection.selected_edge_key


func get_selected_node_params() -> Dictionary:
	var pid: String = _selection.primary_node_id
	if not pid.is_empty() and _nodes.has(pid):
		return (_nodes[pid] as Dictionary).get("params", {}) as Dictionary
	return {}


func clear_live_highlights() -> void:
	_telemetry.clear()
	queue_redraw()


func apply_frame_telemetry(frame: Dictionary) -> void:
	_telemetry.apply_frame(frame)
	if frame.has("breakpoints") and frame["breakpoints"] is Array:
		set_breakpoints(frame["breakpoints"] as Array)
	queue_redraw()


func trigger_edge_pulse(from_id: String, to_id: String) -> void:
	_ensure_routes_fresh()
	_telemetry.trigger_pulse(from_id, to_id, _nodes, _edge_by_key, _plan)
	queue_redraw()


func sync_positions_to_model(graph: MermaidGraphModel) -> void:
	if graph == null:
		return
	for nid: String in _node_draw_order:
		if _nodes.has(nid):
			graph.set_node_pos(nid, ((_nodes[nid] as Dictionary)["rect"] as Rect2).position)


func sync_edge_defs_from_model(graph: MermaidGraphModel) -> void:
	_graph_ref = graph
	if graph == null:
		_routed_edges.clear()
		_edge_by_key.clear()
		queue_redraw()
		return
	_plan = MermaidLayout.analyze_topology(graph)
	var interrupt_set: Dictionary = _plan.get("interrupt_set", {}) as Dictionary
	var terminal_set: Dictionary = _collect_fsm_terminal_ids(graph)
	for nid: String in _node_draw_order:
		if _nodes.has(nid):
			(_nodes[nid] as Dictionary)["is_interrupt"] = interrupt_set.has(nid)
			(_nodes[nid] as Dictionary)["is_terminal"] = terminal_set.has(nid)
			(_nodes[nid] as Dictionary)["is_initial"] = (nid == graph.initial_node_id)
	_routes_dirty = false
	_rebuild_routes()
	_selection.prune_invalid(_nodes, _edge_by_key)
	queue_redraw()

#endregion


#region 脏标记合并路由、绘制编排与交互回调

func _ensure_routes_fresh() -> void:
	if not _routes_dirty:
		return
	_routes_dirty = false
	if _graph_ref != null and not _read_only_topology and _is_bt_schema():
		sync_positions_to_model(_graph_ref)
		if _graph_ref.reorder_bt_children_by_position(_is_vertical_layout()):
			_plan = MermaidLayout.analyze_topology(_graph_ref)
	_rebuild_routes()


func _rebuild_routes() -> void:
	var route_res: Dictionary = CanvasEdgeRouter.build_routes(_graph_ref, _plan, _nodes, _node_draw_order)
	_routed_edges = route_res["routed_edges"] as Array[Dictionary]
	_edge_by_key = route_res["edge_by_key"] as Dictionary
	_has_any_state_zone = bool(route_res["has_any_state_zone"])
	_any_zone_rect = route_res["any_zone_rect"] as Rect2
	_any_origin_boxes = route_res["any_origin_boxes"] as Array[Rect2]


func _draw() -> void:
	_ensure_routes_fresh()
	if _palette == null or _palette.is_stale():
		_palette = CanvasThemePalette.new()

	CanvasPainter.draw_backdrop_and_grid(self, scroll_offset, zoom, _palette)
	if _nodes.is_empty():
		CanvasPainter.draw_empty_placeholder(self, ui_scale, _palette)
		if _selection.is_marquee_visible():
			CanvasPainter.draw_marquee_box(self, _palette, _selection.get_marquee_screen_rect(zoom, scroll_offset))
		return

	var font: Font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return

	var active_edge_set: Dictionary = {}
	for pair: Array in _telemetry.continuous_edges:
		active_edge_set["%s->%s" % [str(pair[0]), str(pair[1])]] = true
	var pulse_edge_set: Dictionary = {}
	for p: Dictionary in _telemetry.burst_pulses:
		pulse_edge_set[str(p["key"])] = true

	var draw_ctx: Dictionary = {
		"ui_scale": ui_scale, "zoom": zoom, "scroll_offset": scroll_offset,
		"nodes": _nodes, "node_order": _node_draw_order,
		"routed_edges": _routed_edges, "edge_by_key": _edge_by_key,
		"has_any_state_zone": _has_any_state_zone, "any_zone_rect": _any_zone_rect, "any_origin_boxes": _any_origin_boxes,
		"active_edge_set": active_edge_set, "pulse_edge_set": pulse_edge_set,
		"focus_nodes": _collect_focus_node_ids(), "continuous_edges": _telemetry.continuous_edges,
		"burst_pulses": _telemetry.burst_pulses, "recent_trail_keys": _telemetry.recent_trail_keys,
		"active_node_states": _telemetry.active_node_states, "breakpoint_set": breakpoint_node_ids,
		"interrupt_source_hints": _telemetry.interrupt_source_hints, "anim_clock": _telemetry.anim_clock,
		"pulse_wave": 0.5 + 0.5 * sin(_telemetry.anim_clock * 5.6), "live_mode": _read_only_topology,
		"is_vertical": _is_vertical_layout(), "is_bt": _is_bt_schema(),
		"show_all_labels": show_all_labels, "selected_node_id": _selection.primary_node_id,
		"selected_node_set": _selection.selected_lookup,
		"selected_edge_key": _selection.selected_edge_key, "hovered_node_id": _hovered_node_id,
		"hovered_port_node_id": _hovered_port_node_id, "hovered_edge_key": _hovered_edge_key,
		"hovered_portal_key": _hovered_portal_key, "connecting_from_id": _connecting_from_id,
		"connecting_mouse_world": _connecting_mouse_world, "snap_target_node_id": _snap_target_node_id,
		"snap_target_valid": _snap_target_valid, "hub_arrival_flash": _telemetry.hub_arrival_flash,
		"hub_id": str(_plan.get("hub_id", "")), "archetype": _plan.get("archetype", &"") as StringName,
	}

	draw_set_transform(-scroll_offset, 0.0, Vector2(zoom, zoom))
	CanvasPainter.draw_world_geometry(self, _palette, draw_ctx)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	CanvasPainter.draw_screen_labels(self, font, _palette, draw_ctx)
	if minimap_enabled:
		CanvasPainter.draw_minimap(self, _palette, _compute_world_bounds(), draw_ctx)
	if _selection.is_marquee_visible():
		CanvasPainter.draw_marquee_box(self, _palette, _selection.get_marquee_screen_rect(zoom, scroll_offset))


func _gui_input(event: InputEvent) -> void:
	_ensure_controllers()
	# 原位重命名浮层打开期间，拦截并忽略冒泡到父画布的键盘事件，避免编辑标题时误触画布快捷键
	if event is InputEventKey and _inline_renamer != null and _inline_renamer.is_active():
		return
	# 先安全收起原位改名框并抢占焦点，确保检视器 LineEdit 的 focus_exited 在构造交互快照前完成，杜绝吞点击
	if FlowEditorInput.is_canvas_focus_click(event):
		if _inline_renamer != null and _inline_renamer.is_active():
			_inline_renamer.commit_and_close()
		if is_inside_tree() and not has_focus():
			grab_focus()

	_ensure_routes_fresh()
	_input_ctrl.handle_gui_input(self, event, _selection, {
		"nodes": _nodes, "node_order": _node_draw_order,
		"routed_edges": _routed_edges, "edge_by_key": _edge_by_key,
		"read_only_topology": _read_only_topology, "live_mode": _live_mode,
		"is_vertical": _is_vertical_layout(), "is_bt": _is_bt_schema(),
		"snapping_enabled": snapping_enabled, "minimap_enabled": minimap_enabled,
		"ui_scale": ui_scale, "zoom": zoom, "scroll_offset": scroll_offset,
		"hovered_node_id": _hovered_node_id, "hovered_port_node_id": _hovered_port_node_id,
		"hovered_portal_key": _hovered_portal_key, "hovered_edge_key": _hovered_edge_key,
		"world_bounds": _compute_world_bounds() if minimap_enabled else Rect2(),
	})


func _on_selection_visual_changed(emit_inspect: bool) -> void:
	if emit_inspect and (_selection.primary_node_id != _last_inspected_node_id or _selection.selected_edge_key != _last_inspected_edge_key):
		_last_inspected_node_id = _selection.primary_node_id
		_last_inspected_edge_key = _selection.selected_edge_key
		node_inspected.emit(_last_inspected_node_id)
	queue_redraw()


func _on_input_portal_hub_jumped(hub_id: String) -> void:
	_selection.select_single_node(hub_id)
	_last_inspected_node_id = hub_id
	_telemetry.hub_arrival_flash = 0.85
	node_inspected.emit(hub_id)
	queue_redraw()


func _on_input_hover_changed(hn: String, hport: String, hp: String, he: String, tip: String) -> void:
	_hovered_node_id = hn
	_hovered_port_node_id = hport
	_hovered_portal_key = hp
	_hovered_edge_key = he
	tooltip_text = tip
	queue_redraw()


func _on_input_connection_preview(from_id: String, mouse_w: Vector2, snap_nid: String) -> void:
	_connecting_from_id = from_id
	_connecting_mouse_world = mouse_w
	_snap_target_node_id = snap_nid
	_snap_target_valid = _is_valid_edge_target(from_id, snap_nid) if not snap_nid.is_empty() else true
	_hovered_node_id = snap_nid
	if not from_id.is_empty():
		mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if (not snap_nid.is_empty() and not _snap_target_valid) else Control.CURSOR_CROSS
	queue_redraw()


func _on_input_edge_added(from_id: String, to_id: String) -> void:
	if not _is_valid_edge_target(from_id, to_id):
		return
	edge_connection_added.emit(from_id, to_id)


func _on_input_wire_dropped_on_blank(popup_pos: Vector2i, w_pt: Vector2, from_id: String) -> void:
	if _read_only_topology or from_id.is_empty() or not _nodes.has(from_id):
		_connecting_from_id = ""
		queue_redraw()
		return
	_connecting_from_id = from_id
	_connecting_mouse_world = w_pt
	_snap_target_node_id = ""
	_snap_target_valid = true
	queue_redraw()
	_open_quick_picker(popup_pos, w_pt, from_id, "")


func _open_quick_picker(popup_pos: Vector2i, w_pt: Vector2, from_id: String, split_to_id: String) -> void:
	if _read_only_topology:
		return
	var is_empty_gen: bool = (_graph_ref == null) or _graph_ref.is_empty_generic()
	var has_bt_root: bool = (_graph_ref != null and not _graph_ref.find_bt_root_id().is_empty())
	var from_title: String = str((_nodes[from_id] as Dictionary).get("title", from_id)) if _nodes.has(from_id) else from_id
	var to_title: String = str((_nodes[split_to_id] as Dictionary).get("title", split_to_id)) if _nodes.has(split_to_id) else split_to_id
	_quick_picker.open_picker(popup_pos, w_pt, _is_fsm_schema(), is_empty_gen, ui_scale, from_id, from_title, split_to_id, to_title, has_bt_root)


func _on_quick_picker_chosen(kind: String, w_pos: Vector2, from_id: String, split_to_id: String) -> void:
	_connecting_from_id = ""
	_snap_target_node_id = ""
	if not split_to_id.is_empty() and not from_id.is_empty():
		node_inserted_on_edge.emit(from_id, split_to_id, kind, w_pos)
	elif not from_id.is_empty():
		node_added_and_connected.emit(from_id, kind, w_pos)
	else:
		node_added_at.emit(kind, w_pos)
	queue_redraw()


func _on_quick_picker_closed(_committed: bool) -> void:
	if not _connecting_from_id.is_empty():
		_connecting_from_id = ""
		_snap_target_node_id = ""
		queue_redraw()


func _on_append_downstream_requested(from_id: String) -> void:
	if _read_only_topology or from_id.is_empty() or not _nodes.has(from_id):
		return
	var src_r: Rect2 = (_nodes[from_id] as Dictionary)["rect"] as Rect2
	var sibling_cnt: int = _graph_ref.find_outgoing_edges(from_id).size() if _graph_ref != null else 0
	var spawn_w: Vector2 = (
		Vector2(src_r.get_center().x + float(sibling_cnt) * 184.0, src_r.end.y + 68.0)
		if _is_vertical_layout()
		else Vector2(src_r.end.x + 84.0, src_r.get_center().y + float(sibling_cnt) * 56.0)
	)
	if _is_fsm_schema():
		node_added_and_connected.emit(from_id, "State", spawn_w)
		var next_sel: String = _selection.primary_node_id
		if not next_sel.is_empty() and next_sel != from_id:
			start_inline_rename(next_sel)
	else:
		_connecting_from_id = from_id
		_connecting_mouse_world = spawn_w
		_snap_target_node_id = ""
		queue_redraw()
		var s_pt: Vector2 = world_to_screen(spawn_w).clamp(Vector2(24.0, 24.0), (size - Vector2(48.0, 48.0)).max(Vector2(24.0, 24.0)))
		var pop_pos := Vector2i((get_screen_transform() * s_pt).round())
		_open_quick_picker(pop_pos, spawn_w, from_id, "")


func _on_input_group_drag_started() -> void:
	_drag_start_positions.clear()
	for nid: String in _selection.selected_node_ids:
		if _nodes.has(nid):
			_drag_start_positions[nid] = ((_nodes[nid] as Dictionary)["rect"] as Rect2).position
	if not _read_only_topology:
		before_graph_mutation.emit()


func _on_input_group_dragged_by(world_delta: Vector2) -> void:
	var any_moved: bool = false
	for nid_v: Variant in _drag_start_positions.keys():
		var nid: String = str(nid_v)
		if not _nodes.has(nid):
			continue
		var start_p: Vector2 = _drag_start_positions[nid] as Vector2
		var next_pos: Vector2 = start_p + world_delta
		var nd_drag: Dictionary = _nodes[nid] as Dictionary
		var r_drag: Rect2 = nd_drag["rect"] as Rect2
		if not r_drag.position.is_equal_approx(next_pos):
			r_drag.position = next_pos
			nd_drag["rect"] = r_drag
			any_moved = true
	if any_moved:
		_routes_dirty = true
		queue_redraw()


func _on_input_group_drag_finished(moved: bool) -> void:
	_drag_start_positions.clear()
	if moved:
		if not _read_only_topology and _graph_ref != null:
			sync_positions_to_model(_graph_ref)
			if _is_bt_schema():
				if _graph_ref.reorder_bt_children_by_position(_is_vertical_layout()):
					_plan = MermaidLayout.analyze_topology(_graph_ref)
		_routes_dirty = false
		_rebuild_routes()
		graph_mutated.emit()
	queue_redraw()


func _emit_nodes_delete(node_ids: Array[String]) -> void:
	if node_ids.is_empty():
		return
	if not nodes_deleted_requested.get_connections().is_empty():
		nodes_deleted_requested.emit(node_ids)
	elif node_ids.size() == 1:
		node_deleted_requested.emit(node_ids[0])


func _emit_nodes_duplicate(node_ids: Array[String]) -> void:
	if node_ids.is_empty():
		return
	if not nodes_duplicated_requested.get_connections().is_empty():
		nodes_duplicated_requested.emit(node_ids)
	elif node_ids.size() == 1:
		node_duplicated_requested.emit(node_ids[0])


func _emit_breakpoints_toggle(node_ids: Array[String]) -> void:
	if node_ids.is_empty():
		return
	if not breakpoints_toggled_requested.get_connections().is_empty():
		breakpoints_toggled_requested.emit(node_ids)
	elif node_ids.size() == 1:
		breakpoint_toggled.emit(node_ids[0])


func _on_input_node_context_menu(popup_pos: Vector2i, hit_nid: String) -> void:
	if not _nodes.has(hit_nid):
		return
	var nd: Dictionary = _nodes[hit_nid] as Dictionary
	var can_emit: bool = CanvasGeometry.can_node_emit_edge(str(nd.get("kind", "State")), _is_bt_schema())
	_context_menu.popup_for_node(
		popup_pos, nd, _is_fsm_schema(),
		_read_only_topology, _live_mode, breakpoint_node_ids.has(hit_nid), ui_scale, can_emit,
		_selection.selected_node_ids
	)


func _on_input_edge_context_menu(popup_pos: Vector2i, w_pt: Vector2, ekey: String) -> void:
	if not _edge_by_key.has(ekey):
		return
	var ed: Dictionary = _edge_by_key[ekey] as Dictionary
	_context_menu.popup_for_edge(popup_pos, w_pt, str(ed["from"]), str(ed["to"]), _is_fsm_schema(), ui_scale)


func _on_ctx_edge_inspect(from_id: String, to_id: String) -> void:
	var inspect_nid: String = from_id if (from_id != "*" and _nodes.has(from_id)) else to_id
	var ekey: String = "%s->%s" % [from_id, to_id]
	if _nodes.has(inspect_nid):
		_selection.select_single_node(inspect_nid)
		_last_inspected_node_id = inspect_nid
	_selection.select_edge(ekey)
	_last_inspected_edge_key = ekey
	if _nodes.has(inspect_nid):
		node_inspected.emit(inspect_nid)
	queue_redraw()


func _on_ctx_edge_insert_node(popup_pos: Vector2i, w_pt: Vector2, from_id: String, to_id: String) -> void:
	_open_quick_picker(popup_pos, w_pt, from_id, to_id)


func _on_input_blank_context_menu(popup_pos: Vector2i, world_pt: Vector2) -> void:
	_context_menu.popup_for_blank(popup_pos, world_pt, _read_only_topology, ui_scale)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _read_only_topology or not (data is Dictionary):
		return false
	var d: Dictionary = data as Dictionary
	if not bool(d.get("flow_graph_palette_item", false)):
		return false
	var drag_kind: String = str(d.get("kind", ""))
	var drag_preset: String = str(d.get("preset", ""))
	var is_empty_gen: bool = (_graph_ref == null) or (_graph_ref.nodes.is_empty() and _graph_ref.schema == MermaidGraphModel.SCHEMA_GENERIC)
	if not is_empty_gen:
		if _is_fsm_schema() and drag_kind != "State":
			return false
		if _is_bt_schema() and drag_kind == "State":
			return false

	_ensure_routes_fresh()
	var w_pt: Vector2 = screen_to_world(at_position)
	var next_snap_nid: String = ""
	var next_edge_key: String = ""

	if drag_preset != "interrupt":
		var hit_nid: String = CanvasGeometry.hit_test_node(w_pt, _nodes, _node_draw_order)
		if not hit_nid.is_empty():
			var src_kind: String = str((_nodes[hit_nid] as Dictionary).get("kind", "State"))
			if CanvasGeometry.can_node_emit_edge(src_kind, _is_bt_schema()):
				next_snap_nid = hit_nid
		elif CanvasGeometry.can_node_emit_edge(drag_kind, _is_bt_schema()):
			var hit_ed: String = CanvasGeometry.hit_test_edge(w_pt, _routed_edges, zoom)
			if not hit_ed.is_empty() and _edge_by_key.has(hit_ed):
				var ed_rec: Dictionary = _edge_by_key[hit_ed] as Dictionary
				if str(ed_rec.get("from", "")) != "*":
					next_edge_key = hit_ed

	if _snap_target_node_id != next_snap_nid or _hovered_edge_key != next_edge_key:
		_snap_target_node_id = next_snap_nid
		_snap_target_valid = true
		_hovered_edge_key = next_edge_key
		queue_redraw()
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _read_only_topology or not (data is Dictionary):
		return
	var d: Dictionary = data as Dictionary
	if not bool(d.get("flow_graph_palette_item", false)):
		return
	var drag_kind: String = str(d.get("kind", "State"))
	var drag_preset: String = str(d.get("preset", ""))
	var w_pt: Vector2 = screen_to_world(at_position)
	var target_nid: String = _snap_target_node_id
	var split_from: String = ""
	var split_to: String = ""
	if target_nid.is_empty() and not _hovered_edge_key.is_empty() and _edge_by_key.has(_hovered_edge_key):
		var ed_rec: Dictionary = _edge_by_key[_hovered_edge_key] as Dictionary
		split_from = str(ed_rec.get("from", ""))
		split_to = str(ed_rec.get("to", ""))
	_snap_target_node_id = ""
	_hovered_edge_key = ""
	grab_focus()
	palette_item_dropped.emit(drag_kind, drag_preset, w_pt, target_nid, split_from, split_to)
	queue_redraw()


func _on_ctx_direction_toggle() -> void:
	if not direction_toggle_requested.get_connections().is_empty():
		direction_toggle_requested.emit()
		return
	if _read_only_topology or _graph_ref == null:
		return
	before_graph_mutation.emit()
	_graph_ref.direction = &"TD" if (_graph_ref.direction == &"LR" or _graph_ref.direction == &"RL") else &"LR"
	render_graph(_graph_ref, _live_mode, MermaidLayout.apply_layout(_graph_ref, true), _read_only_topology)
	fit_graph_view()
	graph_mutated.emit()


func _on_ctx_auto_layout() -> void:
	if not auto_layout_requested.get_connections().is_empty():
		auto_layout_requested.emit()
		return
	if _read_only_topology or _graph_ref == null or _graph_ref.nodes.is_empty():
		return
	before_graph_mutation.emit()
	render_graph(_graph_ref, _live_mode, MermaidLayout.apply_layout(_graph_ref, true), _read_only_topology)
	fit_graph_view()
	graph_mutated.emit()


func _sync_inline_renamer_rect() -> void:
	if _inline_renamer != null and _inline_renamer.is_active():
		var rn_id: String = _inline_renamer.get_editing_node_id()
		if _nodes.has(rn_id):
			_inline_renamer.sync_transform((_nodes[rn_id] as Dictionary)["rect"] as Rect2, zoom, scroll_offset)


func _is_vertical_layout() -> bool:
	return _graph_ref != null and (_graph_ref.direction == &"TD" or _graph_ref.direction == &"TB")


func _is_bt_schema() -> bool:
	return _graph_ref != null and _graph_ref.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT


func _is_fsm_schema() -> bool:
	return _graph_ref != null and _graph_ref.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM


func _is_valid_edge_target(from_id: String, to_id: String) -> bool:
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id or not _nodes.has(from_id) or not _nodes.has(to_id):
		return false
	var is_bt: bool = _is_bt_schema()
	var src_kind: String = str((_nodes[from_id] as Dictionary).get("kind", "State"))
	var dst_kind: String = str((_nodes[to_id] as Dictionary).get("kind", "State"))
	if not CanvasGeometry.can_node_emit_edge(src_kind, is_bt) or not CanvasGeometry.can_node_accept_edge(dst_kind, is_bt):
		return false
	if is_bt and _graph_ref != null:
		# 行为树禁止反向成环（若 from_id 可由 to_id 顺向到达，则连线会制造死循环）
		if _is_reachable_in_graph(to_id, from_id):
			return false
	return true


func _is_reachable_in_graph(start_id: String, goal_id: String) -> bool:
	if _graph_ref == null:
		return false
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == goal_id:
			return true
		for ed: Dictionary in _graph_ref.edges:
			if str(ed.get("from", "")) == cur:
				var nxt: String = str(ed.get("to", ""))
				if not nxt.is_empty() and not visited.has(nxt):
					visited[nxt] = true
					queue.append(nxt)
	return false


func world_to_screen(w: Vector2) -> Vector2:
	return w * zoom - scroll_offset


func screen_to_world(s: Vector2) -> Vector2:
	return (s + scroll_offset) / maxf(zoom, 0.15)


func _zoom_at_screen_point(anchor_screen: Vector2, factor: float) -> void:
	var before_world: Vector2 = screen_to_world(anchor_screen)
	zoom = zoom * factor
	scroll_offset = before_world * zoom - anchor_screen


func _compute_world_bounds() -> Rect2:
	return CanvasGeometry.compute_world_bounds(_nodes, _node_draw_order, _routed_edges, _has_any_state_zone, _any_zone_rect)


func _collect_focus_node_ids() -> Dictionary:
	var focus: Dictionary = {}
	var arch: StringName = _plan.get("archetype", &"") as StringName
	if arch != MermaidMetrics.ARCHETYPE_BT_TREE:
		for k: Variant in _telemetry.active_node_states.keys():
			var nid: String = str(k)
			if str((_telemetry.active_node_states[nid] as Dictionary).get("state", "RUNNING")) == "RUNNING":
				focus[nid] = true
	for sel_nid: String in _selection.selected_node_ids:
		focus[sel_nid] = true
	if not _hovered_node_id.is_empty():
		focus[_hovered_node_id] = true
	if focus.is_empty() and _telemetry.active_node_states.is_empty() and arch != MermaidMetrics.ARCHETYPE_BT_TREE:
		var hub_id: String = str(_plan.get("hub_id", ""))
		if not hub_id.is_empty():
			focus[hub_id] = true
	return focus

#endregion
