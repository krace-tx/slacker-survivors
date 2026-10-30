@tool
extends RefCounted

## Sugiyama 哑节点通道与通用 DAG 端口分槽正交路由器（DAG Channel & Port-Slotted Elbow Router）。[br]
##
## 负责四向端口扇出排序、Sugiyama 跨层哑节点走廊拼接，以及无遮挡单向直连与 Z/N 型正交折线路由。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)


#region 四向端口扇出排序表

static func build_directional_port_maps(
	graph: MermaidGraphModel,
	nodes: Dictionary,
	already_routed: Dictionary,
	interrupt_redirects: Dictionary,
	transient_only: Dictionary,
	arch: StringName
) -> Dictionary:
	var east_out: Dictionary = {}
	var west_out: Dictionary = {}
	var south_out: Dictionary = {}
	var north_out: Dictionary = {}

	if arch == MermaidMetrics.ARCHETYPE_BT_TREE:
		return {"east": east_out, "west": west_out, "south": south_out, "north": north_out}

	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		var key: String = "%s->%s" % [f, t]
		if f == "*" or f == t or not nodes.has(f) or not nodes.has(t):
			continue
		if already_routed.has(key) or interrupt_redirects.has(key) or transient_only.has(key):
			continue
		var rf: Rect2 = (nodes[f] as Dictionary)["rect"] as Rect2
		var rt: Rect2 = (nodes[t] as Dictionary)["rect"] as Rect2
		if rt.position.x >= rf.end.x + 16.0:
			if not east_out.has(f):
				east_out[f] = []
			(east_out[f] as Array).append(t)
		elif rf.position.x >= rt.end.x + 16.0:
			if not west_out.has(f):
				west_out[f] = []
			(west_out[f] as Array).append(t)
		elif rt.position.y >= rf.end.y + 16.0:
			if not south_out.has(f):
				south_out[f] = []
			(south_out[f] as Array).append(t)
		elif rf.position.y >= rt.end.y + 16.0:
			if not north_out.has(f):
				north_out[f] = []
			(north_out[f] as Array).append(t)

	for m_y: Dictionary in [east_out, west_out]:
		for fk: Variant in m_y.keys():
			(m_y[fk] as Array).sort_custom(func(a: Variant, b: Variant) -> bool:
				return ((nodes[str(a)] as Dictionary)["rect"] as Rect2).get_center().y < ((nodes[str(b)] as Dictionary)["rect"] as Rect2).get_center().y
			)
	for m_x: Dictionary in [south_out, north_out]:
		for fk2: Variant in m_x.keys():
			(m_x[fk2] as Array).sort_custom(func(a: Variant, b: Variant) -> bool:
				return ((nodes[str(a)] as Dictionary)["rect"] as Rect2).get_center().x < ((nodes[str(b)] as Dictionary)["rect"] as Rect2).get_center().x
			)

	return {"east": east_out, "west": west_out, "south": south_out, "north": north_out}

#endregion


#region Sugiyama 哑节点跨层走廊与通用单向直连/折线

static func try_route_sugiyama_corridor(
	key: String,
	f: String,
	t: String,
	lbl: String,
	rf: Rect2,
	rt: Rect2,
	edge_wps_map: Dictionary,
	is_vertical: bool
) -> Dictionary:
	if not edge_wps_map.has(key):
		return {"ok": false}
	var mid_wps: Array = edge_wps_map[key] as Array
	if mid_wps.is_empty():
		return {"ok": false}
	var full_wps: Array[Vector2] = build_sugiyama_corridor_waypoints(rf, rt, mid_wps, is_vertical)
	var pts_wp: PackedVector2Array = CanvasGeometry.make_rounded_ortho_path(full_wps, 12.0)
	var rec_wp: Dictionary = {
		"key": key,
		"from": f,
		"to": t,
		"label": lbl,
		"route": CanvasGeometry.ROUTE_ORTHO_ELBOW,
		"pts": pts_wp,
		"pill_pos": CanvasGeometry.interpolate_polyline(pts_wp, 0.5),
		"branch_index": -1,
	}
	return {"ok": true, "record": rec_wp}


