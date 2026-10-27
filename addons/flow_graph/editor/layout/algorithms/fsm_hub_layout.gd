@tool
extends RefCounted

## 星型状态机自动布局器（FSM Hub-Star & Rigid-Block `[Any State]` Layout）。[br]
##
## 实现全正交（零斜角射线）四向卫星分配、预留顶部回流胶囊与底部嵌套回跳弧真实包络的多跳链展开，以及底部刚体复合块水平居中排布。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)


static func apply(graph: MermaidGraphModel, plan: Dictionary) -> void:
	var hub_id: String = str(plan.get("hub_id", ""))
	if hub_id.is_empty():
		return

	var hub_short: String = str(plan.get("hub_short_title", hub_id))
	var sizes: Dictionary = {}
	for nd: Dictionary in graph.nodes:
		sizes[str(nd["id"])] = MermaidMetrics.estimate_node_size(nd)

	var edge_labels: Dictionary = {}
	for ed: Dictionary in graph.edges:
		edge_labels["%s->%s" % [str(ed["from"]), str(ed["to"])]] = str(ed.get("label", ""))

	var satellites: Array = (plan.get("satellites_ordered", []) as Array).duplicate()
	var slot_hints: Dictionary = plan.get("satellite_slot_hints", {}) as Dictionary
	var chains: Array = (plan.get("chains_ordered", []) as Array).duplicate()
	var interrupts: Array = plan.get("interrupt_nodes", []) as Array
	var portal_returns: Dictionary = plan.get("portal_return_edges", {}) as Dictionary
	var local_backs: Dictionary = plan.get("local_back_edges", {}) as Dictionary
	var dag_depth: Dictionary = plan.get("dag_depth", {}) as Dictionary
	var branch_root_of: Dictionary = plan.get("branch_root_of", {}) as Dictionary
	var is_vertical: bool = (graph.direction == &"TD" or graph.direction == &"TB")

	var hub_sz: Vector2 = sizes[hub_id] as Vector2
	var hub_center := Vector2(460.0, 280.0)
	var hub_rect := Rect2(hub_center - hub_sz * 0.5, hub_sz)
	graph.set_node_pos(hub_id, hub_rect.position)

	# 1. 全正交 1 跳卫星分配（彻底废除产生 45 度长斜穿线的西北/西南槽，改为西侧/东侧正交纵向栈）
	_place_orthogonal_satellites(graph, satellites, slot_hints, chains.is_empty(), is_vertical, sizes, edge_labels, hub_id, hub_rect, hub_center)

	# 2. 基于真实包络高度（含顶部非叶节点回流胶囊与底部多层回跳弧）排布多跳动作链
	if not chains.is_empty():
		if not is_vertical:
			_place_horizontal_chains(graph, plan, chains, sizes, edge_labels, hub_id, hub_short, hub_rect, hub_center, portal_returns, local_backs, dag_depth, branch_root_of)
		else:
			_place_vertical_chains(graph, plan, chains, sizes, edge_labels, hub_id, hub_short, hub_rect, hub_center, portal_returns)

	# 3. 刚体复合块精确测量与水平居中排布 [Any State] 中断区
	if not interrupts.is_empty():
		_place_any_state_zone(graph, plan, interrupts, sizes, edge_labels, hub_id, hub_short, portal_returns, local_backs)


