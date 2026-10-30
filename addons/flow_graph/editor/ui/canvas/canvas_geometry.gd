@tool
extends RefCounted

## 画布 2D 几何计算、障碍物相交检测与命中判定工具集（Canvas 2D Geometry & Obstacle Math）。[br]
##
## 提供矩形周长射线锚点、圆角正交折线生成、折线-矩形碰撞检测、折线交叉计数及指针命中检测。

const ROUTE_STRAIGHT: int = 0
const ROUTE_TWIN: int = 1
const ROUTE_ORTHO_ELBOW: int = 2
const ROUTE_BT_BUS: int = 3
const ROUTE_PORTAL_RETURN: int = 4
const ROUTE_UNDER_ARC: int = 5
const ROUTE_ANY_BUS: int = 6
const ROUTE_TRANSIENT: int = 7

const BT_LEAF_KINDS: PackedStringArray = ["Action", "Condition", "Wait", "SubTree"]


#region 端口锚点、连线导引贝塞尔与射线几何

static func can_node_emit_edge(kind: String, is_bt: bool) -> bool:
	if is_bt and BT_LEAF_KINDS.has(kind):
		return false
	return true


static func can_node_accept_edge(kind: String, is_bt: bool) -> bool:
	if is_bt and kind == "Root":
		return false
	return true


static func get_output_port_world(rect: Rect2, is_vertical: bool) -> Vector2:
	return Vector2(rect.get_center().x, rect.end.y) if is_vertical else Vector2(rect.end.x, rect.get_center().y)


static func get_input_port_world(rect: Rect2, is_vertical: bool) -> Vector2:
	return Vector2(rect.get_center().x, rect.position.y) if is_vertical else Vector2(rect.position.x, rect.get_center().y)


static func build_preview_wire_points(p_start: Vector2, p_end: Vector2, is_vertical: bool, steps: int = 20) -> PackedVector2Array:
	var dist: float = p_start.distance_to(p_end)
	if dist < 2.0:
		return PackedVector2Array([p_start, p_end])
	var tang: float = clampf(dist * 0.44, 24.0, 140.0)
	var dir_vec: Vector2 = Vector2(0.0, tang) if is_vertical else Vector2(tang, 0.0)
	var c0: Vector2 = p_start + dir_vec
	var c1: Vector2 = p_end - dir_vec
	var out := PackedVector2Array()
	var n: int = maxi(6, steps)
	for i: int in range(n + 1):
		var t: float = float(i) / float(n)
		var omt: float = 1.0 - t
		var pt: Vector2 = (
			p_start * (omt * omt * omt)
			+ c0 * (3.0 * omt * omt * t)
			+ c1 * (3.0 * omt * t * t)
			+ p_end * (t * t * t)
		)
		out.append(pt)
	return out

static func rect_perimeter_point(rect: Rect2, toward: Vector2) -> Vector2:
	var c: Vector2 = rect.get_center()
	var d: Vector2 = toward - c
	if d.length_squared() < 0.001:
		return Vector2(rect.end.x, c.y)
	return ray_rect_exit(rect, c, d.normalized())


static func ray_rect_exit(rect: Rect2, origin: Vector2, dir: Vector2) -> Vector2:
	var t_min: float = INF
	if absf(dir.x) > 0.0001:
		var tx1: float = (rect.position.x - origin.x) / dir.x
		var tx2: float = (rect.end.x - origin.x) / dir.x
		if tx1 > 0.0:
			t_min = minf(t_min, tx1)
		if tx2 > 0.0:
			t_min = minf(t_min, tx2)
	if absf(dir.y) > 0.0001:
		var ty1: float = (rect.position.y - origin.y) / dir.y
		var ty2: float = (rect.end.y - origin.y) / dir.y
		if ty1 > 0.0:
			t_min = minf(t_min, ty1)
		if ty2 > 0.0:
			t_min = minf(t_min, ty2)
	if not is_finite(t_min):
		return origin
	return origin + dir * t_min


