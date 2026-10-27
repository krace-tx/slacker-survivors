@tool
extends Control

## Mermaid 多态轻量 2D 矢量流转画布门面（2D Vector Graph Canvas Facade）。[br]
##
## 负责视口状态与子模块装配协调；几何计算、边路由、运行期脉冲状态、指针/快捷键交互、右键菜单与双空间绘制分别委派至 [`CanvasGeometry`](canvas_geometry.gd)、[`CanvasEdgeRouter`](canvas_edge_router.gd)、[`CanvasTelemetryState`](canvas_telemetry_state.gd)、[`CanvasInputController`](canvas_input_controller.gd)、[`CanvasContextMenu`](canvas_context_menu.gd) 与 [`CanvasPainter`](canvas_painter.gd)。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const CanvasEdgeRouter = preload(FlowGraphContracts.SCRIPT_CANVAS_EDGE_ROUTER)
const CanvasPainter = preload(FlowGraphContracts.SCRIPT_CANVAS_PAINTER)
const CanvasContextMenu = preload(FlowGraphContracts.SCRIPT_CANVAS_CONTEXT_MENU)
const CanvasInputController = preload(FlowGraphContracts.SCRIPT_CANVAS_INPUT_CTRL)
const CanvasTelemetryState = preload(FlowGraphContracts.SCRIPT_CANVAS_TELEMETRY)


#region 信号定义与公开属性

signal graph_mutated()
signal before_graph_mutation()
signal edge_connection_added(from_id: String, to_id: String)
signal edge_connection_removed(from_id: String, to_id: String)
signal node_force_requested(node_id: String, params: Dictionary)
signal node_inspected(node_id: String)
signal view_zoom_changed(new_zoom: float)

signal node_added_at(kind: String, world_pos: Vector2)
signal node_deleted_requested(node_id: String)
signal node_duplicated_requested(node_id: String)
signal initial_node_set_requested(node_id: String)
signal any_state_edge_toggled(node_id: String)
signal breakpoint_toggled(node_id: String)
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
			view_zoom_changed.emit(zoom)
			queue_redraw()

var scroll_offset: Vector2 = Vector2.ZERO:
	set(v):
		if scroll_offset != v:
			scroll_offset = v
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
var _input_ctrl: CanvasInputController = null
var _telemetry: CanvasTelemetryState = CanvasTelemetryState.new()
var _graph_ref: MermaidGraphModel = null
var _plan: Dictionary = {}
var _live_mode: bool = false
var _read_only_topology: bool = false

var _nodes: Dictionary = {}
var _node_draw_order: Array[String] = []
var _routed_edges: Array[Dictionary] = []
var _edge_by_key: Dictionary = {}
var _has_any_state_zone: bool = false
var _any_zone_rect: Rect2 = Rect2()
var _any_origin_boxes: Array[Rect2] = []

var _selected_node_id: String = ""
var _hovered_node_id: String = ""
var _hovered_portal_key: String = ""
var _hovered_edge_key: String = ""
var _connecting_from_id: String = ""
var _connecting_mouse_world: Vector2 = Vector2.ZERO

#endregion


#region 生命周期与控制器接线

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
		_context_menu.node_add_requested.connect(func(k: String, wpos: Vector2) -> void: node_added_at.emit(k, wpos))
		_context_menu.node_delete_requested.connect(func(nid: String) -> void: node_deleted_requested.emit(nid))
		_context_menu.node_duplicate_requested.connect(func(nid: String) -> void: node_duplicated_requested.emit(nid))
		_context_menu.initial_node_set_requested.connect(func(nid: String) -> void: initial_node_set_requested.emit(nid))
		_context_menu.any_state_edge_toggled.connect(func(nid: String) -> void: any_state_edge_toggled.emit(nid))
		_context_menu.breakpoint_toggled.connect(func(nid: String) -> void: breakpoint_toggled.emit(nid))
		_context_menu.sub_graph_open_requested.connect(func(sp: String, nid: String) -> void: sub_graph_open_requested.emit(sp, nid))
		_context_menu.node_force_requested.connect(func(nid: String, p: Dictionary) -> void: node_force_requested.emit(nid, p))
		_context_menu.direction_toggle_requested.connect(_on_ctx_direction_toggle)
		_context_menu.auto_layout_requested.connect(_on_ctx_auto_layout)

	if _input_ctrl == null:
		_input_ctrl = CanvasInputController.new()
		_input_ctrl.scroll_delta_requested.connect(func(d: Vector2) -> void: scroll_offset += d)
		_input_ctrl.zoom_at_requested.connect(_zoom_at_screen_point)
		_input_ctrl.minimap_pan_requested.connect(func(tw: Vector2) -> void: scroll_offset = tw * zoom - size * 0.5)
		_input_ctrl.node_selected.connect(_on_input_node_selected)
		_input_ctrl.portal_hub_jumped.connect(_on_input_portal_hub_jumped)
		_input_ctrl.hover_state_changed.connect(_on_input_hover_changed)
		_input_ctrl.connection_preview_changed.connect(_on_input_connection_preview)
		_input_ctrl.edge_connection_added.connect(func(f: String, t: String) -> void: edge_connection_added.emit(f, t))
		_input_ctrl.edge_connection_removed.connect(func(f: String, t: String) -> void: edge_connection_removed.emit(f, t))
		_input_ctrl.node_drag_started.connect(func() -> void: before_graph_mutation.emit())
		_input_ctrl.node_dragged_to.connect(_on_input_node_dragged_to)
		_input_ctrl.node_drag_finished.connect(_on_input_node_drag_finished)
		_input_ctrl.node_force_requested.connect(func(nid: String, p: Dictionary) -> void: node_force_requested.emit(nid, p))
		_input_ctrl.sub_graph_open_requested.connect(func(sp: String, nid: String) -> void: sub_graph_open_requested.emit(sp, nid))
		_input_ctrl.node_context_menu_requested.connect(_on_input_node_context_menu)
		_input_ctrl.blank_context_menu_requested.connect(_on_input_blank_context_menu)
		_input_ctrl.node_deleted_requested.connect(func(nid: String) -> void: node_deleted_requested.emit(nid))
		_input_ctrl.node_duplicated_requested.connect(func(nid: String) -> void: node_duplicated_requested.emit(nid))
		_input_ctrl.undo_requested.connect(func() -> void: undo_requested.emit())
		_input_ctrl.redo_requested.connect(func() -> void: redo_requested.emit())


