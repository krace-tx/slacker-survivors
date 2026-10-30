@tool
extends RefCounted

## 通用有向管线布局器（Four-Phase Sugiyama DAG Layout with Dummy Corridors）。[br]
##
## 实现最长路径分层、跨层虚拟哑节点（`__dm_*`）双锚点正交走廊插入、12 轮重心 + 收敛式邻位交换消交叉，以及边标签感知列宽与父子共线对齐。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)


static func apply(graph: MermaidGraphModel, plan: Dictionary) -> void:
	var raw_fwd_out: Dictionary = plan["fwd_out"] as Dictionary
	var n_real: int = graph.nodes.size()
	var is_vertical: bool = (graph.direction == &"TD" or graph.direction == &"TB")

	var sizes: Dictionary = {}
	var layer_of: Dictionary = {}
	var orig_order: Dictionary = {}
	var real_set: Dictionary = {}

	for i: int in range(n_real):
		var nid: String = str(graph.nodes[i]["id"])
		sizes[nid] = MermaidMetrics.estimate_node_size(graph.nodes[i])
		layer_of[nid] = 0
		orig_order[nid] = i
		real_set[nid] = true

	var edge_labels: Dictionary = {}
	for ed: Dictionary in graph.edges:
		edge_labels["%s->%s" % [str(ed["from"]), str(ed["to"])]] = str(ed.get("label", ""))

	# Phase 1: 最长路径分层
	for _pass: int in range(n_real):
		var changed: bool = false
		for nd: Dictionary in graph.nodes:
			var u: String = str(nd["id"])
			var lu: int = int(layer_of[u])
			for v_var: Variant in (raw_fwd_out.get(u, []) as Array):
				var v: String = str(v_var)
				var cand: int = mini(lu + 1, maxi(1, n_real - 1))
				if cand > int(layer_of[v]):
					layer_of[v] = cand
					changed = true
		if not changed:
			break

	var max_layer: int = 0
	var layers: Dictionary = {}
	for nid_k: Variant in layer_of.keys():
		var lv: int = int(layer_of[nid_k])
		max_layer = maxi(max_layer, lv)
	for lv_i: int in range(max_layer + 1):
		layers[lv_i] = []
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		(layers[int(layer_of[nid])] as Array).append(nid)

	# Phase 2: 为跨越多层的长边插入虚拟通道哑节点
	var aug_out: Dictionary = {}
	var aug_in: Dictionary = {}
	for nid_k: Variant in real_set.keys():
		var s_id: String = str(nid_k)
		aug_out[s_id] = []
		aug_in[s_id] = []

	var dummy_chains: Dictionary = {} ## {"u->v": Array[String]}
	var dummy_seq: int = 0
	for u_k: Variant in raw_fwd_out.keys():
		var u: String = str(u_k)
		var lu: int = int(layer_of[u])
		for v_var: Variant in (raw_fwd_out[u] as Array):
			var v: String = str(v_var)
			var lv: int = int(layer_of[v])
			if lv - lu <= 1:
				(aug_out[u] as Array).append(v)
				(aug_in[v] as Array).append(u)
			else:
				var prev_id: String = u
				var d_list: Array[String] = []
				for mid_lv: int in range(lu + 1, lv):
					var dm_id: String = "__dm_%d" % dummy_seq
					dummy_seq += 1
					sizes[dm_id] = Vector2(28.0, 22.0)
					layer_of[dm_id] = mid_lv
					orig_order[dm_id] = n_real + dummy_seq
					(layers[mid_lv] as Array).append(dm_id)
					aug_out[dm_id] = []
					aug_in[dm_id] = [prev_id]
					(aug_out[prev_id] as Array).append(dm_id)
					d_list.append(dm_id)
					prev_id = dm_id
				(aug_out[prev_id] as Array).append(v)
				(aug_in[v] as Array).append(prev_id)
				dummy_chains["%s->%s" % [u, v]] = d_list

	# Phase 3: 12 轮双向重心排序 + 收敛式邻位贪心交换 + 全局最少交叉快照锁定
	var best_layers: Dictionary = _clone_layers(layers, max_layer)
	var best_crossings: int = _count_total_crossings(layers, max_layer, aug_out)

	for sweep: int in range(12):
		for lv_f: int in range(1, max_layer + 1):
			var cur_a: Array = layers[lv_f] as Array
			var prev_a: Array = layers[lv_f - 1] as Array
			cur_a.sort_custom(func(a: Variant, b: Variant) -> bool:
				return _barycenter_val(str(a), aug_in, prev_a, orig_order) < _barycenter_val(str(b), aug_in, prev_a, orig_order)
			)
			_convergent_swap_polish(cur_a, prev_a, aug_in, aug_out, (layers[lv_f + 1] as Array) if lv_f < max_layer else [])
		var c_after_fwd: int = _count_total_crossings(layers, max_layer, aug_out)
		if c_after_fwd < best_crossings:
			best_crossings = c_after_fwd
			best_layers = _clone_layers(layers, max_layer)
			if best_crossings == 0:
				break

		# 偶数轮末尾尝试翻转哑节点与实节点初始次序跳出局部极小值
		if sweep == 4 and best_crossings > 0 and max_layer >= 1:
			(layers[max_layer] as Array).reverse()

		for lv_b: int in range(max_layer - 1, -1, -1):
			var cur_b: Array = layers[lv_b] as Array
			var next_b: Array = layers[lv_b + 1] as Array
			cur_b.sort_custom(func(a: Variant, b: Variant) -> bool:
				return _barycenter_val(str(a), aug_out, next_b, orig_order) < _barycenter_val(str(b), aug_out, next_b, orig_order)
			)
			_convergent_swap_polish(cur_b, next_b, aug_out, aug_in, (layers[lv_b - 1] as Array) if lv_b > 0 else [])
		var c_after_bwd: int = _count_total_crossings(layers, max_layer, aug_out)
		if c_after_bwd < best_crossings:
			best_crossings = c_after_bwd
			best_layers = _clone_layers(layers, max_layer)
			if best_crossings == 0:
				break

	layers = best_layers

	# Phase 4: 边标签感知主轴间距 + 交叉轴父子共线对齐与防重叠投影
	var layer_primary: Dictionary = {}
	var layer_span_main: Dictionary = {}
	var cursor_main: float = 0.0
	for lv_i: int in range(max_layer + 1):
		layer_primary[lv_i] = cursor_main
		var max_w: float = MermaidMetrics.NODE_MIN_W
		var max_lbl_px: float = 0.0
		for item_var: Variant in (layers[lv_i] as Array):
			var uid: String = str(item_var)
			if real_set.has(uid):
				max_w = maxf(max_w, (sizes[uid] as Vector2).x)
				for nxt_v: Variant in (raw_fwd_out.get(uid, []) as Array):
					var elbl: String = str(edge_labels.get("%s->%s" % [uid, str(nxt_v)], ""))
					max_lbl_px = maxf(max_lbl_px, MermaidMetrics.estimate_text_px(elbl))
		var main_sz: float = MermaidMetrics.NODE_HEIGHT if is_vertical else max_w
		var main_gap: float = 88.0 if is_vertical else maxf(102.0, max_lbl_px + 54.0)
		layer_span_main[lv_i] = main_sz
		cursor_main += main_sz + main_gap

	var cross_coord: Dictionary = {}
	for lv_i: int in range(max_layer + 1):
		var arr: Array = layers[lv_i] as Array
		var cur_c: float = 0.0
		for item_var: Variant in arr:
			var uid: String = str(item_var)
			var span: float = (sizes[uid] as Vector2).x if is_vertical else (sizes[uid] as Vector2).y
			cross_coord[uid] = cur_c + span * 0.5
			cur_c += span + (40.0 if real_set.has(uid) else 26.0)
		var shift_mid: float = -cur_c * 0.5
		for item_var2: Variant in arr:
			var uid2: String = str(item_var2)
			cross_coord[uid2] = float(cross_coord[uid2]) + shift_mid

	for _align_it: int in range(4):
		for lv_f: int in range(1, max_layer + 1):
			_align_layer_to_neighbors(layers[lv_f] as Array, aug_in, cross_coord, sizes, real_set, is_vertical)
		for lv_b: int in range(max_layer - 1, -1, -1):
			_align_layer_to_neighbors(layers[lv_b] as Array, aug_out, cross_coord, sizes, real_set, is_vertical)

	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		var sz: Vector2 = sizes[nid] as Vector2
		var lv: int = int(layer_of[nid])
		var p_val: float = float(layer_primary[lv])
		var c_val: float = float(cross_coord[nid])
		var pos: Vector2 = (
			Vector2(c_val - sz.x * 0.5, p_val)
			if is_vertical
			else Vector2(p_val, c_val - sz.y * 0.5)
		)
		graph.set_node_pos(nid, pos)

	# 为每个虚拟哑节点生成双锚点正交走廊，保证跨列长边完整水平/垂直穿过预留缝隙，绝不切角擦碰宽节点
	var edge_waypoints: Dictionary = {}
	for ekey_var: Variant in dummy_chains.keys():
		var ekey: String = str(ekey_var)
		var d_arr: Array = dummy_chains[ekey] as Array
		var wps: Array[Vector2] = []
		for dm_var: Variant in d_arr:
			var dm_id: String = str(dm_var)
			var dlv: int = int(layer_of[dm_id])
			var p_start: float = float(layer_primary[dlv])
			var p_end: float = p_start + float(layer_span_main[dlv])
			var dc: float = float(cross_coord[dm_id])
			if is_vertical:
				wps.append(Vector2(dc, p_start - 14.0))
				wps.append(Vector2(dc, p_end + 14.0))
			else:
				wps.append(Vector2(p_start - 18.0, dc))
				wps.append(Vector2(p_end + 18.0, dc))
		edge_waypoints[ekey] = wps
	plan["edge_waypoints"] = edge_waypoints