static func make_rounded_ortho_path(waypoints: Array[Vector2], radius: float) -> PackedVector2Array:
	var clean: Array[Vector2] = []
	for wp: Vector2 in waypoints:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(wp) > 0.5:
			clean.append(wp)
	if clean.size() <= 2:
		return PackedVector2Array(clean)

	var out := PackedVector2Array()
	out.append(clean[0])
	for i: int in range(1, clean.size() - 1):
		var p_prev: Vector2 = clean[i - 1]
		var p_curr: Vector2 = clean[i]
		var p_next: Vector2 = clean[i + 1]
		var v_in: Vector2 = p_curr - p_prev
		var v_out: Vector2 = p_next - p_curr
		var len_in: float = v_in.length()
		var len_out: float = v_out.length()
		if len_in < 1.0 or len_out < 1.0:
			out.append(p_curr)
			continue
		var d_in: Vector2 = v_in / len_in
		var d_out: Vector2 = v_out / len_out
		if d_in.dot(d_out) > 0.98:
			continue
		var r_use: float = minf(radius, minf(len_in * 0.45, len_out * 0.45))
		var c_start: Vector2 = p_curr - d_in * r_use
		var c_end: Vector2 = p_curr + d_out * r_use
		for s: int in range(5):
			var t: float = float(s) / 4.0
			var omt: float = 1.0 - t
			var q: Vector2 = c_start * (omt * omt) + p_curr * (2.0 * omt * t) + c_end * (t * t)
			out.append(q)
	out.append(clean[clean.size() - 1])
	return out