func _process(delta: float) -> void:
	if _telemetry.tick(delta):
		queue_redraw()


func apply_locale() -> void:
	if _context_menu != null:
		_context_menu.apply_locale()
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
	_graph_ref = graph
	_live_mode = live_mode
	_read_only_topology = live_mode or read_only_topology
	_nodes.clear()
	_node_draw_order.clear()
	_routed_edges.clear()
	_edge_by_key.clear()
	_telemetry.clear()
	_connecting_from_id = ""
	if _input_ctrl != null:
		_input_ctrl.reset_interaction_state()

	if graph == null or graph.nodes.is_empty():
		_plan = {}
		_has_any_state_zone = false
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

	if not _selected_node_id.is_empty() and not _nodes.has(_selected_node_id):
		_selected_node_id = ""
	if not _hovered_node_id.is_empty() and not _nodes.has(_hovered_node_id):
		_hovered_node_id = ""

	_rebuild_routes()
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
	var out: Array[Dictionary] = []
	for ed: Dictionary in _routed_edges:
		if int(ed.get("route", CanvasGeometry.ROUTE_STRAIGHT)) != CanvasGeometry.ROUTE_ANY_BUS:
			out.append({
				"from_node": StringName(str(ed["from"])), "from_port": 0,
				"to_node": StringName(str(ed["to"])), "to_port": 0,
			})
	return out


func fit_graph_view() -> void:
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


func select_and_focus_node(node_id: String, pan_to_center: bool = false) -> void:
	if node_id.is_empty() or not _nodes.has(node_id):
		_selected_node_id = ""
		queue_redraw()
		return
	_selected_node_id = node_id
	if pan_to_center:
		var s: float = maxf(ui_scale, 0.75)
		var view_sz: Vector2 = size if size.x > 80.0 * s else Vector2(960.0 * s, 600.0 * s)
		var nr: Rect2 = (_nodes[node_id] as Dictionary)["rect"] as Rect2
		scroll_offset = nr.get_center() * zoom - view_sz * 0.5
	queue_redraw()


func get_selected_node_id() -> String:
	return _selected_node_id


func get_selected_node_params() -> Dictionary:
	if not _selected_node_id.is_empty() and _nodes.has(_selected_node_id):
		return (_nodes[_selected_node_id] as Dictionary).get("params", {}) as Dictionary
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
	_rebuild_routes()
	queue_redraw()

#endregion


#region 路由、绘制编排与交互回调

func _rebuild_routes() -> void:
	var route_res: Dictionary = CanvasEdgeRouter.build_routes(_graph_ref, _plan, _nodes, _node_draw_order)
	_routed_edges = route_res["routed_edges"] as Array[Dictionary]
	_edge_by_key = route_res["edge_by_key"] as Dictionary
	_has_any_state_zone = bool(route_res["has_any_state_zone"])
	_any_zone_rect = route_res["any_zone_rect"] as Rect2
	_any_origin_boxes = route_res["any_origin_boxes"] as Array[Rect2]


