@tool
extends RefCounted

## 双坐标空间 2D 矢量绘制引擎门面（Dual-Space 2D Vector Painter）。[br]
##
## 负责背景网格、世界空间几何渲染（总线、脉冲彗星、胶囊卡片、断点红点、子图嵌套角标）；1:1 屏幕像素文字、BT `#1/#2` 优先级角标、防碰撞胶囊与小地图委派至 [`CanvasOverlayPainter`](canvas_overlay_painter.gd)。

const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const CanvasOverlayPainter = preload(FlowGraphContracts.SCRIPT_CANVAS_OVERLAY_PAINTER)

const GRID_MINOR: float = 16.0
const GRID_MAJOR: float = 80.0


#region 背景网格与空态占位

static func draw_backdrop_and_grid(canvas: Control, scroll_offset: Vector2, zoom: float, palette: CanvasThemePalette = null) -> void:
	var pal: CanvasThemePalette = palette if palette != null else CanvasThemePalette.new()
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), pal.canvas_bg, true)

	var minor_step: float = GRID_MINOR * zoom
	var major_step: float = GRID_MAJOR * zoom

	if minor_step >= 9.0:
		var col_minor: Color = pal.grid_minor
		var sx: float = fposmod(-scroll_offset.x, minor_step)
		while sx < canvas.size.x:
			canvas.draw_line(Vector2(sx, 0.0), Vector2(sx, canvas.size.y), col_minor, 1.0)
			sx += minor_step
		var sy: float = fposmod(-scroll_offset.y, minor_step)
		while sy < canvas.size.y:
			canvas.draw_line(Vector2(0.0, sy), Vector2(canvas.size.x, sy), col_minor, 1.0)
			sy += minor_step

	if major_step >= 18.0:
		var col_major: Color = pal.grid_major
		var mx: float = fposmod(-scroll_offset.x, major_step)
		while mx < canvas.size.x:
			canvas.draw_line(Vector2(mx, 0.0), Vector2(mx, canvas.size.y), col_major, 1.0)
			mx += major_step
		var my: float = fposmod(-scroll_offset.y, major_step)
		while my < canvas.size.y:
			canvas.draw_line(Vector2(0.0, my), Vector2(canvas.size.x, my), col_major, 1.0)
			my += major_step


static func draw_empty_placeholder(canvas: Control, ui_scale: float = 1.0, palette: CanvasThemePalette = null) -> void:
	var pal: CanvasThemePalette = palette if palette != null else CanvasThemePalette.new()
	var font: Font = canvas.get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return
	var s: float = maxf(ui_scale, 0.75)
	var title_fs: int = maxi(13, roundi(15.0 * s))
	var sub_fs: int = maxi(11, roundi(12.5 * s))
	var title_msg: String = FlowEditorI18n.t(&"canvas.empty_title")
	var sub_msg: String = FlowEditorI18n.t(&"canvas.empty_sub")
	var w1: float = font.get_string_size(title_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs).x
	var w2: float = font.get_string_size(sub_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs).x
	var cy: float = canvas.size.y * 0.48
	canvas.draw_string(font, Vector2((canvas.size.x - w1) * 0.5, cy), title_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, pal.text_dim)
	canvas.draw_string(font, Vector2((canvas.size.x - w2) * 0.5, cy + roundf(28.0 * s)), sub_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs, pal.text_faint)

#endregion


#region 世界空间几何层绘制

