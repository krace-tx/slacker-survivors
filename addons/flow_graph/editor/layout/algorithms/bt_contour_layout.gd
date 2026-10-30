@tool
extends RefCounted

## 行为树逐层轮廓紧缩布局器（Reingold-Tilford Per-Depth Contour Tree Layout）。[br]
##
## 递归维护每棵子树的各深度包络轮廓，区分同组叶节点间距与跨分支组间距，并按边标签自适应列距，实现零重叠、零交叉的紧凑树形排布。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)


static func apply(graph: MermaidGraphModel, plan: Dictionary) -> void:
	var fwd_out: Dictionary = plan["fwd_out"] as Dictionary
	var roots: Array = plan["roots"] as Array
	var is_vertical: bool = (graph.direction == &"TD" or graph.direction == &"TB")

	var sizes: Dictionary = {}
	var depth_of: Dictionary = {}
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		sizes[nid] = MermaidMetrics.estimate_node_size(nd)
		depth_of[nid] = 0

	var edge_labels: Dictionary = {}
	for ed: Dictionary in graph.edges:
		edge_labels["%s->%s" % [str(ed["from"]), str(ed["to"])]] = str(ed.get("label", ""))

	var visited_d: Dictionary = {}
	for r_var: Variant in roots:
		var rid: String = str(r_var)
		if not visited_d.has(rid):
			_assign_depth(rid, 0, fwd_out, visited_d, depth_of)
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		if not visited_d.has(nid):
			_assign_depth(nid, 0, fwd_out, visited_d, depth_of)

	var max_depth: int = 0
	var max_w_at_depth: Dictionary = {}
	var max_lbl_at_depth: Dictionary = {}
	for k: Variant in depth_of.keys():
		var nid: String = str(k)
		var d: int = int(depth_of[nid])
		max_depth = maxi(max_depth, d)
		var w: float = (sizes[nid] as Vector2).x
		max_w_at_depth[d] = maxf(float(max_w_at_depth.get(d, MermaidMetrics.NODE_MIN_W)), w)
		for ch_v: Variant in (fwd_out.get(nid, []) as Array):
			var lbl_s: String = str(edge_labels.get("%s->%s" % [nid, str(ch_v)], ""))
			if not lbl_s.begins_with("#"):
				max_lbl_at_depth[d] = maxf(float(max_lbl_at_depth.get(d, 0.0)), MermaidMetrics.estimate_text_px(lbl_s))

	var layer_primary: Dictionary = {}
	var accum: float = 0.0
	for d: int in range(max_depth + 1):
		layer_primary[d] = accum
		var h_gap: float = maxf(88.0, float(max_lbl_at_depth.get(d, 0.0)) + 52.0)
		accum += (MermaidMetrics.NODE_HEIGHT + 78.0) if is_vertical else (float(max_w_at_depth.get(d, 180.0)) + h_gap)

	var cross_center: Dictionary = {}
	var visited_c: Dictionary = {}
	var forest_contour: Dictionary = {}

	var ordered_starts: Array[String] = []
	for r_var: Variant in roots:
		ordered_starts.append(str(r_var))
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		if not ordered_starts.has(nid):
			ordered_starts.append(nid)

	for start_id: String in ordered_starts:
		if visited_c.has(start_id):
			continue
		var sub_info: Dictionary = _contour_dfs(start_id, 0, fwd_out, sizes, visited_c, cross_center, is_vertical)
		var sub_contour: Dictionary = sub_info["contour"] as Dictionary
		if not forest_contour.is_empty():
			var shift_f: float = _compute_contour_separation(forest_contour, sub_contour, 40.0)
			if absf(shift_f) > 0.001:
				_shift_subtree_cross(sub_info["members"] as Array, shift_f, cross_center, sub_contour)
		_merge_contours_into(forest_contour, sub_contour)

	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		var sz: Vector2 = sizes[nid] as Vector2
		var d: int = int(depth_of.get(nid, 0))
		var p_coord: float = float(layer_primary.get(d, 0.0))
		var c_coord: float = float(cross_center.get(nid, 0.0))
		var pos: Vector2 = (
			Vector2(c_coord - sz.x * 0.5, p_coord)
			if is_vertical
			else Vector2(p_coord, c_coord - sz.y * 0.5)
		)
		graph.set_node_pos(nid, pos)