static func build_sugiyama_corridor_waypoints(
	rf: Rect2,
	rt: Rect2,
	mid_wps: Array,
	is_vertical: bool
) -> Array[Vector2]:
	var first_wp: Vector2 = mid_wps[0] as Vector2
	var last_wp: Vector2 = mid_wps[mid_wps.size() - 1] as Vector2
	var out: Array[Vector2] = []
	if not is_vertical:
		var p_s := Vector2(rf.end.x, rf.get_center().y)
		var p_e := Vector2(rt.position.x, rt.get_center().y)
		var e1_x: float = (p_s.x + first_wp.x) * 0.5
		var e2_x: float = (last_wp.x + p_e.x) * 0.5
		out.append(p_s)
		out.append(Vector2(e1_x, p_s.y))
		out.append(Vector2(e1_x, first_wp.y))
		for mwp_var: Variant in mid_wps:
			out.append(mwp_var as Vector2)
		out.append(Vector2(e2_x, last_wp.y))
		out.append(Vector2(e2_x, p_e.y))
		out.append(p_e)
	else:
		var pv_s := Vector2(rf.get_center().x, rf.end.y)
		var pv_e := Vector2(rt.get_center().x, rt.position.y)
		var e1_y: float = (pv_s.y + first_wp.y) * 0.5
		var e2_y: float = (last_wp.y + pv_e.y) * 0.5
		out.append(pv_s)
		out.append(Vector2(pv_s.x, e1_y))
		out.append(Vector2(first_wp.x, e1_y))
		for mwp_var2: Variant in mid_wps:
			out.append(mwp_var2 as Vector2)
		out.append(Vector2(last_wp.x, e2_y))
		out.append(Vector2(pv_e.x, e2_y))
		out.append(pv_e)
	return out


