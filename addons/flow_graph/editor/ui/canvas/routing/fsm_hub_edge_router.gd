@tool
extends RefCounted

## FSM 星型枢纽专用边路由器（FSM Hub Twin, Portal Return, Back-Arc & Any-State Router）。[br]
##
## 负责 `[-> Hub]` 本地回流胶囊防重叠排布、同行/同列俄罗斯套娃回跳弧、平行正交双轨以及底部 `[Any State]` 全局中断区总线构建。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const EdgeObstacleAvoidance = preload(FlowGraphContracts.SCRIPT_ROUTE_OBSTACLE)


#region Pass 1: 本地回流胶囊排布

static func route_portal_returns(
	graph: MermaidGraphModel,
	plan: Dictionary,
	nodes: Dictionary,
	node_order: Array[String],
	portal_obstacles: Array[Rect2],
	existing_polylines: Array[PackedVector2Array],
	routed_edges: Array[Dictionary],
	edge_by_key: Dictionary
) -> void:
	var hub_id: String = str(plan.get("hub_id", ""))
	var hub_short: String = str(plan.get("hub_short_title", hub_id))
	var portal_returns: Dictionary = plan.get("portal_return_edges", {}) as Dictionary
	var interrupt_redirects: Dictionary = plan.get("interrupt_redirect_edges", {}) as Dictionary
	var transient_only: Dictionary = plan.get("transient_only_edges", {}) as Dictionary
	var fwd_out_map: Dictionary = plan.get("fwd_out", {}) as Dictionary

	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		if f == "*" or f == t or not nodes.has(f) or not nodes.has(t):
			continue
		var key: String = "%s->%s" % [f, t]
		if not portal_returns.has(key) or interrupt_redirects.has(key) or transient_only.has(key):
			continue

		var lbl: String = str(ed.get("label", "")).strip_edges()
		var rf: Rect2 = (nodes[f] as Dictionary)["rect"] as Rect2
		var p_txt: String = "-> %s" % hub_short
		if not lbl.is_empty():
			var short_l: String = lbl if lbl.length() <= 10 else (lbl.substr(0, 9) + "..")
			p_txt = "-> %s · %s" % [hub_short, short_l]
		var pw: float = MermaidMetrics.estimate_portal_pill_width(hub_short, lbl)
		var ph: float = 22.0
		var fwd_children: Array = fwd_out_map.get(f, []) as Array

		var east_probe := Rect2(Vector2(rf.end.x + 6.0, rf.get_center().y - 13.0), Vector2(30.0 + pw, 26.0))
		var use_east: bool = fwd_children.is_empty() and not EdgeObstacleAvoidance.rect_hits_other_nodes(east_probe, f, nodes, node_order)

		var stem_start: Vector2
		var stem_end: Vector2
		var portal_rect: Rect2
		if use_east:
			stem_start = Vector2(rf.end.x, rf.get_center().y)
			stem_end = Vector2(rf.end.x + 28.0, rf.get_center().y)
			portal_rect = Rect2(Vector2(stem_end.x, rf.get_center().y - ph * 0.5), Vector2(pw, ph))
		else:
			# 非叶节点将顶部胶囊偏右放置 (66% 处)，把左侧留给跨行正交连线锚点，彻底杜绝顶边打架
			var stem_x: float = rf.position.x + rf.size.x * 0.66
			stem_start = Vector2(stem_x, rf.position.y)
			stem_end = Vector2(stem_x, rf.position.y - 18.0)
			portal_rect = Rect2(Vector2(stem_x - pw * 0.5, stem_end.y - ph), Vector2(pw, ph))

		portal_obstacles.append(portal_rect.grow(5.0))
		var pts_p := PackedVector2Array([stem_start, stem_end])
		existing_polylines.append(pts_p)
		var rec_p: Dictionary = {
			"key": key,
			"from": f,
			"to": t,
			"label": "",
			"portal_text": p_txt,
			"portal_rect": portal_rect,
			"route": CanvasGeometry.ROUTE_PORTAL_RETURN,
			"pts": pts_p,
			"branch_index": -1,
		}
		routed_edges.append(rec_p)
		edge_by_key[key] = rec_p

#endregion


#region Pass 2: 同行/同列俄罗斯套娃嵌套回跳弧