static func draw_world_geometry(
	canvas: Control,
	palette: CanvasThemePalette,
	ctx: Dictionary
) -> void:
	var nodes: Dictionary = ctx["nodes"] as Dictionary
	var node_order: Array[String] = ctx["node_order"] as Array[String]
	var routed_edges: Array[Dictionary] = ctx["routed_edges"] as Array[Dictionary]
	var edge_by_key: Dictionary = ctx["edge_by_key"] as Dictionary
	var active_edge_set: Dictionary = ctx["active_edge_set"] as Dictionary
	var pulse_edge_set: Dictionary = ctx["pulse_edge_set"] as Dictionary
	var focus_nodes: Dictionary = ctx["focus_nodes"] as Dictionary
	var continuous_edges: Array[Array] = ctx["continuous_edges"] as Array[Array]
	var burst_pulses: Array[Dictionary] = ctx["burst_pulses"] as Array[Dictionary]
	var recent_trail_keys: Array[String] = ctx["recent_trail_keys"] as Array[String]
	var active_node_states: Dictionary = ctx["active_node_states"] as Dictionary
	var breakpoint_set: Dictionary = ctx.get("breakpoint_set", {}) as Dictionary
	var anim_clock: float = float(ctx["anim_clock"])
	var pulse_wave: float = float(ctx["pulse_wave"])
	var live_mode: bool = bool(ctx["live_mode"])
	var is_vertical: bool = bool(ctx.get("is_vertical", false))
	var is_bt: bool = bool(ctx.get("is_bt", false))
	var selected_node_id: String = str(ctx["selected_node_id"])
	var selected_node_set: Dictionary = ctx.get("selected_node_set", {}) as Dictionary
	var selected_edge_key: String = str(ctx.get("selected_edge_key", ""))
	var hovered_node_id: String = str(ctx["hovered_node_id"])
	var hovered_port_node_id: String = str(ctx.get("hovered_port_node_id", ""))
	var hovered_edge_key: String = str(ctx["hovered_edge_key"])
	var hovered_portal_key: String = str(ctx["hovered_portal_key"])
	var conn_from: String = str(ctx["connecting_from_id"])
	var snap_target_id: String = str(ctx.get("snap_target_node_id", ""))
	var snap_target_valid: bool = bool(ctx.get("snap_target_valid", true))

	if bool(ctx["has_any_state_zone"]):
		var any_zone_rect: Rect2 = ctx["any_zone_rect"] as Rect2
		var any_origin_boxes: Array[Rect2] = ctx["any_origin_boxes"] as Array[Rect2]
		canvas.draw_style_box(palette.sb_any_zone, any_zone_rect)
		for abox: Rect2 in any_origin_boxes:
			canvas.draw_style_box(palette.sb_any_badge, abox)
			canvas.draw_circle(Vector2(abox.position.x + 13.0, abox.get_center().y), 3.0, palette.interrupt)

	var arch_name: StringName = ctx.get("archetype", &"") as StringName
	for z_layer: int in range(3):
		for ed: Dictionary in routed_edges:
			var ek: String = str(ed["key"])
			var layer_of_ed: int = _classify_edge_z_layer(ed, ek, active_node_states, focus_nodes, active_edge_set, pulse_edge_set, recent_trail_keys, hovered_edge_key, hovered_portal_key, selected_edge_key)
			if layer_of_ed == z_layer:
				_draw_single_edge(canvas, palette, ed, arch_name, active_node_states, focus_nodes, active_edge_set, pulse_edge_set, recent_trail_keys, hovered_edge_key, hovered_portal_key, selected_edge_key)

	for pair: Array in continuous_edges:
		var ckey: String = "%s->%s" % [str(pair[0]), str(pair[1])]
		if not edge_by_key.has(ckey):
			continue
		var pts_c: PackedVector2Array = (edge_by_key[ckey] as Dictionary)["pts"] as PackedVector2Array
		if pts_c.size() < 2:
			continue
		canvas.draw_polyline(pts_c, Color(palette.accent, 0.14), 6.0, true)
		canvas.draw_polyline(pts_c, palette.edge_active, 2.0, true)
		for orb_i: int in range(2):
			var phase: float = fmod(anim_clock * 1.15 + float(orb_i) * 0.5, 1.0)
			var opos: Vector2 = CanvasGeometry.interpolate_polyline(pts_c, phase)
			canvas.draw_circle(opos, 4.6, Color(palette.accent, 0.2))
			canvas.draw_circle(opos, 2.2, palette.accent.lerp(Color.WHITE, 0.55))

	for pulse: Dictionary in burst_pulses:
		var pkey: String = str(pulse["key"])
		var pts_p: PackedVector2Array = pulse.get("custom_pts", PackedVector2Array()) as PackedVector2Array
		if pts_p.is_empty() and edge_by_key.has(pkey):
			pts_p = (edge_by_key[pkey] as Dictionary)["pts"] as PackedVector2Array
		if pts_p.size() < 2:
			continue
		var t_val: float = clampf(float(pulse.get("t", 0.0)), 0.0, 1.0)
		var fade: float = 1.0 - t_val * 0.45
		var segs: int = 5
		var tail_span: float = 0.28
		for s: int in range(segs):
			var r0: float = maxf(0.0, t_val - tail_span * float(segs - s) / float(segs))
			var r1: float = maxf(0.0, t_val - tail_span * float(segs - s - 1) / float(segs))
			if r1 <= r0:
				continue
			var sub_p: PackedVector2Array = CanvasGeometry.slice_polyline(pts_p, r0, r1)
			if sub_p.size() >= 2:
				var ratio_s: float = float(s + 1) / float(segs)
				canvas.draw_polyline(sub_p, Color(palette.warning, 0.85 * ratio_s * fade), lerpf(1.2, 3.2, ratio_s), true)
		var hpos: Vector2 = CanvasGeometry.interpolate_polyline(pts_p, t_val)
		canvas.draw_circle(hpos, 6.0, Color(palette.warning, 0.22 * fade))
		canvas.draw_circle(hpos, 2.8, Color(palette.warning.lerp(Color.WHITE, 0.6), 0.98 * fade))

	var hub_flash: float = float(ctx["hub_arrival_flash"])
	var hub_id: String = str(ctx["hub_id"])
	if hub_flash > 0.0 and nodes.has(hub_id):
		var hr: Rect2 = (nodes[hub_id] as Dictionary)["rect"] as Rect2
		var grow_amt: float = lerpf(3.0, 10.0, 1.0 - hub_flash)
		var flash_sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(0, 0, 0, 0), Color(palette.accent, hub_flash * 0.7), 2, 6)
		canvas.draw_style_box(flash_sb, hr.grow(grow_amt))

	for nid: String in node_order:
		_draw_node_capsule(
			canvas, palette, nodes[nid] as Dictionary, active_node_states,
			selected_node_id, selected_node_set, hovered_node_id, hovered_port_node_id,
			conn_from, snap_target_id, snap_target_valid,
			live_mode, is_vertical, is_bt, pulse_wave, breakpoint_set.has(nid)
		)

	if not conn_from.is_empty() and nodes.has(conn_from):
		var src_r: Rect2 = (nodes[conn_from] as Dictionary)["rect"] as Rect2
		var conn_w: Vector2 = ctx["connecting_mouse_world"] as Vector2
		var p_drag_start: Vector2 = CanvasGeometry.get_output_port_world(src_r, is_vertical)
		var p_drag_end: Vector2 = conn_w
		var wire_col: Color = palette.edge_active
		if not snap_target_id.is_empty() and nodes.has(snap_target_id):
			if snap_target_valid:
				var dst_r: Rect2 = (nodes[snap_target_id] as Dictionary)["rect"] as Rect2
				p_drag_end = CanvasGeometry.get_input_port_world(dst_r, is_vertical)
				wire_col = palette.success.lerp(palette.accent, 0.35)
			else:
				wire_col = palette.error
		var preview_pts: PackedVector2Array = CanvasGeometry.build_preview_wire_points(p_drag_start, p_drag_end, is_vertical)
		canvas.draw_polyline(preview_pts, Color(wire_col, 0.20), 6.0, true)
		canvas.draw_polyline(preview_pts, wire_col, 2.2, true)
		_draw_endpoint_chevron(canvas, preview_pts, wire_col)
		canvas.draw_circle(p_drag_start, 4.2, wire_col)
		if snap_target_id.is_empty() or not snap_target_valid:
			canvas.draw_circle(p_drag_end, 4.5, Color(wire_col, 0.28))
			canvas.draw_circle(p_drag_end, 2.6, wire_col)