static func _place_orthogonal_satellites(
	graph: MermaidGraphModel,
	satellites: Array,
	slot_hints: Dictionary,
	no_chains: bool,
	is_vertical: bool,
	sizes: Dictionary,
	edge_labels: Dictionary,
	hub_id: String,
	hub_rect: Rect2,
	hub_center: Vector2
) -> void:
	if satellites.is_empty():
		return

	var north_ids: Array[String] = []
	var south_ids: Array[String] = []
	var west_ids: Array[String] = []
	var east_ids: Array[String] = []

	if not is_vertical:
		var remaining: Array[String] = []
		for s_var: Variant in satellites:
			var sid: String = str(s_var)
			var hint: String = str(slot_hints.get(sid, ""))
			if hint == "north" and north_ids.is_empty():
				north_ids.append(sid)
			elif hint == "south" and south_ids.is_empty():
				south_ids.append(sid)
			else:
				remaining.append(sid)

		for sid2: String in remaining:
			if no_chains and east_ids.size() <= west_ids.size() and east_ids.size() < 2:
				east_ids.append(sid2)
			elif north_ids.is_empty():
				north_ids.append(sid2)
			elif west_ids.is_empty():
				west_ids.append(sid2)
			elif south_ids.is_empty():
				south_ids.append(sid2)
			elif no_chains and east_ids.size() < west_ids.size():
				east_ids.append(sid2)
			else:
				west_ids.append(sid2)
	else:
		for i: int in range(satellites.size()):
			var sid_v: String = str(satellites[i])
			if west_ids.is_empty():
				west_ids.append(sid_v)
			elif east_ids.is_empty():
				east_ids.append(sid_v)
			elif north_ids.is_empty():
				north_ids.append(sid_v)
			elif no_chains and south_ids.is_empty():
				south_ids.append(sid_v)
			elif west_ids.size() <= east_ids.size():
				west_ids.append(sid_v)
			else:
				east_ids.append(sid_v)

	var v_gap: float = 92.0
	if not north_ids.is_empty():
		var nid_n: String = north_ids[0]
		var sz_n: Vector2 = sizes[nid_n] as Vector2
		graph.set_node_pos(nid_n, Vector2(hub_center.x - sz_n.x * 0.5, hub_rect.position.y - v_gap - sz_n.y))

	if not south_ids.is_empty():
		var nid_s: String = south_ids[0]
		var sz_s: Vector2 = sizes[nid_s] as Vector2
		graph.set_node_pos(nid_s, Vector2(hub_center.x - sz_s.x * 0.5, hub_rect.end.y + v_gap))

	if not west_ids.is_empty():
		var max_w_lbl: float = 0.0
		for wid: String in west_ids:
			var l1: String = str(edge_labels.get("%s->%s" % [hub_id, wid], ""))
			var l2: String = str(edge_labels.get("%s->%s" % [wid, hub_id], ""))
			max_w_lbl = maxf(max_w_lbl, maxf(MermaidMetrics.estimate_text_px(l1), MermaidMetrics.estimate_text_px(l2)))
		var w_gap: float = maxf(114.0, max_w_lbl + 56.0)
		var stack_step_y: float = MermaidMetrics.NODE_HEIGHT + 34.0
		for wi: int in range(west_ids.size()):
			var wid2: String = west_ids[wi]
			var sz_w: Vector2 = sizes[wid2] as Vector2
			var cy_w: float = hub_center.y + (float(wi) - float(west_ids.size() - 1) * 0.5) * stack_step_y
			graph.set_node_pos(wid2, Vector2(hub_rect.position.x - w_gap - sz_w.x, cy_w - sz_w.y * 0.5))

	if not east_ids.is_empty():
		var max_e_lbl: float = 0.0
		for eid: String in east_ids:
			var le1: String = str(edge_labels.get("%s->%s" % [hub_id, eid], ""))
			var le2: String = str(edge_labels.get("%s->%s" % [eid, hub_id], ""))
			max_e_lbl = maxf(max_e_lbl, maxf(MermaidMetrics.estimate_text_px(le1), MermaidMetrics.estimate_text_px(le2)))
		var e_gap: float = maxf(114.0, max_e_lbl + 56.0)
		var stack_step_e: float = MermaidMetrics.NODE_HEIGHT + 34.0
		for ei: int in range(east_ids.size()):
			var eid2: String = east_ids[ei]
			var sz_e: Vector2 = sizes[eid2] as Vector2
			var cy_e: float = hub_center.y + (float(ei) - float(east_ids.size() - 1) * 0.5) * stack_step_e
			graph.set_node_pos(eid2, Vector2(hub_rect.end.x + e_gap, cy_e - sz_e.y * 0.5))