static func route_same_band_back_arcs(
	graph: MermaidGraphModel,
	plan: Dictionary,
	nodes: Dictionary,
	node_order: Array[String],
	is_vertical: bool,
	deferred_backs: Dictionary,
	existing_polylines: Array[PackedVector2Array],
	routed_edges: Array[Dictionary],
	edge_by_key: Dictionary
) -> void:
	var arch: StringName = plan.get("archetype", MermaidMetrics.ARCHETYPE_DAG_PIPELINE) as StringName
	var portal_returns: Dictionary = plan.get("portal_return_edges", {}) as Dictionary
	var interrupt_redirects: Dictionary = plan.get("interrupt_redirect_edges", {}) as Dictionary
	var transient_only: Dictionary = plan.get("transient_only_edges", {}) as Dictionary
	var local_backs: Dictionary = plan.get("local_back_edges", {}) as Dictionary
	var plan_backs: Dictionary = plan.get("back_edges", {}) as Dictionary

	var same_band_backs: Array[Dictionary] = []
	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		if f == "*" or f == t or not nodes.has(f) or not nodes.has(t):
			continue
		var key: String = "%s->%s" % [f, t]
		if portal_returns.has(key) or interrupt_redirects.has(key) or transient_only.has(key):
			continue
		var is_back: bool = local_backs.has(key) or (arch != MermaidMetrics.ARCHETYPE_FSM_HUB and plan_backs.has(key))
		if not is_back:
			continue

		var rf_b: Rect2 = (nodes[f] as Dictionary)["rect"] as Rect2
		var rt_b: Rect2 = (nodes[t] as Dictionary)["rect"] as Rect2
		if not is_vertical and absf(rf_b.get_center().y - rt_b.get_center().y) <= 38.0:
			same_band_backs.append({"ed": ed, "span": absf(rf_b.get_center().x - rt_b.get_center().x)})
		elif is_vertical and absf(rf_b.get_center().x - rt_b.get_center().x) <= 48.0:
			same_band_backs.append({"ed": ed, "span": absf(rf_b.get_center().y - rt_b.get_center().y)})
		else:
			deferred_backs[key] = true

	same_band_backs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["span"]) < float(b["span"])
	)

	var band_lane_counts: Dictionary = {}
	for b_item: Dictionary in same_band_backs:
		var ed_b: Dictionary = b_item["ed"] as Dictionary
		var f: String = str(ed_b["from"])
		var t: String = str(ed_b["to"])
		var key: String = "%s->%s" % [f, t]
		var lbl: String = str(ed_b.get("label", "")).strip_edges()
		var rf: Rect2 = (nodes[f] as Dictionary)["rect"] as Rect2
		var rt: Rect2 = (nodes[t] as Dictionary)["rect"] as Rect2

		var pts_u: PackedVector2Array
		var pill_u: Vector2
		if not is_vertical:
			var band_id: int = roundi(((rf.get_center().y + rt.get_center().y) * 0.5) / 70.0)
			var lane_i: int = int(band_lane_counts.get(band_id, 0))
			band_lane_counts[band_id] = lane_i + 1

			var min_x: float = minf(rf.position.x, rt.position.x) - 6.0
			var max_x: float = maxf(rf.end.x, rt.end.x) + 6.0
			var max_row_bottom: float = maxf(rf.end.y, rt.end.y)
			for mid_id: String in node_order:
				var mr: Rect2 = (nodes[mid_id] as Dictionary)["rect"] as Rect2
				if mr.end.x >= min_x and mr.position.x <= max_x and absf(mr.get_center().y - rf.get_center().y) < 52.0:
					max_row_bottom = maxf(max_row_bottom, mr.end.y)

			var rail_y: float = max_row_bottom + 24.0 + float(lane_i) * 19.0
			var p0 := Vector2(rf.get_center().x - 10.0, rf.end.y)
			var p3 := Vector2(rt.get_center().x + 10.0 + float(lane_i) * 8.0, rt.end.y)
			p3.x = clampf(p3.x, rt.position.x + 14.0, rt.end.x - 14.0)
			pts_u = CanvasGeometry.make_rounded_ortho_path([p0, Vector2(p0.x, rail_y), Vector2(p3.x, rail_y), p3], 10.0)
			pill_u = Vector2((p0.x + p3.x) * 0.5, rail_y)
		else:
			var band_vid: int = roundi(((rf.get_center().x + rt.get_center().x) * 0.5) / 120.0)
			var lane_vi: int = int(band_lane_counts.get(band_vid, 0))
			band_lane_counts[band_vid] = lane_vi + 1

			var min_y: float = minf(rf.position.y, rt.position.y) - 6.0
			var max_y: float = maxf(rf.end.y, rt.end.y) + 6.0
			var min_col_left: float = minf(rf.position.x, rt.position.x)
			for mid_id2: String in node_order:
				var mr2: Rect2 = (nodes[mid_id2] as Dictionary)["rect"] as Rect2
				if mr2.end.y >= min_y and mr2.position.y <= max_y and absf(mr2.get_center().x - rf.get_center().x) < 90.0:
					min_col_left = minf(min_col_left, mr2.position.x)

			var rail_x: float = min_col_left - 26.0 - float(lane_vi) * 18.0
			var pv0 := Vector2(rf.position.x, rf.get_center().y - 6.0)
			var pv3 := Vector2(rt.position.x, rt.get_center().y + 6.0)
			pts_u = CanvasGeometry.make_rounded_ortho_path([pv0, Vector2(rail_x, pv0.y), Vector2(rail_x, pv3.y), pv3], 10.0)
			pill_u = Vector2(rail_x, (pv0.y + pv3.y) * 0.5)

		existing_polylines.append(pts_u)
		var rec_u: Dictionary = {
			"key": key,
			"from": f,
			"to": t,
			"label": lbl,
			"route": CanvasGeometry.ROUTE_UNDER_ARC,
			"pts": pts_u,
			"pill_pos": pill_u,
			"branch_index": -1,
		}
		routed_edges.append(rec_u)
		edge_by_key[key] = rec_u