static func sample_quad_bezier(p0: Vector2, p1: Vector2, p2: Vector2, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = maxi(4, steps)
	for i: int in range(n + 1):
		var t: float = float(i) / float(n)
		var omt: float = 1.0 - t
		out.append(p0 * (omt * omt) + p1 * (2.0 * omt * t) + p2 * (t * t))
	return out


static func polyline_length(pts: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total


static func interpolate_polyline(pts: PackedVector2Array, ratio: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1 or ratio <= 0.0:
		return pts[0]
	if ratio >= 1.0:
		return pts[pts.size() - 1]
	var total_len: float = 0.0
	var seg_lens: Array[float] = []
	for i: int in range(pts.size() - 1):
		var d: float = pts[i].distance_to(pts[i + 1])
		seg_lens.append(d)
		total_len += d
	if total_len <= 0.001:
		return pts[0]
	var target: float = total_len * ratio
	var accum: float = 0.0
	for i: int in range(seg_lens.size()):
		var sl: float = seg_lens[i]
		if accum + sl >= target and sl > 0.0001:
			return pts[i].lerp(pts[i + 1], (target - accum) / sl)
		accum += sl
	return pts[pts.size() - 1]


static func slice_polyline(pts: PackedVector2Array, t0: float, t1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps: int = 6
	for s: int in range(steps + 1):
		out.append(interpolate_polyline(pts, lerpf(t0, t1, float(s) / float(steps))))
	return out

#endregion


#region 障碍物矩形碰撞与折线交叉度量

static func segment_intersects_rect(p0: Vector2, p1: Vector2, rect: Rect2) -> bool:
	var seg_min := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var seg_max := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
	if seg_max.x < rect.position.x or seg_min.x > rect.end.x or seg_max.y < rect.position.y or seg_min.y > rect.end.y:
		return false
	if rect.has_point(p0) or rect.has_point(p1):
		return true
	var tl: Vector2 = rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br: Vector2 = rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	if Geometry2D.segment_intersects_segment(p0, p1, tl, tr) != null:
		return true
	if Geometry2D.segment_intersects_segment(p0, p1, tr, br) != null:
		return true
	if Geometry2D.segment_intersects_segment(p0, p1, br, bl) != null:
		return true
	if Geometry2D.segment_intersects_segment(p0, p1, bl, tl) != null:
		return true
	return false


static func waypoints_hit_obstacles(
	wps: Array[Vector2],
	obstacles: Array[Rect2],
	ignore_a: Rect2,
	ignore_b: Rect2
) -> bool:
	if wps.size() < 2:
		return false
	var shrink_a: Rect2 = ignore_a.grow(-2.0)
	var shrink_b: Rect2 = ignore_b.grow(-2.0)
	for i: int in range(wps.size() - 1):
		var a: Vector2 = wps[i]
		var b: Vector2 = wps[i + 1]
		# 首尾段也禁止反向穿过起止节点自身内部
		if i > 0 and segment_intersects_rect(a, b, shrink_a):
			return true
		if i < wps.size() - 2 and segment_intersects_rect(a, b, shrink_b):
			return true
		for obs: Rect2 in obstacles:
			if segment_intersects_rect(a, b, obs):
				return true
	return false


static func count_waypoint_crossings(wps: Array[Vector2], existing_polylines: Array[PackedVector2Array]) -> int:
	if wps.size() < 2 or existing_polylines.is_empty():
		return 0
	var crossings: int = 0
	for i: int in range(wps.size() - 1):
		var a0: Vector2 = wps[i]
		var a1: Vector2 = wps[i + 1]
		for poly: PackedVector2Array in existing_polylines:
			for j: int in range(poly.size() - 1):
				var b0: Vector2 = poly[j]
				var b1: Vector2 = poly[j + 1]
				var hit: Variant = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
				if hit != null:
					var hp: Vector2 = hit as Vector2
					if hp.distance_to(a0) > 4.0 and hp.distance_to(a1) > 4.0 and hp.distance_to(b0) > 4.0 and hp.distance_to(b1) > 4.0:
						crossings += 1
						break
	return crossings

#endregion


#region 包围盒计算与指针命中检测

static func compute_world_bounds(
	nodes: Dictionary,
	node_order: Array[String],
	routed_edges: Array[Dictionary],
	has_any_zone: bool,
	any_zone_rect: Rect2
) -> Rect2:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for nid: String in node_order:
		var r: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
		min_p = min_p.min(r.position)
		max_p = max_p.max(r.end)
	for ed: Dictionary in routed_edges:
		if ed.has("portal_rect"):
			var pr: Rect2 = ed["portal_rect"] as Rect2
			min_p = min_p.min(pr.position)
			max_p = max_p.max(pr.end)
		for pt: Vector2 in (ed["pts"] as PackedVector2Array):
			min_p = min_p.min(pt)
			max_p = max_p.max(pt)
	if has_any_zone:
		min_p = min_p.min(any_zone_rect.position)
		max_p = max_p.max(any_zone_rect.end)
	if not is_finite(min_p.x):
		return Rect2(0.0, 0.0, 400.0, 300.0)
	return Rect2(min_p, max_p - min_p)


static func hit_test_node(w_pt: Vector2, nodes: Dictionary, node_order: Array[String]) -> String:
	for i: int in range(node_order.size() - 1, -1, -1):
		var nid: String = node_order[i]
		var r: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
		if r.has_point(w_pt):
			return nid
	return ""


static func hit_test_connect_handle(
	w_pt: Vector2,
	nodes: Dictionary,
	node_order: Array[String],
	is_vertical: bool = false,
	is_bt: bool = false,
	zoom: float = 1.0
) -> String:
	var hit_r: float = maxf(13.0 / maxf(zoom, 0.25), 10.0)
	var best_id: String = ""
	var best_d: float = hit_r
	for i: int in range(node_order.size() - 1, -1, -1):
		var nid: String = node_order[i]
		var rec: Dictionary = nodes[nid] as Dictionary
		if not can_node_emit_edge(str(rec.get("kind", "State")), is_bt):
			continue
		var r: Rect2 = rec["rect"] as Rect2
		var h_pt: Vector2 = get_output_port_world(r, is_vertical)
		var d: float = h_pt.distance_to(w_pt)
		if d <= best_d:
			best_d = d
			best_id = nid
	return best_id


static func hit_test_snap_target(
	w_pt: Vector2,
	src_id: String,
	nodes: Dictionary,
	node_order: Array[String],
	is_vertical: bool = false,
	zoom: float = 1.0
) -> String:
	var direct_hit: String = hit_test_node(w_pt, nodes, node_order)
	if not direct_hit.is_empty() and direct_hit != src_id:
		return direct_hit
	var port_r: float = maxf(20.0 / maxf(zoom, 0.25), 15.0)
	var grow_pad: float = maxf(12.0 / maxf(zoom, 0.25), 9.0)
	var best_id: String = ""
	var best_d: float = INF
	for i: int in range(node_order.size() - 1, -1, -1):
		var nid: String = node_order[i]
		if nid == src_id:
			continue
		var r: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
		var in_pt: Vector2 = get_input_port_world(r, is_vertical)
		var d_port: float = in_pt.distance_to(w_pt)
		if d_port <= port_r and d_port < best_d:
			best_d = d_port
			best_id = nid
		elif r.grow(grow_pad).has_point(w_pt):
			var d_center: float = r.get_center().distance_to(w_pt) * 0.5
			if d_center < best_d:
				best_d = d_center
				best_id = nid
	return best_id


static func hit_test_subgraph_badge(
	w_pt: Vector2,
	nodes: Dictionary,
	node_order: Array[String],
	live_mode: bool,
	hovered_id: String,
	zoom: float = 1.0
) -> String:
	var pad: float = maxf(4.5 / maxf(zoom, 0.25), 3.5)
	for i: int in range(node_order.size() - 1, -1, -1):
		var nid: String = node_order[i]
		var nd: Dictionary = nodes[nid] as Dictionary
		var n_params: Dictionary = nd.get("params", {}) as Dictionary
		var sub_p: String = str(nd.get("sub_graph_path", n_params.get("sub_graph_path", ""))).strip_edges()
		if sub_p.is_empty():
			continue
		var rect: Rect2 = nd["rect"] as Rect2
		var sub_x: float = rect.end.x - (29.0 if (live_mode and hovered_id == nid) else 15.0)
		var sub_y: float = rect.position.y + 4.5
		var badge_rect := Rect2(Vector2(sub_x, sub_y), Vector2(9.5, 9.5)).grow(pad)
		if badge_rect.has_point(w_pt):
			return nid
	return ""


static func hit_test_portal(w_pt: Vector2, routed_edges: Array[Dictionary]) -> String:
	for ed: Dictionary in routed_edges:
		if int(ed.get("route", -1)) == ROUTE_PORTAL_RETURN and ed.has("portal_rect"):
			if (ed["portal_rect"] as Rect2).has_point(w_pt):
				return str(ed["key"])
	return ""


static func hit_test_edge(w_pt: Vector2, routed_edges: Array[Dictionary], zoom: float = 1.0) -> String:
	var best_key: String = ""
	var best_d: float = maxf(9.0 / maxf(zoom, 0.25), 7.5)
	for ed: Dictionary in routed_edges:
		var pts: PackedVector2Array = ed["pts"] as PackedVector2Array
		for i: int in range(pts.size() - 1):
			var seg_p: Vector2 = Geometry2D.get_closest_point_to_segment(w_pt, pts[i], pts[i + 1])
			var d: float = seg_p.distance_to(w_pt)
			if d < best_d:
				best_d = d
				best_key = str(ed["key"])
	return best_key


static func minimap_screen_to_world(
	s_pt: Vector2,
	canvas_size: Vector2,
	ui_scale: float,
	world_bounds: Rect2
) -> Dictionary:
	var s: float = maxf(ui_scale, 0.75)
	if canvas_size.x < 340.0 * s or canvas_size.y < 240.0 * s:
		return {"hit": false, "world": Vector2.ZERO}
	var map_sz: Vector2 = (Vector2(168.0, 104.0) * s).round()
	var margin: Vector2 = (Vector2(14.0, 14.0) * s).round()
	var map_rect := Rect2(canvas_size - map_sz - margin, map_sz)
	if not map_rect.has_point(s_pt):
		return {"hit": false, "world": Vector2.ZERO}
	var wb: Rect2 = world_bounds.grow(40.0)
	var inner_pad: float = roundf(8.0 * s)
	var avail: Vector2 = map_sz - Vector2(inner_pad * 2.0, inner_pad * 2.0)
	var scale_m: float = minf(avail.x / maxf(wb.size.x, 1.0), avail.y / maxf(wb.size.y, 1.0))
	var offset_m: Vector2 = map_rect.position + Vector2(inner_pad, inner_pad) + (avail - wb.size * scale_m) * 0.5
	var target_world: Vector2 = wb.position + (s_pt - offset_m) / maxf(scale_m, 0.001)
	return {"hit": true, "world": target_world}

#endregion