static func _clone_layers(layers: Dictionary, max_layer: int) -> Dictionary:
	var copy_d: Dictionary = {}
	for i: int in range(max_layer + 1):
		copy_d[i] = (layers[i] as Array).duplicate()
	return copy_d


static func _count_total_crossings(layers: Dictionary, max_layer: int, aug_out: Dictionary) -> int:
	var total: int = 0
	for lv: int in range(max_layer):
		var cur_l: Array = layers[lv] as Array
		var nxt_l: Array = layers[lv + 1] as Array
		for i: int in range(cur_l.size()):
			for j: int in range(i + 1, cur_l.size()):
				total += _pair_crossings(str(cur_l[i]), str(cur_l[j]), aug_out, nxt_l)
	return total


static func _barycenter_val(nid: String, adj: Dictionary, ref_layer: Array, orig_order: Dictionary) -> float:
	var nbs: Array = adj.get(nid, []) as Array
	var sum_v: float = 0.0
	var cnt: int = 0
	for nb_var: Variant in nbs:
		var idx: int = ref_layer.find(str(nb_var))
		if idx >= 0:
			sum_v += float(idx)
			cnt += 1
	if cnt > 0:
		return sum_v / float(cnt)
	return float(orig_order.get(nid, 0)) * 0.01 + 50.0