static func try_route_clean_direct_or_elbow(
	f: String,
	t: String,
	rf: Rect2,
	rt: Rect2,
	port_maps: Dictionary,
	obstacles: Array[Rect2]
) -> Dictionary:
	var cf: Vector2 = rf.get_center()
	var ct: Vector2 = rt.get_center()
	var dx: float = ct.x - cf.x
	var dy: float = ct.y - cf.y

	# 1. 同行水平直连
	if absf(dy) <= 18.0 and (rt.position.x >= rf.end.x + 8.0 or rf.position.x >= rt.end.x + 8.0):
		var y_line: float = clampf((cf.y + ct.y) * 0.5, maxf(rf.position.y, rt.position.y) + 8.0, minf(rf.end.y, rt.end.y) - 8.0)
		var pa := Vector2(rf.end.x if dx > 0.0 else rf.position.x, y_line)
		var pb := Vector2(rt.position.x if dx > 0.0 else rt.end.x, y_line)
		var wps_s: Array[Vector2] = [pa, pb]
		if not CanvasGeometry.waypoints_hit_obstacles(wps_s, obstacles, rf, rt):
			return {
				"ok": true,
				"route": CanvasGeometry.ROUTE_STRAIGHT,
				"pts": PackedVector2Array(wps_s),
				"pill_pos": (pa + pb) * 0.5,
			}

	# 2. 同列垂直直连（偏向左侧 30% 避让顶部右侧回流胶囊）
	if absf(dx) <= 28.0 and (rt.position.y >= rf.end.y + 8.0 or rf.position.y >= rt.end.y + 8.0):
		var ov_l: float = maxf(rf.position.x, rt.position.x) + 12.0
		var ov_r: float = minf(rf.end.x, rt.end.x) - 12.0
		if ov_r > ov_l:
			var x_line: float = ov_l + (ov_r - ov_l) * 0.30
			var pa_v := Vector2(x_line, rf.end.y if dy > 0.0 else rf.position.y)
			var pb_v := Vector2(x_line, rt.position.y if dy > 0.0 else rt.end.y)
			var wps_sv: Array[Vector2] = [pa_v, pb_v]
			if not CanvasGeometry.waypoints_hit_obstacles(wps_sv, obstacles, rf, rt):
				return {
					"ok": true,
					"route": CanvasGeometry.ROUTE_STRAIGHT,
					"pts": PackedVector2Array(wps_sv),
					"pill_pos": (pa_v + pb_v) * 0.5,
				}

	# 3. 东/西分槽正交 Z 型折线
	var east_map: Dictionary = port_maps["east"] as Dictionary
	var west_map: Dictionary = port_maps["west"] as Dictionary
	if rt.position.x >= rf.end.x + 16.0 or rf.position.x >= rt.end.x + 16.0:
		var is_east: bool = rt.position.x >= rf.end.x + 16.0
		var side_map: Dictionary = east_map if is_east else west_map
		var siblings: Array = side_map.get(f, [t]) as Array
		var s_idx: int = maxi(0, siblings.find(t))
		var s_cnt: int = maxi(1, siblings.size())
		var slot_off: float = (float(s_idx) - float(s_cnt - 1) * 0.5) * 11.0
		var y_exit: float = clampf(cf.y + slot_off, rf.position.y + 8.0, rf.end.y - 8.0)
		var p_s := Vector2(rf.end.x if is_east else rf.position.x, y_exit)
		var p_e := Vector2(rt.position.x if is_east else rt.end.x, ct.y)
		var ratio_x: float = clampf(0.42 + (float(s_idx) - float(s_cnt - 1) * 0.5) * 0.08, 0.25, 0.65)
		var elbow_x: float = lerpf(p_s.x, p_e.x, ratio_x)
		var wps_el: Array[Vector2] = [p_s, Vector2(elbow_x, p_s.y), Vector2(elbow_x, p_e.y), p_e]
		if not CanvasGeometry.waypoints_hit_obstacles(wps_el, obstacles, rf, rt):
			return {
				"ok": true,
				"route": CanvasGeometry.ROUTE_ORTHO_ELBOW,
				"pts": CanvasGeometry.make_rounded_ortho_path(wps_el, 10.0),
				"pill_pos": Vector2((elbow_x + p_e.x) * 0.5, p_e.y),
			}

	# 4. 南/北分槽正交 N 型折线
	var south_map: Dictionary = port_maps["south"] as Dictionary
	var north_map: Dictionary = port_maps["north"] as Dictionary
	if rt.position.y >= rf.end.y + 16.0 or rf.position.y >= rt.end.y + 16.0:
		var is_south: bool = rt.position.y >= rf.end.y + 16.0
		var v_map: Dictionary = south_map if is_south else north_map
		var siblings_v: Array = v_map.get(f, [t]) as Array
		var sv_idx: int = maxi(0, siblings_v.find(t))
		var sv_cnt: int = maxi(1, siblings_v.size())
		var slot_x_off: float = (float(sv_idx) - float(sv_cnt - 1) * 0.5) * 16.0
		var x_exit: float = clampf(rf.position.x + rf.size.x * 0.32 + slot_x_off, rf.position.x + 12.0, rf.end.x - 12.0)
		var x_enter: float = rt.position.x + rt.size.x * 0.32
		var pv_s := Vector2(x_exit, rf.end.y if is_south else rf.position.y)
		var pv_e := Vector2(x_enter, rt.position.y if is_south else rt.end.y)
		var elbow_y: float = lerpf(pv_s.y, pv_e.y, 0.45)
		var wps_elv: Array[Vector2] = [pv_s, Vector2(pv_s.x, elbow_y), Vector2(pv_e.x, elbow_y), pv_e]
		if not CanvasGeometry.waypoints_hit_obstacles(wps_elv, obstacles, rf, rt):
			return {
				"ok": true,
				"route": CanvasGeometry.ROUTE_ORTHO_ELBOW,
				"pts": CanvasGeometry.make_rounded_ortho_path(wps_elv, 10.0),
				"pill_pos": Vector2((pv_s.x + pv_e.x) * 0.5, elbow_y),
			}

	return {"ok": false}

#endregion