#endregion


#region 双向正交平行双轨与底部 [Any State] 全局中断区

static func try_route_orthogonal_twin(
	f: String,
	t: String,
	rf: Rect2,
	rt: Rect2,
	lbl: String,
	obstacles: Array[Rect2]
) -> Dictionary:
	var cf: Vector2 = rf.get_center()
	var ct: Vector2 = rt.get_center()
	var dx: float = ct.x - cf.x
	var dy: float = ct.y - cf.y
	var sign_dir: float = 1.0 if f < t else -1.0

	# 1. 同行水平平行双轨
	if absf(dy) <= 22.0 and (rt.position.x > rf.end.x + 8.0 or rf.position.x > rt.end.x + 8.0):
		var y_mid: float = (cf.y + ct.y) * 0.5 + sign_dir * 7.5
		y_mid = clampf(y_mid, maxf(rf.position.y, rt.position.y) + 7.0, minf(rf.end.y, rt.end.y) - 7.0)
		var pa_h := Vector2(rf.end.x if dx > 0.0 else rf.position.x, y_mid)
		var pb_h := Vector2(rt.position.x if dx > 0.0 else rt.end.x, y_mid)
		var wps_h: Array[Vector2] = [pa_h, pb_h]
		if not CanvasGeometry.waypoints_hit_obstacles(wps_h, obstacles, rf, rt):
			return {
				"ok": true,
				"pts": PackedVector2Array(wps_h),
				"pill_pos": Vector2((pa_h.x + pb_h.x) * 0.5, y_mid + sign_dir * 14.5),
			}

	# 2. 同列垂直平行双轨（偏向左侧安全带避让右侧回流胶囊）
	if absf(dx) <= 38.0 and (rt.position.y > rf.end.y + 8.0 or rf.position.y > rt.end.y + 8.0):
		var overlap_l: float = maxf(rf.position.x, rt.position.x) + 12.0
		var overlap_r: float = minf(rf.end.x, rt.end.x) - 12.0
		if overlap_r > overlap_l:
			var base_x: float = clampf((cf.x + ct.x) * 0.5, overlap_l + 9.0, overlap_r - 9.0)
			var safe_x: float = minf(base_x, overlap_l + (overlap_r - overlap_l) * 0.34)
			var x_lane: float = safe_x + sign_dir * 8.0
			var pa_v := Vector2(x_lane, rf.end.y if dy > 0.0 else rf.position.y)
			var pb_v := Vector2(x_lane, rt.position.y if dy > 0.0 else rt.end.y)
			var wps_v: Array[Vector2] = [pa_v, pb_v]
			if not CanvasGeometry.waypoints_hit_obstacles(wps_v, obstacles, rf, rt):
				var pill_off_x: float = MermaidMetrics.estimate_label_pill_width(lbl) * 0.5 + 9.0
				return {
					"ok": true,
					"pts": PackedVector2Array(wps_v),
					"pill_pos": Vector2(x_lane + sign_dir * pill_off_x, (pa_v.y + pb_v.y) * 0.5),
				}

	# 3. 错位正交双折线
	if rt.position.x >= rf.end.x + 20.0 or rf.position.x >= rt.end.x + 20.0:
		var going_east: bool = dx > 0.0
		var sx: float = rf.end.x if going_east else rf.position.x
		var ex: float = rt.position.x if going_east else rt.end.x
		var sy: float = clampf(cf.y + sign_dir * 7.0, rf.position.y + 8.0, rf.end.y - 8.0)
		var ey: float = clampf(ct.y + sign_dir * 7.0, rt.position.y + 8.0, rt.end.y - 8.0)
		var mid_x: float = (sx + ex) * 0.5 + sign_dir * 7.5
		var wps_z: Array[Vector2] = [Vector2(sx, sy), Vector2(mid_x, sy), Vector2(mid_x, ey), Vector2(ex, ey)]
		if not CanvasGeometry.waypoints_hit_obstacles(wps_z, obstacles, rf, rt):
			return {
				"ok": true,
				"pts": CanvasGeometry.make_rounded_ortho_path(wps_z, 9.0),
				"pill_pos": Vector2((mid_x + ex) * 0.5, ey + sign_dir * 13.0),
			}

	return {"ok": false}


