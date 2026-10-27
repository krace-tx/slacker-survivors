@tool
extends RefCounted

## 行为树正交分叉主干总线路由器（Behavior Tree Orthogonal Bus & Order Badge Router）。[br]
##
## 为 BT 父节点与子节点构建共享正交分叉主干总线，并在兄弟数 `>= 2` 时注入 1-based `bt_child_order`（`#1, #2, ...`）及可选 `bt_weight` 权重元数据。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)


## 提取 BT 图中所有父节点的有序子边映射 `{parent_id: Array[String]}`。
static func build_bt_children_order_map(graph: MermaidGraphModel, nodes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if graph == null or graph.resolve_effective_schema() != MermaidGraphModel.SCHEMA_BT:
		return out
	for ed: Dictionary in graph.edges:
		if bool(ed.get("discovered", false)):
			continue
		var f: String = str(ed.get("from", ""))
		var t: String = str(ed.get("to", ""))
		if f == "*" or f == t or not nodes.has(f) or not nodes.has(t):
			continue
		if not out.has(f):
			out[f] = []
		var arr: Array = out[f] as Array
		if not arr.has(t):
			arr.append(t)
	return out


## 尝试按 BT 正交分叉主干总线构建路径；若子节点因手动拖拽逆向折叠遮挡则返回 `{"ok": false}` 交由外层避障器兜底。
static func try_route_bt_bus(
	ed: Dictionary,
	key: String,
	f: String,
	t: String,
	lbl: String,
	rf: Rect2,
	rt: Rect2,
	ch_arr: Array,
	target_node_rec: Dictionary,
	is_vertical: bool,
	obstacles: Array[Rect2]
) -> Dictionary:
	var wps_bt: Array[Vector2] = []
	var tap_badge_pos := Vector2.ZERO

	if not is_vertical:
		if rt.position.x < rf.end.x + 10.0:
			return {"ok": false}
		var p_out := Vector2(rf.end.x, rf.get_center().y)
		var p_in := Vector2(rt.position.x, rt.get_center().y)
		var bus_x: float = rf.end.x + clampf((rt.position.x - rf.end.x) * 0.35, 22.0, 38.0)
		wps_bt = [p_out, Vector2(bus_x, p_out.y), Vector2(bus_x, p_in.y), p_in]
		tap_badge_pos = Vector2(lerpf(bus_x, p_in.x - 6.0, 0.5), p_in.y)
	else:
		if rt.position.y < rf.end.y + 10.0:
			return {"ok": false}
		var p_out_v := Vector2(rf.get_center().x, rf.end.y)
		var p_in_v := Vector2(rt.get_center().x, rt.position.y)
		var bus_y: float = rf.end.y + clampf((rt.position.y - rf.end.y) * 0.38, 22.0, 36.0)
		wps_bt = [p_out_v, Vector2(p_out_v.x, bus_y), Vector2(p_in_v.x, bus_y), p_in_v]
		tap_badge_pos = Vector2(p_in_v.x, lerpf(bus_y, p_in_v.y - 6.0, 0.5))

	if CanvasGeometry.waypoints_hit_obstacles(wps_bt, obstacles, rf, rt):
		return {"ok": false}

	var b_idx: int = ch_arr.find(t)
	var branch_num: int = (b_idx + 1) if (ch_arr.size() >= 2 and b_idx >= 0) else -1
	var clean_bt_lbl: String = _strip_redundant_order_label(lbl, branch_num)
	var pts_bt: PackedVector2Array = CanvasGeometry.make_rounded_ortho_path(wps_bt, 8.0)

	var rec_bt: Dictionary = {
		"key": key,
		"from": f,
		"to": t,
		"label": clean_bt_lbl,
		"route": CanvasGeometry.ROUTE_BT_BUS,
		"pts": pts_bt,
		"pill_pos": CanvasGeometry.interpolate_polyline(pts_bt, 0.72),
		"branch_index": branch_num,
		"tap_badge_pos": tap_badge_pos,
	}
	annotate_bt_metadata(rec_bt, ed, target_node_rec, ch_arr, t)
	return {
		"ok": true,
		"record": rec_bt,
	}


## 为任何属于 BT 多子分支的有向边补齐 `bt_child_order`（1-based）与 `bt_weight` 元数据。
static func annotate_bt_metadata(
	routed_rec: Dictionary,
	raw_edge: Dictionary,
	target_node_rec: Dictionary,
	siblings: Array,
	target_id: String
) -> void:
	var idx: int = siblings.find(target_id)
	if siblings.size() >= 2 and idx >= 0:
		var order_1based: int = idx + 1
		routed_rec["bt_child_order"] = order_1based
		routed_rec["branch_index"] = order_1based
		if not routed_rec.has("tap_badge_pos"):
			var pts: PackedVector2Array = routed_rec.get("pts", PackedVector2Array()) as PackedVector2Array
			if pts.size() >= 2:
				routed_rec["tap_badge_pos"] = CanvasGeometry.interpolate_polyline(pts, 0.82)
		var cur_lbl: String = str(routed_rec.get("label", ""))
		routed_rec["label"] = _strip_redundant_order_label(cur_lbl, order_1based)

	var e_params: Dictionary = raw_edge.get("params", {}) as Dictionary if raw_edge.get("params", {}) is Dictionary else {}
	var n_params: Dictionary = target_node_rec.get("params", {}) as Dictionary if target_node_rec.get("params", {}) is Dictionary else {}
	if e_params.has("weight"):
		routed_rec["bt_weight"] = float(e_params["weight"])
	elif n_params.has("weight"):
		routed_rec["bt_weight"] = float(n_params["weight"])


static func _strip_redundant_order_label(lbl: String, branch_num: int) -> String:
	if branch_num > 0 and (lbl == ("#%d" % branch_num) or (lbl.begins_with("#") and lbl.substr(1).is_valid_int())):
		return ""
	return lbl
