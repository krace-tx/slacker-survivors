@tool
extends RefCounted

## 屏幕空间锐利文字、BT 优先级角标、防碰撞条件胶囊与缩略小地图绘制器（Screen-Space Overlay & Minimap Painter）。[br]
##
## 由 [`CanvasPainter`](canvas_painter.gd) 委派调用，工作在 1:1 屏幕像素坐标系下，确保任意缩放倍率下字体与角标零模糊。

const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)


static func draw_screen_labels(
	canvas: Control,
	font: Font,
	palette: CanvasThemePalette,
	ctx: Dictionary
) -> void:
	var zoom: float = float(ctx["zoom"])
	var ui_s: float = maxf(float(ctx.get("ui_scale", 1.0)), 0.75)
	if zoom < 0.34 * ui_s:
		return

	var scroll_offset: Vector2 = ctx["scroll_offset"] as Vector2
	var nodes: Dictionary = ctx["nodes"] as Dictionary
	var node_order: Array[String] = ctx["node_order"] as Array[String]
	var routed_edges: Array[Dictionary] = ctx["routed_edges"] as Array[Dictionary]
	var active_node_states: Dictionary = ctx["active_node_states"] as Dictionary
	var interrupt_source_hints: Dictionary = ctx["interrupt_source_hints"] as Dictionary
	var focus_nodes: Dictionary = ctx["focus_nodes"] as Dictionary
	var active_set: Dictionary = ctx["active_edge_set"] as Dictionary
	var pulse_set: Dictionary = ctx["pulse_edge_set"] as Dictionary
	var recent_trail_keys: Array[String] = ctx["recent_trail_keys"] as Array[String]
	var hovered_edge_key: String = str(ctx["hovered_edge_key"])
	var hovered_portal_key: String = str(ctx["hovered_portal_key"])
	var show_all_labels: bool = bool(ctx["show_all_labels"])

	var title_fsize: int = maxi(10, roundi(12.0 * zoom))
	var sub_fsize: int = maxi(9, roundi(10.0 * zoom))
	var title_ascent_delta: float = float(font.get_ascent(title_fsize) - font.get_descent(title_fsize))
	var sub_ascent_delta: float = float(font.get_ascent(sub_fsize) - font.get_descent(sub_fsize))

	if bool(ctx["has_any_state_zone"]):
		var any_zone_rect: Rect2 = ctx["any_zone_rect"] as Rect2
		var any_origin_boxes: Array[Rect2] = ctx["any_origin_boxes"] as Array[Rect2]
		var zone_tl: Vector2 = (any_zone_rect.position + Vector2(12.0, 16.0)) * zoom - scroll_offset
		canvas.draw_string(font, zone_tl, FlowEditorI18n.t(&"canvas.any_zone_header"), HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize, Color(palette.interrupt, 0.78))
		var any_lbl: String = FlowEditorI18n.t(&"canvas.any_origin")
		for abox: Rect2 in any_origin_boxes:
			var s_abox := Rect2(abox.position * zoom - scroll_offset, abox.size * zoom)
			var ay: float = s_abox.position.y + (s_abox.size.y + sub_ascent_delta) * 0.5
			canvas.draw_string(font, Vector2(s_abox.position.x + 22.0 * zoom, ay), any_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize, palette.text_title)

	for nid: String in node_order:
		_draw_node_title_and_chips(
			canvas, font, palette, nodes[nid] as Dictionary, active_node_states,
			interrupt_source_hints, zoom, scroll_offset, ui_s,
			title_fsize, sub_fsize, title_ascent_delta, sub_ascent_delta
		)

	var static_screen_obstacles: Array[Rect2] = []
	for nid_obs: String in node_order:
		var w_obs: Rect2 = (nodes[nid_obs] as Dictionary)["rect"] as Rect2
		static_screen_obstacles.append(Rect2(w_obs.position * zoom - scroll_offset, w_obs.size * zoom).grow(3.0 * ui_s))
	if bool(ctx["has_any_state_zone"]):
		for abox_obs: Rect2 in (ctx["any_origin_boxes"] as Array[Rect2]):
			static_screen_obstacles.append(Rect2(abox_obs.position * zoom - scroll_offset, abox_obs.size * zoom).grow(3.0 * ui_s))

	var pill_items: Array[Dictionary] = []
	for ed: Dictionary in routed_edges:
		var key: String = str(ed["key"])
		var f_id: String = str(ed["from"])
		var t_id: String = str(ed["to"])
		var route: int = int(ed.get("route", CanvasGeometry.ROUTE_STRAIGHT))

		if route == CanvasGeometry.ROUTE_PORTAL_RETURN and ed.has("portal_rect"):
			var pr_w: Rect2 = ed["portal_rect"] as Rect2
			var pr_s := Rect2(pr_w.position * zoom - scroll_offset, pr_w.size * zoom)
			static_screen_obstacles.append(pr_s.grow(2.5 * ui_s))
			var ptxt: String = str(ed.get("portal_text", ""))
			var is_p_pulse: bool = pulse_set.has(key) or hovered_portal_key == key
			var pcol: Color = palette.warning.lerp(Color.WHITE, 0.3) if is_p_pulse else palette.text_dim
			canvas.draw_string(font, Vector2(pr_s.position.x + 16.0 * zoom, pr_s.position.y + (pr_s.size.y + sub_ascent_delta) * 0.5), ptxt, HORIZONTAL_ALIGNMENT_LEFT, pr_s.size.x - 20.0 * zoom, sub_fsize, pcol)
			continue

		var b_idx: int = int(ed.get("bt_child_order", ed.get("branch_index", -1)))
		if b_idx >= 1:
			var brect: Rect2 = _draw_bt_priority_badge(
				canvas, font, palette, ed, key, f_id, t_id, b_idx,
				active_set, active_node_states, zoom, scroll_offset, ui_s, sub_fsize, sub_ascent_delta
			)
			static_screen_obstacles.append(brect.grow(2.0 * ui_s))

		var raw_lbl: String = str(ed.get("label", ""))
		if raw_lbl.is_empty() or (b_idx >= 1 and (raw_lbl == ("#%d" % b_idx) or (raw_lbl.begins_with("#") and raw_lbl.substr(1).is_valid_int()))):
			continue
		var is_pulsing: bool = pulse_set.has(key)
		var is_active: bool = active_set.has(key)
		var is_trail: bool = recent_trail_keys.has(key)
		var is_hovered_e: bool = (hovered_edge_key == key)
		var is_focus_e: bool = focus_nodes.has(f_id) or (focus_nodes.has(t_id) and route == CanvasGeometry.ROUTE_TWIN)
		if not (show_all_labels or is_focus_e or is_pulsing or is_active or is_trail or is_hovered_e):
			continue

		var anchor_w: Vector2 = ed.get("pill_pos", Vector2.ZERO) as Vector2
		var anchor_s: Vector2 = anchor_w * zoom - scroll_offset
		var disp_lbl: String = raw_lbl if raw_lbl.length() <= 18 else (raw_lbl.substr(0, 16) + "..")
		var lsz: Vector2 = font.get_string_size(disp_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize)
		var pad_p: Vector2 = Vector2(10.0, 4.0) * ui_s
		var box_p := Rect2(anchor_s - (lsz + pad_p) * 0.5, lsz + pad_p)

		var sb_use: StyleBoxFlat = palette.sb_pill_focus if is_focus_e else palette.sb_pill_dim
		var col_use: Color = palette.text_title_active if is_focus_e else palette.text_dim
		if is_pulsing:
			sb_use = palette.sb_pill_pulse
			col_use = palette.warning.lerp(Color.WHITE, 0.35)
		elif is_active:
			sb_use = palette.sb_pill_active
			col_use = palette.accent.lerp(Color.WHITE, 0.3)

		pill_items.append({"rect": box_p, "text": disp_lbl, "sb": sb_use, "col": col_use})

	_resolve_pill_collisions(pill_items, static_screen_obstacles, ui_s)
	for p_item: Dictionary in pill_items:
		var pr: Rect2 = p_item["rect"] as Rect2
		canvas.draw_style_box(p_item["sb"] as StyleBoxFlat, pr)
		canvas.draw_string(font, Vector2(pr.position.x + 5.0 * ui_s, pr.position.y + (pr.size.y + sub_ascent_delta) * 0.5), str(p_item["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize, p_item["col"] as Color)


static func _draw_node_title_and_chips(
	canvas: Control,
	font: Font,
	palette: CanvasThemePalette,
	nd: Dictionary,
	active_node_states: Dictionary,
	interrupt_source_hints: Dictionary,
	zoom: float,
	scroll_offset: Vector2,
	ui_s: float,
	title_fsize: int,
	sub_fsize: int,
	title_ascent_delta: float,
	sub_ascent_delta: float
) -> void:
	var nid: String = str(nd["id"])
	var w_rect: Rect2 = nd["rect"] as Rect2
	var s_rect := Rect2(w_rect.position * zoom - scroll_offset, w_rect.size * zoom)
	var title_s: String = str(nd.get("title", nid))

	var badge_s: String = ""
	var st_name: String = "IDLE"
	if active_node_states.has(nid):
		var st_info: Dictionary = active_node_states[nid] as Dictionary
		badge_s = str(st_info.get("badge", ""))
		st_name = str(st_info.get("state", "RUNNING"))

	var right_reserve: float = 10.0 * zoom
	if not badge_s.is_empty():
		var b_sz: Vector2 = font.get_string_size(badge_s, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize)
		var chip_w: float = b_sz.x + 10.0 * zoom
		var chip_h: float = maxf(16.0 * zoom, b_sz.y + 3.0 * zoom)
		var chip_rect := Rect2(Vector2(s_rect.end.x - chip_w - 7.0 * zoom, s_rect.get_center().y - chip_h * 0.5), Vector2(chip_w, chip_h))
		canvas.draw_style_box(palette.sb_badge_chip, chip_rect)
		var chip_col: Color = palette.text_dim
		if st_name == "RUNNING":
			chip_col = palette.accent
		elif st_name == "SUCCESS":
			chip_col = palette.success
		elif st_name == "FAILURE":
			chip_col = palette.error
		canvas.draw_string(font, Vector2(chip_rect.position.x + 5.0 * zoom, chip_rect.position.y + (chip_rect.size.y + sub_ascent_delta) * 0.5), badge_s, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize, chip_col)
		right_reserve = chip_w + 14.0 * zoom

	var has_icon: bool = CanvasThemePalette.resolve_kind_icon(
		str(nd.get("kind", "State")),
		bool(nd.get("is_initial", false)),
		bool(nd.get("is_interrupt", false)),
		bool(nd.get("is_terminal", false))
	) != null
	var lead_px: float = (32.0 if has_icon else 12.0) * zoom
	var text_x: float = s_rect.position.x + lead_px
	var max_text_w: float = maxf(24.0, s_rect.size.x - lead_px - right_reserve)
	var baseline_y: float = s_rect.position.y + (s_rect.size.y + title_ascent_delta) * 0.5
	var txt_col: Color = palette.text_title_active if st_name == "RUNNING" else palette.text_title
	canvas.draw_string(font, Vector2(text_x, baseline_y), title_s, HORIZONTAL_ALIGNMENT_LEFT, max_text_w, title_fsize, txt_col)

	if interrupt_source_hints.has(nid):
		var hrec: Dictionary = interrupt_source_hints[nid] as Dictionary
		var alpha_h: float = clampf(float(hrec.get("ttl", 0.0)) * 0.8, 0.0, 1.0)
		var hint_txt: String = "%s ->" % str(hrec.get("from_title", ""))
		var hsz: Vector2 = font.get_string_size(hint_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize)
		var hpad_x: float = 12.0 * ui_s
		var hpad_y: float = 4.0 * ui_s
		var hbox := Rect2(Vector2(s_rect.get_center().x - (hsz.x + hpad_x) * 0.5, s_rect.position.y - hsz.y - 10.0 * ui_s), Vector2(hsz.x + hpad_x, hsz.y + hpad_y))
		canvas.draw_style_box(palette.sb_pill_pulse, hbox)
		canvas.draw_string(font, Vector2(hbox.position.x + 6.0 * ui_s, hbox.position.y + (hbox.size.y + sub_ascent_delta) * 0.5), hint_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize, Color(palette.warning.lerp(Color.WHITE, 0.4), alpha_h))


static func _draw_bt_priority_badge(
	canvas: Control,
	font: Font,
	palette: CanvasThemePalette,
	ed: Dictionary,
	key: String,
	f_id: String,
	t_id: String,
	b_idx: int,
	active_set: Dictionary,
	active_node_states: Dictionary,
	zoom: float,
	scroll_offset: Vector2,
	ui_s: float,
	sub_fsize: int,
	sub_ascent_delta: float
) -> Rect2:
	var tap_w: Vector2 = (
		ed["tap_badge_pos"] as Vector2 if ed.has("tap_badge_pos")
		else CanvasGeometry.interpolate_polyline(ed["pts"] as PackedVector2Array, 0.82)
	)
	var tpos_s: Vector2 = tap_w * zoom - scroll_offset
	var b_str: String = "#%d" % b_idx
	var bsz: Vector2 = font.get_string_size(b_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize)
	var b_pad: Vector2 = Vector2(8.0, 3.0) * ui_s
	var brect := Rect2(tpos_s - (bsz + b_pad) * 0.5, bsz + b_pad)
	var b_sb: StyleBoxFlat = palette.sb_pill_dim
	var b_col: Color = palette.text_dim
	if active_set.has(key):
		b_sb = palette.sb_pill_active
		b_col = palette.accent
	elif active_node_states.has(f_id) and active_node_states.has(t_id):
		var child_st_b: String = str((active_node_states[t_id] as Dictionary).get("state", "IDLE"))
		if child_st_b == "SUCCESS":
			b_sb = palette.sb_pill_success
			b_col = palette.success
		elif child_st_b == "FAILURE":
			b_sb = palette.sb_pill_fail
			b_col = palette.error
	canvas.draw_style_box(b_sb, brect)
	canvas.draw_string(font, Vector2(brect.position.x + 4.0 * ui_s, brect.position.y + (brect.size.y + sub_ascent_delta) * 0.5), b_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsize, b_col)
	return brect


static func _resolve_pill_collisions(pill_items: Array[Dictionary], static_screen_obstacles: Array[Rect2], ui_s: float) -> void:
	for _it: int in range(6):
		for i: int in range(pill_items.size()):
			var ri: Rect2 = pill_items[i]["rect"] as Rect2
			for obs_r: Rect2 in static_screen_obstacles:
				if ri.intersects(obs_r):
					var ox: float = minf(ri.end.x, obs_r.end.x) - maxf(ri.position.x, obs_r.position.x) + 2.0 * ui_s
					var oy_s: float = minf(ri.end.y, obs_r.end.y) - maxf(ri.position.y, obs_r.position.y) + 2.0 * ui_s
					if oy_s <= ox:
						ri.position.y += (-oy_s if ri.get_center().y <= obs_r.get_center().y else oy_s)
					else:
						ri.position.x += (-ox if ri.get_center().x <= obs_r.get_center().x else ox)
			pill_items[i]["rect"] = ri

		for i: int in range(pill_items.size()):
			for j: int in range(i + 1, pill_items.size()):
				var ra: Rect2 = pill_items[i]["rect"] as Rect2
				var rb: Rect2 = pill_items[j]["rect"] as Rect2
				if ra.grow(2.0 * ui_s).intersects(rb):
					var ox_p: float = minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x) + 3.0 * ui_s
					var oy_p: float = minf(ra.end.y, rb.end.y) - maxf(ra.position.y, rb.position.y) + 3.0 * ui_s
					if oy_p <= ox_p:
						var dy: float = -1.0 if ra.get_center().y <= rb.get_center().y else 1.0
						ra.position.y += oy_p * 0.5 * dy
						rb.position.y -= oy_p * 0.5 * dy
					else:
						var dx_p: float = -1.0 if ra.get_center().x <= rb.get_center().x else 1.0
						ra.position.x += ox_p * 0.5 * dx_p
						rb.position.x -= ox_p * 0.5 * dx_p
					pill_items[i]["rect"] = ra
					pill_items[j]["rect"] = rb


static func draw_minimap(
	canvas: Control,
	palette: CanvasThemePalette,
	world_bounds: Rect2,
	ctx: Dictionary
) -> void:
	var nodes: Dictionary = ctx["nodes"] as Dictionary
	var ui_s: float = maxf(float(ctx.get("ui_scale", 1.0)), 0.75)
	if nodes.is_empty() or canvas.size.x < 340.0 * ui_s or canvas.size.y < 240.0 * ui_s:
		return

	var map_sz: Vector2 = (Vector2(168.0, 104.0) * ui_s).round()
	var margin: Vector2 = (Vector2(14.0, 14.0) * ui_s).round()
	var map_rect := Rect2(canvas.size - map_sz - margin, map_sz)
	canvas.draw_style_box(palette.sb_minimap, map_rect)

	var wb: Rect2 = world_bounds.grow(40.0)
	var inner_pad: float = roundf(8.0 * ui_s)
	var avail: Vector2 = map_sz - Vector2(inner_pad * 2.0, inner_pad * 2.0)
	var scale_m: float = minf(avail.x / maxf(wb.size.x, 1.0), avail.y / maxf(wb.size.y, 1.0))
	var offset_m: Vector2 = map_rect.position + Vector2(inner_pad, inner_pad) + (avail - wb.size * scale_m) * 0.5

	var routed_edges: Array[Dictionary] = ctx["routed_edges"] as Array[Dictionary]
	for ed: Dictionary in routed_edges:
		var pts: PackedVector2Array = ed["pts"] as PackedVector2Array
		if pts.size() >= 2:
			var p0: Vector2 = offset_m + (pts[0] - wb.position) * scale_m
			var p1: Vector2 = offset_m + (pts[pts.size() - 1] - wb.position) * scale_m
			canvas.draw_line(p0, p1, palette.minimap_edge, maxf(1.0, roundf(1.0 * ui_s)))

	var node_order: Array[String] = ctx["node_order"] as Array[String]
	var active_node_states: Dictionary = ctx["active_node_states"] as Dictionary
	var min_dot_sz := Vector2(4.0 * ui_s, 2.5 * ui_s)
	for nid: String in node_order:
		var nd: Dictionary = nodes[nid] as Dictionary
		var nr: Rect2 = nd["rect"] as Rect2
		var mr := Rect2(offset_m + (nr.position - wb.position) * scale_m, (nr.size * scale_m).max(min_dot_sz))
		var mc: Color = palette.minimap_node
		if active_node_states.has(nid):
			var st_m: String = str((active_node_states[nid] as Dictionary).get("state", "RUNNING"))
			if st_m == "FAILURE":
				mc = palette.error
			elif st_m == "SUCCESS":
				mc = palette.success
			else:
				mc = palette.accent
		elif bool(nd.get("is_interrupt", false)):
			mc = Color(palette.interrupt, 0.8)
		canvas.draw_rect(mr, mc, true)

	var scroll_offset: Vector2 = ctx["scroll_offset"] as Vector2
	var zoom: float = maxf(float(ctx["zoom"]), 0.15)
	var view_world_tl: Vector2 = scroll_offset / zoom
	var view_world_sz: Vector2 = canvas.size / zoom
	var vr := Rect2(offset_m + (view_world_tl - wb.position) * scale_m, view_world_sz * scale_m)
	vr = vr.intersection(map_rect.grow(-2.0 * ui_s))
	if vr.size.x > 2.0 and vr.size.y > 2.0:
		canvas.draw_rect(vr, Color(palette.accent, 0.6), false, maxf(1.0, roundf(1.2 * ui_s)))
