@tool
extends RefCounted

## 边路由矩形障碍物检测、净空巷道提取与零碰撞绕行走廊搜索（Obstacle Avoidance & Detour Search）。[br]
##
## 负责节点/回流胶囊包围盒碰撞排除、行间/列间净空通道扫描，以及多候选外围拱桥与内巷评分择优。

const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)


#region 障碍物包围盒收集与探测

static func rect_hits_other_nodes(
	probe: Rect2,
	self_id: String,
	nodes: Dictionary,
	node_order: Array[String]
) -> bool:
	for nid: String in node_order:
		if nid == self_id:
			continue
		var r: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
		if probe.intersects(r.grow(6.0)):
			return true
	return false


static func gather_obstacles_excluding(
	from_id: String,
	to_id: String,
	nodes: Dictionary,
	node_order: Array[String],
	portal_obstacles: Array[Rect2]
) -> Array[Rect2]:
	var obs: Array[Rect2] = []
	for nid: String in node_order:
		if nid == from_id or nid == to_id:
			continue
		var r: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
		obs.append(r.grow(6.0))
	for pr: Rect2 in portal_obstacles:
		obs.append(pr)
	return obs

#endregion


#region 行间与列间净空正交巷道提取

static func collect_horizontal_alleys(
	nodes: Dictionary,
	node_order: Array[String],
	portal_obstacles: Array[Rect2]
) -> Array[float]:
	var bands: Array[Vector2] = []
	for nid: String in node_order:
		var r: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
		bands.append(Vector2(r.position.y, r.end.y))
	for pr: Rect2 in portal_obstacles:
		bands.append(Vector2(pr.position.y, pr.end.y))
	if bands.is_empty():
		return []
	bands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var merged: Array[Vector2] = [bands[0]]
	for i: int in range(1, bands.size()):
		var cur: Vector2 = bands[i]
		var last: Vector2 = merged[merged.size() - 1]
		if cur.x <= last.y + 14.0:
			merged[merged.size() - 1] = Vector2(last.x, maxf(last.y, cur.y))
		else:
			merged.append(cur)

	var alleys: Array[float] = []
	for i: int in range(merged.size() - 1):
		alleys.append((merged[i].y + merged[i + 1].x) * 0.5)
	return alleys


static func collect_vertical_alleys(
	nodes: Dictionary,
	node_order: Array[String],
	portal_obstacles: Array[Rect2]
) -> Array[float]:
	var bands: Array[Vector2] = []
	for nid: String in node_order:
		var r: Rect2 = (nodes[nid] as Dictionary)["rect"] as Rect2
		bands.append(Vector2(r.position.x, r.end.x))
	for pr: Rect2 in portal_obstacles:
		bands.append(Vector2(pr.position.x, pr.end.x))
	if bands.is_empty():
		return []
	bands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var merged: Array[Vector2] = [bands[0]]
	for i: int in range(1, bands.size()):
		var cur: Vector2 = bands[i]
		var last: Vector2 = merged[merged.size() - 1]
		if cur.x <= last.y + 18.0:
			merged[merged.size() - 1] = Vector2(last.x, maxf(last.y, cur.y))
		else:
			merged.append(cur)

	var alleys: Array[float] = []
	for i: int in range(merged.size() - 1):
		alleys.append((merged[i].y + merged[i + 1].x) * 0.5)
	return alleys

#endregion


#region 零碰撞最少交叉正交绕行走廊搜索