static func _place_horizontal_chains(
	graph: MermaidGraphModel,
	plan: Dictionary,
	chains: Array,
	sizes: Dictionary,
	edge_labels: Dictionary,
	hub_id: String,
	hub_short: String,
	hub_rect: Rect2,
	hub_center: Vector2,
	portal_returns: Dictionary,
	local_backs: Dictionary,
	dag_depth: Dictionary,
	branch_root_of: Dictionary
) -> void:
	var fwd_out_map: Dictionary = plan.get("fwd_out", {}) as Dictionary
	var chain_specs: Array[Dictionary] = []
	var total_stack_h: float = 0.0
	var inter_chain_gap: float = 64.0

	for c_idx: int in range(chains.size()):
		var members: Array = chains[c_idx] as Array
		var depth_groups: Dictionary = {}
		var ordered_depths: Array[int] = []
		var max_sub_fan: int = 1
		var has_top_portal: bool = false
		var under_loop_cnt: int = 0
		var c_root: String = str(branch_root_of.get(str(members[0]), str(members[0])))

		for m_var: Variant in members:
			var mid: String = str(m_var)
			var d: int = int(dag_depth.get(mid, 1))
			if not depth_groups.has(d):
				depth_groups[d] = []
				ordered_depths.append(d)
			(depth_groups[d] as Array).append(mid)
			max_sub_fan = maxi(max_sub_fan, (depth_groups[d] as Array).size())
			if portal_returns.has("%s->%s" % [mid, hub_id]) and not (fwd_out_map.get(mid, []) as Array).is_empty():
				has_top_portal = true

		for lb_key_var: Variant in local_backs.keys():
			var parts: PackedStringArray = str(lb_key_var).split("->")
			if parts.size() == 2 and str(branch_root_of.get(parts[0], "")) == c_root:
				under_loop_cnt += 1

		ordered_depths.sort()
		var sub_step_y: float = MermaidMetrics.NODE_HEIGHT + (54.0 if (has_top_portal and max_sub_fan > 1) else 24.0)
		var body_h: float = float(max_sub_fan - 1) * sub_step_y + MermaidMetrics.NODE_HEIGHT
		var top_pad: float = 42.0 if has_top_portal else 0.0
		var under_pad: float = (26.0 + float(under_loop_cnt) * 20.0) if under_loop_cnt > 0 else 0.0
		var spec_h: float = top_pad + body_h + under_pad
		chain_specs.append({
			"depths": ordered_depths,
			"groups": depth_groups,
			"sub_step_y": sub_step_y,
			"top_pad": top_pad,
			"body_h": body_h,
			"under_pad": under_pad,
			"total_h": spec_h,
		})
		total_stack_h += spec_h
	total_stack_h += float(chain_specs.size() - 1) * inter_chain_gap

	var max_hub_lbl_px: float = 0.0
	for sp: Dictionary in chain_specs:
		var d0: int = (sp["depths"] as Array[int])[0]
		for first_m: Variant in ((sp["groups"] as Dictionary)[d0] as Array):
			var l_str: String = str(edge_labels.get("%s->%s" % [hub_id, str(first_m)], ""))
			max_hub_lbl_px = maxf(max_hub_lbl_px, MermaidMetrics.estimate_text_px(l_str))
	var base_col_x: float = hub_rect.end.x + maxf(124.0, max_hub_lbl_px + 72.0)

	var cur_top_y: float = hub_center.y - total_stack_h * 0.5
	for sp: Dictionary in chain_specs:
		var top_pad_v: float = float(sp["top_pad"])
		var body_h: float = float(sp["body_h"])
		var sub_step_v: float = float(sp["sub_step_y"])
		var row_center_y: float = cur_top_y + top_pad_v + body_h * 0.5
		var depths_arr: Array[int] = sp["depths"] as Array[int]
		var groups_map: Dictionary = sp["groups"] as Dictionary
		var cursor_x: float = base_col_x

		for di: int in range(depths_arr.size()):
			var d_val: int = depths_arr[di]
			var grp: Array = groups_map[d_val] as Array
			var col_max_w: float = 0.0
			var next_lbl_px: float = 0.0
			var mid_portal_px: float = 0.0

			for sub_i: int in range(grp.size()):
				var mid: String = str(grp[sub_i])
				var m_sz: Vector2 = sizes[mid] as Vector2
				var sub_y: float = row_center_y + (float(sub_i) - float(grp.size() - 1) * 0.5) * sub_step_v - m_sz.y * 0.5
				graph.set_node_pos(mid, Vector2(cursor_x, sub_y))
				var eff_w: float = m_sz.x
				# 若当前非叶节点顶部挂载回流胶囊，保证水平列宽足以容纳胶囊宽度防相邻挤压
				if portal_returns.has("%s->%s" % [mid, hub_id]) and not (fwd_out_map.get(mid, []) as Array).is_empty():
					var top_plbl: String = str(edge_labels.get("%s->%s" % [mid, hub_id], ""))
					var top_pw: float = MermaidMetrics.estimate_portal_pill_width(hub_short, top_plbl)
					eff_w = maxf(eff_w, m_sz.x * 0.66 + top_pw * 0.5 + 14.0)
				col_max_w = maxf(col_max_w, eff_w)

				if di + 1 < depths_arr.size():
					for nxt_m: Variant in (groups_map[depths_arr[di + 1]] as Array):
						var elbl: String = str(edge_labels.get("%s->%s" % [mid, str(nxt_m)], ""))
						next_lbl_px = maxf(next_lbl_px, MermaidMetrics.estimate_text_px(elbl))
					if portal_returns.has("%s->%s" % [mid, hub_id]) and (fwd_out_map.get(mid, []) as Array).is_empty():
						var plbl: String = str(edge_labels.get("%s->%s" % [mid, hub_id], ""))
						mid_portal_px = maxf(mid_portal_px, 32.0 + MermaidMetrics.estimate_portal_pill_width(hub_short, plbl) + 28.0)

			var step_gap: float = maxf(84.0, maxf(next_lbl_px + 48.0, mid_portal_px))
			cursor_x += col_max_w + step_gap

		cur_top_y += float(sp["total_h"]) + inter_chain_gap