static func build_any_state_zone_routes(
	interrupt_nodes: Array,
	nodes: Dictionary,
	routed_edges: Array[Dictionary],
	edge_by_key: Dictionary
) -> Dictionary:
	var valid_ids: Array[String] = []
	for item: Variant in interrupt_nodes:
		var iid: String = str(item)
		if nodes.has(iid):
			valid_ids.append(iid)

	var origin_boxes: Array[Rect2] = []
	if valid_ids.is_empty():
		return {"has_zone": false, "zone_rect": Rect2(), "origin_boxes": origin_boxes}

	var rows: Array[Array] = []
	for iid: String in valid_ids:
		var r: Rect2 = (nodes[iid] as Dictionary)["rect"] as Rect2
		var placed: bool = false
		for row_arr: Array in rows:
			var ref_r: Rect2 = (nodes[str(row_arr[0])] as Dictionary)["rect"] as Rect2
			if absf(r.position.y - ref_r.position.y) < 34.0:
				row_arr.append(iid)
				placed = true
				break
		if not placed:
			rows.append([iid])

	var zone_min := Vector2(INF, INF)
	var zone_max := Vector2(-INF, -INF)

	for row_arr: Array in rows:
		row_arr.sort_custom(func(a: Variant, b: Variant) -> bool:
			var xa: float = ((nodes[str(a)] as Dictionary)["rect"] as Rect2).position.x
			var xb: float = ((nodes[str(b)] as Dictionary)["rect"] as Rect2).position.x
			return xa < xb
		)
		var first_r: Rect2 = (nodes[str(row_arr[0])] as Dictionary)["rect"] as Rect2
		var rail_y: float = first_r.position.y - 26.0
		var badge_sz := Vector2(114.0, 28.0)
		var badge_pos := Vector2(first_r.position.x - 138.0, rail_y - badge_sz.y * 0.5)
		var badge_rect := Rect2(badge_pos, badge_sz)
		origin_boxes.append(badge_rect)

		zone_min.x = minf(zone_min.x, badge_rect.position.x)
		zone_min.y = minf(zone_min.y, badge_rect.position.y)
		zone_max.x = maxf(zone_max.x, badge_rect.end.x)
		zone_max.y = maxf(zone_max.y, badge_rect.end.y)

		var any_out := Vector2(badge_rect.end.x, rail_y)
		for iid_var: Variant in row_arr:
			var iid: String = str(iid_var)
			var ir: Rect2 = (nodes[iid] as Dictionary)["rect"] as Rect2
			var top_in := Vector2(ir.get_center().x, ir.position.y)
			var pts_any: PackedVector2Array = CanvasGeometry.make_rounded_ortho_path(
				[any_out, Vector2(top_in.x, rail_y), top_in],
				7.0
			)
			var akey: String = "*->%s" % iid
			var rec_any: Dictionary = {
				"key": akey,
				"from": "*",
				"to": iid,
				"label": "",
				"route": CanvasGeometry.ROUTE_ANY_BUS,
				"pts": pts_any,
				"pill_pos": Vector2(top_in.x, rail_y),
				"branch_index": -1,
			}
			routed_edges.append(rec_any)
			edge_by_key[akey] = rec_any

			zone_min.x = minf(zone_min.x, ir.position.x)
			zone_min.y = minf(zone_min.y, ir.position.y)
			zone_max.x = maxf(zone_max.x, ir.end.x)
			zone_max.y = maxf(zone_max.y, ir.end.y)

	for ed: Dictionary in routed_edges:
		if int(ed.get("route", -1)) == CanvasGeometry.ROUTE_PORTAL_RETURN:
			var f_id: String = str(ed["from"])
			if nodes.has(f_id) and bool((nodes[f_id] as Dictionary).get("is_interrupt", false)):
				var pr: Rect2 = ed["portal_rect"] as Rect2
				zone_max.x = maxf(zone_max.x, pr.end.x)
				zone_max.y = maxf(zone_max.y, pr.end.y)

	var zone_rect := Rect2(zone_min - Vector2(18.0, 28.0), (zone_max - zone_min) + Vector2(36.0, 44.0))
	return {
		"has_zone": true,
		"zone_rect": zone_rect,
		"origin_boxes": origin_boxes,
	}

#endregion