static func _assign_depth(
	nid: String,
	d: int,
	fwd_out: Dictionary,
	visited: Dictionary,
	depth_of: Dictionary
) -> void:
	visited[nid] = true
	depth_of[nid] = d
	for c_var: Variant in (fwd_out.get(nid, []) as Array):
		var cid: String = str(c_var)
		if not visited.has(cid):
			_assign_depth(cid, d + 1, fwd_out, visited, depth_of)


static func _contour_dfs(
	nid: String,
	depth: int,
	fwd_out: Dictionary,
	sizes: Dictionary,
	visited: Dictionary,
	cross_center: Dictionary,
	is_vertical: bool
) -> Dictionary:
	visited[nid] = true
	var sz: Vector2 = sizes[nid] as Vector2
	var half_span: float = (sz.x if is_vertical else sz.y) * 0.5
	var raw_children: Array = fwd_out.get(nid, []) as Array

	var child_infos: Array[Dictionary] = []
	var merged_child_contour: Dictionary = {}
	var all_members: Array = [nid]

	for i: int in range(raw_children.size()):
		var cid: String = str(raw_children[i])
		if visited.has(cid):
			continue
		var c_info: Dictionary = _contour_dfs(cid, depth + 1, fwd_out, sizes, visited, cross_center, is_vertical)
		var c_contour: Dictionary = c_info["contour"] as Dictionary
		var prev_had_kids: bool = (not child_infos.is_empty()) and bool(child_infos[child_infos.size() - 1]["has_kids"])
		var cur_has_kids: bool = bool(c_info["has_kids"])
		var gap: float = (32.0 if (prev_had_kids or cur_has_kids) else 18.0) if not is_vertical else (36.0 if (prev_had_kids or cur_has_kids) else 24.0)

		if not merged_child_contour.is_empty():
			var shift: float = _compute_contour_separation(merged_child_contour, c_contour, gap)
			if absf(shift) > 0.001:
				_shift_subtree_cross(c_info["members"] as Array, shift, cross_center, c_contour)

		_merge_contours_into(merged_child_contour, c_contour)
		child_infos.append(c_info)
		for m_var: Variant in (c_info["members"] as Array):
			all_members.append(m_var)

	var my_center: float = 0.0
	if not child_infos.is_empty():
		var first_id: String = str(child_infos[0]["id"])
		var last_id: String = str(child_infos[child_infos.size() - 1]["id"])
		my_center = (float(cross_center[first_id]) + float(cross_center[last_id])) * 0.5

	cross_center[nid] = my_center
	merged_child_contour[depth] = Vector2(my_center - half_span, my_center + half_span)

	return {
		"id": nid,
		"has_kids": not child_infos.is_empty(),
		"contour": merged_child_contour,
		"members": all_members,
	}


static func _compute_contour_separation(left_contour: Dictionary, right_contour: Dictionary, min_gap: float) -> float:
	var required_shift: float = -INF
	var has_overlap_depth: bool = false
	for d_var: Variant in right_contour.keys():
		if left_contour.has(d_var):
			has_overlap_depth = true
			var l_bounds: Vector2 = left_contour[d_var] as Vector2
			var r_bounds: Vector2 = right_contour[d_var] as Vector2
			required_shift = maxf(required_shift, (l_bounds.y + min_gap) - r_bounds.x)
	if not has_overlap_depth:
		var max_left: float = -INF
		for k1: Variant in left_contour.keys():
			max_left = maxf(max_left, (left_contour[k1] as Vector2).y)
		var min_right: float = INF
		for k2: Variant in right_contour.keys():
			min_right = minf(min_right, (right_contour[k2] as Vector2).x)
		if is_finite(max_left) and is_finite(min_right):
			return (max_left + min_gap) - min_right
		return 0.0
	return required_shift


static func _shift_subtree_cross(
	members: Array,
	delta: float,
	cross_center: Dictionary,
	contour: Dictionary
) -> void:
	for m_var: Variant in members:
		var mid: String = str(m_var)
		cross_center[mid] = float(cross_center.get(mid, 0.0)) + delta
	for d_var: Variant in contour.keys():
		var b: Vector2 = contour[d_var] as Vector2
		contour[d_var] = Vector2(b.x + delta, b.y + delta)


static func _merge_contours_into(target: Dictionary, addition: Dictionary) -> void:
	for d_var: Variant in addition.keys():
		var add_b: Vector2 = addition[d_var] as Vector2
		if target.has(d_var):
			var cur_b: Vector2 = target[d_var] as Vector2
			target[d_var] = Vector2(minf(cur_b.x, add_b.x), maxf(cur_b.y, add_b.y))
		else:
			target[d_var] = add_b