static func _classify_edge_z_layer(
	ed: Dictionary,
	key: String,
	active_node_states: Dictionary,
	focus_nodes: Dictionary,
	active_set: Dictionary,
	pulse_set: Dictionary,
	recent_trail_keys: Array[String],
	hovered_edge_key: String,
	hovered_portal_key: String,
	selected_edge_key: String = ""
) -> int:
	if active_set.has(key) or pulse_set.has(key) or selected_edge_key == key:
		return 2
	var f_id: String = str(ed["from"])
	var t_id: String = str(ed["to"])
	var route: int = int(ed.get("route", CanvasGeometry.ROUTE_STRAIGHT))
	if hovered_edge_key == key or hovered_portal_key == key or recent_trail_keys.has(key):
		return 1
	if focus_nodes.has(f_id) or (focus_nodes.has(t_id) and route == CanvasGeometry.ROUTE_TWIN):
		return 1
	if active_node_states.has(f_id) and active_node_states.has(t_id):
		var t_st: String = str((active_node_states[t_id] as Dictionary).get("state", "IDLE"))
		if t_st == "SUCCESS":
			return 1
	return 0


static func _draw_single_edge(
	canvas: Control,
	palette: CanvasThemePalette,
	ed: Dictionary,
	arch_name: StringName,
	active_node_states: Dictionary,
	focus_nodes: Dictionary,
	active_set: Dictionary,
	pulse_set: Dictionary,
	recent_trail_keys: Array[String],
	hovered_edge_key: String,
	hovered_portal_key: String,
	selected_edge_key: String = ""
) -> void:
	var key: String = str(ed["key"])
	var f_id: String = str(ed["from"])
	var t_id: String = str(ed["to"])
	var route: int = int(ed.get("route", CanvasGeometry.ROUTE_STRAIGHT))
	var pts: PackedVector2Array = ed["pts"] as PackedVector2Array
	if pts.size() < 2:
		return

	var is_pulsing: bool = pulse_set.has(key)
	var is_active: bool = active_set.has(key)
	var is_selected_edge: bool = (selected_edge_key == key)
	var is_hovered: bool = (hovered_edge_key == key or hovered_portal_key == key)
	var is_trail: bool = recent_trail_keys.has(key)
	var is_focus: bool = focus_nodes.has(f_id) or (focus_nodes.has(t_id) and route == CanvasGeometry.ROUTE_TWIN)

	var line_col: Color = palette.edge_idle
	var line_w: float = 1.4

	if route == CanvasGeometry.ROUTE_ANY_BUS:
		line_col = palette.edge_any
	elif route == CanvasGeometry.ROUTE_UNDER_ARC or route == CanvasGeometry.ROUTE_PORTAL_RETURN:
		line_col = palette.edge_idle
	elif arch_name == &"bt_tree" and not active_node_states.is_empty():
		var p_eval: bool = active_node_states.has(f_id)
		var c_st: String = str((active_node_states[t_id] as Dictionary).get("state", "IDLE")) if active_node_states.has(t_id) else "IDLE"
		if p_eval and c_st == "SUCCESS":
			line_col = palette.edge_success
			line_w = 1.75
		elif p_eval and c_st == "FAILURE":
			line_col = palette.edge_failure
			line_w = 1.50
		else:
			line_col = palette.edge_dormant
			line_w = 1.35

	if is_trail:
		line_col = palette.edge_trail
		line_w = 1.7
	if is_focus:
		line_col = palette.edge_focus
		line_w = 1.7
	if is_hovered:
		line_col = palette.edge_hover
		line_w = 2.0
	if is_selected_edge:
		canvas.draw_polyline(pts, Color(palette.accent, 0.22), 6.2, true)
		line_col = palette.accent
		line_w = 2.2
	if is_active:
		line_col = palette.edge_active
		line_w = 2.0
	if is_pulsing:
		line_col = palette.edge_pulse
		line_w = 2.2

	canvas.draw_polyline(pts, line_col, line_w, true)
	var arrow_col := Color(line_col.r, line_col.g, line_col.b, clampf(line_col.a + 0.16, 0.0, 1.0))
	_draw_endpoint_chevron(canvas, pts, arrow_col)

	if route == CanvasGeometry.ROUTE_PORTAL_RETURN and ed.has("portal_rect"):
		var pr: Rect2 = ed["portal_rect"] as Rect2
		var psb: StyleBoxFlat = palette.sb_portal_active if (is_pulsing or is_hovered or is_selected_edge) else palette.sb_portal_idle
		canvas.draw_style_box(psb, pr)
		var dot_col: Color = palette.warning if is_pulsing else (palette.accent if is_selected_edge else palette.text_dim)
		canvas.draw_circle(Vector2(pr.position.x + 9.5, pr.get_center().y), 2.2, dot_col)