static func _place_vertical_chains(
	graph: MermaidGraphModel,
	plan: Dictionary,
	chains: Array,
	sizes: Dictionary,
	edge_labels: Dictionary,
	hub_id: String,
	hub_short: String,
	hub_rect: Rect2,
	hub_center: Vector2,
	portal_returns: Dictionary
) -> void:
	var fwd_out_map: Dictionary = plan.get("fwd_out", {}) as Dictionary
	var col_widths: Array[float] = []
	var total_w: float = 0.0
	var col_gap: float = 96.0

	for c_idx: int in range(chains.size()):
		var members: Array = chains[c_idx] as Array
		var max_cw: float = MermaidMetrics.NODE_MIN_W
		for m_var: Variant in members:
			var mid: String = str(m_var)
			var m_sz: Vector2 = sizes[mid] as Vector2
			var eff_cw: float = m_sz.x
			if portal_returns.has("%s->%s" % [mid, hub_id]):
				var plbl: String = str(edge_labels.get("%s->%s" % [mid, hub_id], ""))
				eff_cw += 34.0 + MermaidMetrics.estimate_portal_pill_width(hub_short, plbl)
			max_cw = maxf(max_cw, eff_cw)
		col_widths.append(max_cw)
		total_w += max_cw
	total_w += float(maxi(0, chains.size() - 1)) * col_gap

	var cursor_x: float = hub_center.x - total_w * 0.5
	var base_y: float = hub_rect.end.y + 114.0
	for c_idx2: int in range(chains.size()):
		var members2: Array = chains[c_idx2] as Array
		var cw: float = col_widths[c_idx2]
		var cy: float = base_y
		for m_var2: Variant in members2:
			var mid2: String = str(m_var2)
			var m_sz2: Vector2 = sizes[mid2] as Vector2
			if portal_returns.has("%s->%s" % [mid2, hub_id]) and not (fwd_out_map.get(mid2, []) as Array).is_empty():
				cy += 42.0
			graph.set_node_pos(mid2, Vector2(cursor_x, cy))
			cy += m_sz2.y + 68.0
		cursor_x += cw + col_gap