func _draw() -> void:
	if _palette == null or _palette.is_stale():
		_palette = CanvasThemePalette.new()

	CanvasPainter.draw_backdrop_and_grid(self, scroll_offset, zoom, _palette)
	if _nodes.is_empty():
		CanvasPainter.draw_empty_placeholder(self, ui_scale, _palette)
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
		"show_all_labels": show_all_labels, "selected_node_id": _selected_node_id,
		"hovered_node_id": _hovered_node_id, "hovered_edge_key": _hovered_edge_key,
		"hovered_portal_key": _hovered_portal_key, "connecting_from_id": _connecting_from_id,
		"connecting_mouse_world": _connecting_mouse_world, "hub_arrival_flash": _telemetry.hub_arrival_flash,
		"hub_id": str(_plan.get("hub_id", "")), "archetype": _plan.get("archetype", &"") as StringName,
	}

	draw_set_transform(-scroll_offset, 0.0, Vector2(zoom, zoom))
	CanvasPainter.draw_world_geometry(self, _palette, draw_ctx)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	CanvasPainter.draw_screen_labels(self, font, _palette, draw_ctx)
	if minimap_enabled:
		CanvasPainter.draw_minimap(self, _palette, _compute_world_bounds(), draw_ctx)


func _gui_input(event: InputEvent) -> void:
	_ensure_controllers()
	_input_ctrl.handle_gui_input(self, event, {
		"nodes": _nodes, "node_order": _node_draw_order,
		"routed_edges": _routed_edges, "edge_by_key": _edge_by_key,
		"read_only_topology": _read_only_topology, "live_mode": _live_mode,
		"snapping_enabled": snapping_enabled, "minimap_enabled": minimap_enabled,
		"ui_scale": ui_scale, "zoom": zoom, "scroll_offset": scroll_offset,
		"selected_node_id": _selected_node_id, "hovered_node_id": _hovered_node_id,
		"hovered_portal_key": _hovered_portal_key, "hovered_edge_key": _hovered_edge_key,
		"world_bounds": _compute_world_bounds() if minimap_enabled else Rect2(),
	})


func _on_input_node_selected(nid: String, emit_inspect: bool) -> void:
	_selected_node_id = nid
	if emit_inspect:
		node_inspected.emit(nid)
	queue_redraw()


func _on_input_portal_hub_jumped(hub_id: String) -> void:
	_selected_node_id = hub_id
	_telemetry.hub_arrival_flash = 0.85
	node_inspected.emit(hub_id)
	queue_redraw()


func _on_input_hover_changed(hn: String, hp: String, he: String, tip: String) -> void:
	_hovered_node_id = hn
	_hovered_portal_key = hp
	_hovered_edge_key = he
	tooltip_text = tip
	queue_redraw()


func _on_input_connection_preview(from_id: String, mouse_w: Vector2, hover_nid: String) -> void:
	_connecting_from_id = from_id
	_connecting_mouse_world = mouse_w
	_hovered_node_id = hover_nid
	queue_redraw()


func _on_input_node_dragged_to(nid: String, next_pos: Vector2) -> void:
	if not _nodes.has(nid):
		return
	var nd_drag: Dictionary = _nodes[nid] as Dictionary
	var r_drag: Rect2 = nd_drag["rect"] as Rect2
	r_drag.position = next_pos
	nd_drag["rect"] = r_drag
	_rebuild_routes()
	queue_redraw()


func _on_input_node_drag_finished(moved: bool) -> void:
	if moved:
		if not _read_only_topology and _graph_ref != null:
			sync_positions_to_model(_graph_ref)
			if _graph_ref.resolve_effective_schema() == MermaidGraphModel.SCHEMA_BT:
				var is_vert: bool = (_graph_ref.direction == &"TD" or _graph_ref.direction == &"TB")
				if _graph_ref.reorder_bt_children_by_position(is_vert):
					_plan = MermaidLayout.analyze_topology(_graph_ref)
					_rebuild_routes()
		graph_mutated.emit()
	queue_redraw()


func _on_input_node_context_menu(popup_pos: Vector2i, hit_nid: String) -> void:
	if not _nodes.has(hit_nid):
		return
	var is_fsm_n: bool = _graph_ref != null and _graph_ref.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM
	_context_menu.popup_for_node(
		popup_pos, _nodes[hit_nid] as Dictionary, is_fsm_n,
		_read_only_topology, _live_mode, breakpoint_node_ids.has(hit_nid), ui_scale
	)


func _on_input_blank_context_menu(popup_pos: Vector2i, world_pt: Vector2) -> void:
	var eff_schema: StringName = _graph_ref.resolve_effective_schema() if _graph_ref != null else MermaidGraphModel.SCHEMA_GENERIC
	var is_empty_gen: bool = (_graph_ref == null) or (_graph_ref.nodes.is_empty() and _graph_ref.schema == MermaidGraphModel.SCHEMA_GENERIC)
	_context_menu.popup_for_blank(popup_pos, world_pt, eff_schema == MermaidGraphModel.SCHEMA_FSM, is_empty_gen, ui_scale)


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
	if not _selected_node_id.is_empty():
		focus[_selected_node_id] = true
	if not _hovered_node_id.is_empty():
		focus[_hovered_node_id] = true
	if focus.is_empty() and _telemetry.active_node_states.is_empty() and arch != MermaidMetrics.ARCHETYPE_BT_TREE:
		var hub_id: String = str(_plan.get("hub_id", ""))
		if not hub_id.is_empty():
			focus[hub_id] = true
	return focus

#endregion