static func _draw_endpoint_chevron(canvas: Control, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 2:
		return
	var tip: Vector2 = pts[pts.size() - 1]
	var prev: Vector2 = pts[pts.size() - 2]
	for k: int in range(pts.size() - 2, -1, -1):
		if tip.distance_to(pts[k]) >= 3.0:
			prev = pts[k]
			break
	var dir: Vector2 = tip - prev
	if dir.length_squared() < 0.001:
		return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var wing_a: Vector2 = tip - dir * 7.4 + perp * 3.7
	var wing_b: Vector2 = tip - dir * 7.4 - perp * 3.7
	var notch: Vector2 = tip - dir * 5.0
	canvas.draw_colored_polygon(PackedVector2Array([tip, wing_a, notch, wing_b]), col)


static func _draw_node_capsule(
	canvas: Control,
	palette: CanvasThemePalette,
	nd: Dictionary,
	active_node_states: Dictionary,
	selected_node_id: String,
	selected_node_set: Dictionary,
	hovered_node_id: String,
	hovered_port_node_id: String,
	conn_from_id: String,
	snap_target_id: String,
	snap_target_valid: bool,
	live_mode: bool,
	is_vertical: bool,
	is_bt: bool,
	pulse_wave: float,
	has_breakpoint: bool = false
) -> void:
	var nid: String = str(nd["id"])
	var rect: Rect2 = nd["rect"] as Rect2
	var kind: String = str(nd.get("kind", "State"))
	var is_initial: bool = bool(nd.get("is_initial", false))
	var is_interrupt: bool = bool(nd.get("is_interrupt", false))
	var is_terminal: bool = bool(nd.get("is_terminal", false))
	var is_selected: bool = (selected_node_id == nid)
	var is_multi_selected: bool = selected_node_set.has(nid)
	var is_port_hovered: bool = (hovered_port_node_id == nid)
	var is_hovered: bool = (hovered_node_id == nid) or is_port_hovered
	var is_conn_src: bool = (conn_from_id == nid)
	var is_snap_dst: bool = (not conn_from_id.is_empty() and snap_target_id == nid)

	var st_name: String = "IDLE"
	if active_node_states.has(nid):
		var st_info: Dictionary = active_node_states[nid] as Dictionary
		st_name = str(st_info.get("state", "RUNNING"))

	canvas.draw_style_box(palette.sb_shadow, Rect2(rect.position + Vector2(0.0, 2.0), rect.size))

	var card_sb: StyleBoxFlat = palette.sb_card_idle
	match st_name:
		"RUNNING":
			card_sb = palette.sb_card_running
		"SUCCESS":
			card_sb = palette.sb_card_success
		"FAILURE":
			card_sb = palette.sb_card_failure
		_:
			if is_hovered or is_snap_dst:
				card_sb = palette.sb_card_hover
	canvas.draw_style_box(card_sb, rect)

	if st_name == "RUNNING":
		var glow_a: float = lerpf(0.10, 0.30, pulse_wave)
		var halo_sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(0, 0, 0, 0), Color(palette.accent, glow_a), 2, 6)
		canvas.draw_style_box(halo_sb, rect.grow(2.5))
		var bar_w: float = (rect.size.x - 12.0) * lerpf(0.45, 0.96, pulse_wave)
		canvas.draw_rect(Rect2(Vector2(rect.position.x + 6.0, rect.end.y - 3.0), Vector2(bar_w, 1.5)), Color(palette.accent, 0.9), true)

	if is_snap_dst:
		var snap_col: Color = palette.success.lerp(palette.accent, 0.35) if snap_target_valid else palette.error
		var snap_sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(snap_col, 0.08), snap_col, 2, 7)
		canvas.draw_style_box(snap_sb, rect.grow(2.5))
	elif is_selected:
		canvas.draw_style_box(palette.sb_select_ring, rect.grow(2.0))
	elif is_multi_selected:
		canvas.draw_style_box(palette.sb_multi_select_ring, rect.grow(2.0))

	var accent_col: Color = palette.resolve_category_color(kind, is_initial, is_interrupt, is_terminal)
	var icon_tex: Texture2D = CanvasThemePalette.resolve_kind_icon(kind, is_initial, is_interrupt, is_terminal)
	if icon_tex != null:
		var ico_rect := Rect2(Vector2(rect.position.x + 10.0, rect.get_center().y - 8.0), Vector2(16.0, 16.0))
		canvas.draw_texture_rect(icon_tex, ico_rect, false, accent_col)

	if has_breakpoint:
		var bp_pt: Vector2 = rect.position + Vector2(3.5, 3.5)
		canvas.draw_circle(bp_pt, 5.8, palette.canvas_bg)
		canvas.draw_circle(bp_pt, 4.8, Color(0.22, 0.05, 0.06, 0.96))
		canvas.draw_circle(bp_pt, 3.6, Color(0.98, 0.25, 0.27, 1.0))
		canvas.draw_circle(bp_pt + Vector2(-1.0, -1.0), 1.0, Color(1.0, 0.78, 0.78, 0.85))

	var n_params: Dictionary = nd.get("params", {}) as Dictionary
	var sub_path: String = str(nd.get("sub_graph_path", n_params.get("sub_graph_path", ""))).strip_edges()
	var has_subgraph: bool = (kind == "SubTree") or (not sub_path.is_empty()) or bool(n_params.get("submachine", false))
	if has_subgraph:
		var sub_x: float = rect.end.x - (29.0 if (live_mode and is_hovered) else 15.0)
		var sub_y: float = rect.position.y + 4.5
		canvas.draw_rect(Rect2(Vector2(sub_x + 2.8, sub_y), Vector2(6.5, 6.5)), Color(palette.accent, 0.82), false, 1.2)
		canvas.draw_rect(Rect2(Vector2(sub_x, sub_y + 2.8), Vector2(6.5, 6.5)), palette.handle_bg, true)
		canvas.draw_rect(Rect2(Vector2(sub_x, sub_y + 2.8), Vector2(6.5, 6.5)), palette.accent, false, 1.3)

	if not live_mode:
		# 连线拖拽期间，所有可接收连线的候选目标节点显示清晰的入口磁吸插座
		if not conn_from_id.is_empty() and nid != conn_from_id and CanvasGeometry.can_node_accept_edge(kind, is_bt):
			var in_pt: Vector2 = CanvasGeometry.get_input_port_world(rect, is_vertical)
			if is_snap_dst:
				var s_col: Color = palette.success.lerp(palette.accent, 0.35) if snap_target_valid else palette.error
				canvas.draw_circle(in_pt, 7.2, Color(s_col, 0.26))
				canvas.draw_circle(in_pt, 5.2, palette.handle_bg)
				canvas.draw_circle(in_pt, 3.6, s_col)
			else:
				canvas.draw_circle(in_pt, 4.2, palette.handle_bg)
				canvas.draw_circle(in_pt, 2.4, Color(palette.text_dim, 0.65))

		# 输出连接手柄：单选、悬停或端口悬停时持续显示，移至外半圆绝不消失
		var show_idle_port: bool = is_selected and selected_node_set.size() <= 1
		if CanvasGeometry.can_node_emit_edge(kind, is_bt) and (show_idle_port or is_hovered or is_conn_src):
			var out_pt: Vector2 = CanvasGeometry.get_output_port_world(rect, is_vertical)
			if is_port_hovered or is_conn_src:
				canvas.draw_circle(out_pt, 8.2, Color(palette.accent, 0.26))
				canvas.draw_circle(out_pt, 5.8, palette.handle_bg)
				canvas.draw_circle(out_pt, 4.0, palette.accent.lightened(0.15))
			else:
				canvas.draw_circle(out_pt, 5.2, palette.handle_bg)
				canvas.draw_circle(out_pt, 3.2, palette.accent)
	elif is_hovered:
		var bolt_tex: Texture2D = CanvasThemePalette.get_bolt_trigger_icon()
		if bolt_tex != null:
			var bolt_rect := Rect2(Vector2(rect.end.x - 16.0, rect.position.y + 4.0), Vector2(11.0, 11.0))
			canvas.draw_texture_rect(bolt_tex, bolt_rect, false, palette.warning)

#endregion


#region 1:1 屏幕像素文字层、选框与缩略小地图委派接口

static func draw_screen_labels(
	canvas: Control,
	font: Font,
	palette: CanvasThemePalette,
	ctx: Dictionary
) -> void:
	CanvasOverlayPainter.draw_screen_labels(canvas, font, palette, ctx)


static func draw_minimap(
	canvas: Control,
	palette: CanvasThemePalette,
	world_bounds: Rect2,
	ctx: Dictionary
) -> void:
	CanvasOverlayPainter.draw_minimap(canvas, palette, world_bounds, ctx)


static func draw_marquee_box(
	canvas: Control,
	palette: CanvasThemePalette,
	marquee_screen_rect: Rect2
) -> void:
	CanvasOverlayPainter.draw_marquee_box(canvas, palette, marquee_screen_rect)

#endregion