static func _place_any_state_zone(
	graph: MermaidGraphModel,
	plan: Dictionary,
	interrupts: Array,
	sizes: Dictionary,
	edge_labels: Dictionary,
	hub_id: String,
	hub_short: String,
	portal_returns: Dictionary,
	local_backs: Dictionary
) -> void:
	var main_min_x: float = INF
	var main_max_x: float = -INF
	var main_max_y: float = -INF
	var int_lookup: Dictionary = plan.get("interrupt_set", {}) as Dictionary

	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		if int_lookup.has(nid):
			continue
		var p: Vector2 = nd.get("pos", Vector2.ZERO) as Vector2
		var sz: Vector2 = sizes[nid] as Vector2
		var r_end_x: float = p.x + sz.x
		if portal_returns.has("%s->%s" % [nid, hub_id]):
			var plbl_m: String = str(edge_labels.get("%s->%s" % [nid, hub_id], ""))
			r_end_x += 32.0 + MermaidMetrics.estimate_portal_pill_width(hub_short, plbl_m)
		main_min_x = minf(main_min_x, p.x)
		main_max_x = maxf(main_max_x, r_end_x)
		main_max_y = maxf(main_max_y, p.y + sz.y)

	if not is_finite(main_min_x):
		main_min_x = 100.0
		main_max_x = 900.0
		main_max_y = 300.0

	var main_center_x: float = (main_min_x + main_max_x) * 0.5
	var under_extra: float = (34.0 + float(local_backs.size()) * 20.0) if not local_backs.is_empty() else 0.0
	var base_zone_y: float = main_max_y + 92.0 + under_extra

	var max_per_row: int = 4
	var block_gap: float = 36.0
	var origin_lead_w: float = 138.0
	var row_count: int = ceili(float(interrupts.size()) / float(max_per_row))

	for r_idx: int in range(row_count):
		var i_start: int = r_idx * max_per_row
		var i_end: int = mini(interrupts.size(), i_start + max_per_row)
		var blocks: Array[Dictionary] = []
		var row_total_w: float = origin_lead_w

		for idx: int in range(i_start, i_end):
			var inid: String = str(interrupts[idx])
			var isz: Vector2 = sizes[inid] as Vector2
			var bw: float = isz.x
			if portal_returns.has("%s->%s" % [inid, hub_id]):
				var plbl_i: String = str(edge_labels.get("%s->%s" % [inid, hub_id], ""))
				bw += 32.0 + MermaidMetrics.estimate_portal_pill_width(hub_short, plbl_i)
			blocks.append({"id": inid, "node_w": isz.x, "block_w": bw})
			row_total_w += bw
		row_total_w += float(blocks.size() - 1) * block_gap

		var row_x: float = main_center_x - row_total_w * 0.5 + origin_lead_w
		var row_y: float = base_zone_y + float(r_idx) * 82.0
		for blk: Dictionary in blocks:
			graph.set_node_pos(str(blk["id"]), Vector2(row_x, row_y))
			row_x += float(blk["block_w"]) + block_gap