static func route_obstacle_free_detour(
	_f: String,
	_t: String,
	rf: Rect2,
	rt: Rect2,
	obstacles: Array[Rect2],
	existing_polylines: Array[PackedVector2Array],
	row_alleys_y: Array[float],
	col_alleys_x: Array[float],
	corridor_lanes: Dictionary
) -> Dictionary:
	## 评估北外围、南外围、西/东外围及所有净空行间/列间巷道候选路径，选取零障碍相交且交叉数最小的正交折线。
	var span_min_x: float = minf(rf.position.x, rt.position.x) - 20.0
	var span_max_x: float = maxf(rf.end.x, rt.end.x) + 20.0
	var span_min_y: float = minf(rf.position.y, rt.position.y) - 20.0
	var span_max_y: float = maxf(rf.end.y, rt.end.y) + 20.0

	var env_top: float = minf(rf.position.y, rt.position.y)
	var env_bot: float = maxf(rf.end.y, rt.end.y)
	var env_left: float = minf(rf.position.x, rt.position.x)
	var env_right: float = maxf(rf.end.x, rt.end.x)

	for obs: Rect2 in obstacles:
		if obs.end.x >= span_min_x and obs.position.x <= span_max_x:
			if obs.end.y >= span_min_y - 70.0 and obs.position.y <= span_max_y + 70.0:
				env_top = minf(env_top, obs.position.y)
				env_bot = maxf(env_bot, obs.end.y)
		if obs.end.y >= span_min_y and obs.position.y <= span_max_y:
			if obs.end.x >= span_min_x - 90.0 and obs.position.x <= span_max_x + 90.0:
				env_left = minf(env_left, obs.position.x)
				env_right = maxf(env_right, obs.end.x)

	var candidates: Array[Dictionary] = []
	var sx_top: float = rf.position.x + rf.size.x * 0.30
	var ex_top: float = rt.position.x + rt.size.x * 0.30
	var sx_bot: float = rf.position.x + rf.size.x * 0.36
	var ex_bot: float = rt.position.x + rt.size.x * 0.36

	# 候选 1: 北侧拱桥走廊 (Over-Arch)
	var lane_n: int = int(corridor_lanes.get("north", 0))
	var sx_top_n: float = clampf(sx_top + float(lane_n) * 11.0, rf.position.x + 12.0, rf.end.x - 12.0)
	var ex_top_n: float = clampf(ex_top + float(lane_n) * 11.0, rt.position.x + 12.0, rt.end.x - 12.0)
	var y_north: float = env_top - 24.0 - float(lane_n) * 16.0
	candidates.append({
		"lane_key": "north",
		"wps": [Vector2(sx_top_n, rf.position.y), Vector2(sx_top_n, y_north), Vector2(ex_top_n, y_north), Vector2(ex_top_n, rt.position.y)],
		"pill": Vector2((sx_top_n + ex_top_n) * 0.5, y_north),
	})

	# 候选 2: 南侧拱桥走廊 (Under-Arch)
	var lane_s: int = int(corridor_lanes.get("south", 0))
	var sx_bot_s: float = clampf(sx_bot + float(lane_s) * 11.0, rf.position.x + 12.0, rf.end.x - 12.0)
	var ex_bot_s: float = clampf(ex_bot + float(lane_s) * 11.0, rt.position.x + 12.0, rt.end.x - 12.0)
	var y_south: float = env_bot + 26.0 + float(lane_s) * 16.0
	candidates.append({
		"lane_key": "south",
		"wps": [Vector2(sx_bot_s, rf.end.y), Vector2(sx_bot_s, y_south), Vector2(ex_bot_s, y_south), Vector2(ex_bot_s, rt.end.y)],
		"pill": Vector2((sx_bot_s + ex_bot_s) * 0.5, y_south),
	})

	# 候选 3: 所有行间净空水平巷道 (Inter-Row Alleys)
	for ai: int in range(row_alleys_y.size()):
		var lk_a: String = "alley_y_%d" % ai
		var l_off: float = float(int(corridor_lanes.get(lk_a, 0))) * 10.0
		var ay: float = row_alleys_y[ai] + l_off
		var p_start_a := Vector2(sx_bot, rf.end.y) if ay > rf.get_center().y else Vector2(sx_top, rf.position.y)
		var p_end_a := Vector2(ex_top, rt.position.y) if ay < rt.get_center().y else Vector2(ex_bot, rt.end.y)
		candidates.append({
			"lane_key": lk_a,
			"wps": [p_start_a, Vector2(p_start_a.x, ay), Vector2(p_end_a.x, ay), p_end_a],
			"pill": Vector2((p_start_a.x + p_end_a.x) * 0.5, ay),
		})

	# 候选 4: 西侧/东侧及列间净空垂直巷道
	var lane_w: int = int(corridor_lanes.get("west", 0))
	var x_west: float = env_left - 28.0 - float(lane_w) * 16.0
	candidates.append({
		"lane_key": "west",
		"wps": [Vector2(rf.position.x, rf.get_center().y), Vector2(x_west, rf.get_center().y), Vector2(x_west, rt.get_center().y), Vector2(rt.position.x, rt.get_center().y)],
		"pill": Vector2(x_west, (rf.get_center().y + rt.get_center().y) * 0.5),
	})

	var lane_e: int = int(corridor_lanes.get("east", 0))
	var x_east: float = env_right + 28.0 + float(lane_e) * 16.0
	candidates.append({
		"lane_key": "east",
		"wps": [Vector2(rf.end.x, rf.get_center().y), Vector2(x_east, rf.get_center().y), Vector2(x_east, rt.get_center().y), Vector2(rt.end.x, rt.get_center().y)],
		"pill": Vector2(x_east, (rf.get_center().y + rt.get_center().y) * 0.5),
	})

	for ci: int in range(col_alleys_x.size()):
		var lk_c: String = "alley_x_%d" % ci
		var cx_off: float = float(int(corridor_lanes.get(lk_c, 0))) * 10.0
		var ax: float = col_alleys_x[ci] + cx_off
		var ps_c := Vector2(rf.end.x, rf.get_center().y) if ax > rf.get_center().x else Vector2(rf.position.x, rf.get_center().y)
		var pe_c := Vector2(rt.position.x, rt.get_center().y) if ax < rt.get_center().x else Vector2(rt.end.x, rt.get_center().y)
		candidates.append({
			"lane_key": lk_c,
			"wps": [ps_c, Vector2(ax, ps_c.y), Vector2(ax, pe_c.y), pe_c],
			"pill": Vector2(ax, (ps_c.y + pe_c.y) * 0.5),
		})

	var best_idx: int = -1
	var best_score: float = INF
	for idx: int in range(candidates.size()):
		var cand: Dictionary = candidates[idx]
		var wps_raw: Array = cand["wps"] as Array
		var wps_typed: Array[Vector2] = []
		for pt_v: Variant in wps_raw:
			wps_typed.append(pt_v as Vector2)
		if CanvasGeometry.waypoints_hit_obstacles(wps_typed, obstacles, rf, rt):
			continue
		var cross_cnt: int = CanvasGeometry.count_waypoint_crossings(wps_typed, existing_polylines)
		var path_len: float = 0.0
		for s_i: int in range(wps_typed.size() - 1):
			path_len += wps_typed[s_i].distance_to(wps_typed[s_i + 1])
		var score: float = float(cross_cnt) * 650.0 + path_len + float(wps_typed.size() - 2) * 32.0
		if score < best_score:
			best_score = score
			best_idx = idx

	# 若极端包围下所有内巷均被阻挡，必定采纳保证无碰撞的外包络北/南大拱桥
	if best_idx < 0:
		best_idx = 0 if absf(rf.position.y - env_top) <= absf(env_bot - rf.end.y) else 1

	var chosen: Dictionary = candidates[best_idx]
	var chosen_lk: String = str(chosen["lane_key"])
	corridor_lanes[chosen_lk] = int(corridor_lanes.get(chosen_lk, 0)) + 1
	var final_wps: Array[Vector2] = []
	for pt_v2: Variant in (chosen["wps"] as Array):
		final_wps.append(pt_v2 as Vector2)

	return {
		"pts": CanvasGeometry.make_rounded_ortho_path(final_wps, 11.0),
		"pill_pos": chosen["pill"] as Vector2,
	}

#endregion