static func _convergent_swap_polish(
	layer_arr: Array,
	primary_ref: Array,
	primary_adj: Dictionary,
	secondary_adj: Dictionary,
	secondary_ref: Array
) -> void:
	if layer_arr.size() < 2:
		return
	for _pass: int in range(6):
		var improved: bool = false
		for i: int in range(layer_arr.size() - 1):
			var u: String = str(layer_arr[i])
			var v: String = str(layer_arr[i + 1])
			var c_uv: int = _pair_crossings(u, v, primary_adj, primary_ref) + _pair_crossings(u, v, secondary_adj, secondary_ref)
			var c_vu: int = _pair_crossings(v, u, primary_adj, primary_ref) + _pair_crossings(v, u, secondary_adj, secondary_ref)
			if c_vu < c_uv:
				layer_arr[i] = v
				layer_arr[i + 1] = u
				improved = true
		if not improved:
			break


static func _pair_crossings(upper_id: String, lower_id: String, adj: Dictionary, ref_layer: Array) -> int:
	if ref_layer.is_empty():
		return 0
	var up_nbs: Array = adj.get(upper_id, []) as Array
	var lo_nbs: Array = adj.get(lower_id, []) as Array
	var crossings: int = 0
	for a_var: Variant in up_nbs:
		var ia: int = ref_layer.find(str(a_var))
		if ia < 0:
			continue
		for b_var: Variant in lo_nbs:
			var ib: int = ref_layer.find(str(b_var))
			if ib >= 0 and ia > ib:
				crossings += 1
	return crossings


static func _align_layer_to_neighbors(
	layer_arr: Array,
	adj: Dictionary,
	cross_coord: Dictionary,
	sizes: Dictionary,
	real_set: Dictionary,
	is_vertical: bool
) -> void:
	if layer_arr.is_empty():
		return
	for item_var: Variant in layer_arr:
		var uid: String = str(item_var)
		var nbs: Array = adj.get(uid, []) as Array
		if nbs.is_empty():
			continue
		var coords: Array[float] = []
		for nb_var: Variant in nbs:
			var nb: String = str(nb_var)
			if cross_coord.has(nb):
				coords.append(float(cross_coord[nb]))
		if not coords.is_empty():
			coords.sort()
			var mid_i: int = coords.size() / 2
			var target_c: float = (
				coords[mid_i]
				if coords.size() % 2 == 1
				else (coords[mid_i - 1] + coords[mid_i]) * 0.5
			)
			# 虚拟哑节点强制更高对齐权重以拉直跨层走廊
			var blend_w: float = 0.72 if real_set.has(uid) else 0.90
			cross_coord[uid] = lerpf(float(cross_coord[uid]), target_c, blend_w)

	var prev_edge: float = -INF
	var shift_sum: float = 0.0
	var before_sum: float = 0.0
	for item_var2: Variant in layer_arr:
		var uid2: String = str(item_var2)
		var sz: Vector2 = sizes[uid2] as Vector2
		var half_s: float = (sz.x if is_vertical else sz.y) * 0.5
		var gap: float = (38.0 if is_vertical else 28.0) if real_set.has(uid2) else 20.0
		var c_cur: float = float(cross_coord[uid2])
		before_sum += c_cur
		if is_finite(prev_edge) and c_cur - half_s < prev_edge + gap:
			c_cur = prev_edge + gap + half_s
		cross_coord[uid2] = c_cur
		shift_sum += c_cur
		prev_edge = c_cur + half_s

	var recenter: float = (before_sum - shift_sum) / float(layer_arr.size())
	for item_var3: Variant in layer_arr:
		var uid3: String = str(item_var3)
		cross_coord[uid3] = float(cross_coord[uid3]) + recenter
