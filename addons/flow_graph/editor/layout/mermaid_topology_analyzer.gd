@tool
extends RefCounted

## Mermaid 拓扑语义识别与多态分类器（Topology Archetype Analyzer）。[br]
##
## 自动鉴别星型有环状态机（`fsm_hub`）、严格层级决策树（`bt_tree`）与通用有向管线（`dag_pipeline`），并完成枢纽提取、`[Any State]` 全局中断/终态汇点识别、同链局部回边与跨分支边分离，以及减少交叉的子链/卫星预排序。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)


#region 公开拓扑分类入口

static func analyze_topology(graph: MermaidGraphModel) -> Dictionary:
	var base_plan: Dictionary = {
		"archetype": MermaidMetrics.ARCHETYPE_DAG_PIPELINE,
		"hub_id": "",
		"hub_short_title": "",
		"interrupt_nodes": [],
		"interrupt_set": {},
		"satellite_1hop_set": {},
		"satellite_slot_hints": {},
		"portal_return_edges": {},
		"interrupt_redirect_edges": {},
		"local_back_edges": {},
		"cross_branch_edges": {},
		"transient_only_edges": {},
		"branch_root_of": {},
		"dag_depth": {},
		"fwd_out": {},
		"fwd_in": {},
		"back_edges": {},
		"bt_composites": {},
		"edge_waypoints": {},
		"roots": [],
	}
	if graph == null or graph.nodes.is_empty():
		return base_plan

	if graph.diagram_type == MermaidGraphModel.TYPE_STATE_V2:
		var fsm_plan: Dictionary = _analyze_fsm_topology(graph)
		var sats: Array = fsm_plan.get("satellites_ordered", []) as Array
		var chs: Array = fsm_plan.get("chains_ordered", []) as Array
		var ints: Array = fsm_plan.get("interrupt_nodes", []) as Array
		if graph.nodes.size() >= 3 and (sats.size() + chs.size()) <= 1 and ints.is_empty() and sats.is_empty():
			return _analyze_flowchart_topology(graph)
		return fsm_plan

	return _analyze_flowchart_topology(graph)


static func analyze_dag_and_back_edges(graph: MermaidGraphModel, roots: Array[String] = []) -> Dictionary:
	var use_roots: Array[String] = roots if not roots.is_empty() else _collect_roots(graph)
	var raw_adj: Dictionary = {}
	var fwd_out: Dictionary = {}
	var fwd_in: Dictionary = {}
	var back_edges: Dictionary = {}

	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		raw_adj[nid] = []
		fwd_out[nid] = []
		fwd_in[nid] = []

	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		if f != "*" and raw_adj.has(f) and raw_adj.has(t):
			(raw_adj[f] as Array).append(t)

	var root_set: Dictionary = {}
	for r: String in use_roots:
		root_set[r] = true

	var visited: Dictionary = {}
	var on_stack: Dictionary = {}
	for r_id: String in use_roots:
		if not visited.has(r_id):
			_dfs_classify_edges(r_id, raw_adj, root_set, visited, on_stack, fwd_out, fwd_in, back_edges)
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		if not visited.has(nid):
			_dfs_classify_edges(nid, raw_adj, root_set, visited, on_stack, fwd_out, fwd_in, back_edges)

	return {
		"fwd_out": fwd_out,
		"fwd_in": fwd_in,
		"back_edges": back_edges,
	}

#endregion


#region Flowchart / BT / DAG 分类实现

static func _analyze_flowchart_topology(graph: MermaidGraphModel) -> Dictionary:
	var roots: Array[String] = _collect_roots(graph)
	var dag_info: Dictionary = analyze_dag_and_back_edges(graph, roots)
	var back_map: Dictionary = dag_info["back_edges"] as Dictionary
	var fwd_out: Dictionary = dag_info["fwd_out"] as Dictionary
	var fwd_in: Dictionary = dag_info["fwd_in"] as Dictionary

	var is_strict_tree: bool = back_map.is_empty()
	if is_strict_tree:
		for k: Variant in fwd_in.keys():
			if (fwd_in[k] as Array).size() > 1:
				is_strict_tree = false
				break

	var bt_composites: Dictionary = {}
	if is_strict_tree:
		for p_var: Variant in fwd_out.keys():
			var pid: String = str(p_var)
			var ch: Array = fwd_out[pid] as Array
			if not ch.is_empty():
				bt_composites[pid] = ch.duplicate()

	return {
		"archetype": MermaidMetrics.ARCHETYPE_BT_TREE if is_strict_tree else MermaidMetrics.ARCHETYPE_DAG_PIPELINE,
		"hub_id": roots[0] if not roots.is_empty() else "",
		"hub_short_title": "",
		"interrupt_nodes": [],
		"interrupt_set": {},
		"satellite_1hop_set": {},
		"satellite_slot_hints": {},
		"portal_return_edges": {},
		"interrupt_redirect_edges": {},
		"local_back_edges": back_map.duplicate(),
		"cross_branch_edges": {},
		"transient_only_edges": {},
		"branch_root_of": {},
		"dag_depth": {},
		"fwd_out": fwd_out,
		"fwd_in": fwd_in,
		"back_edges": back_map,
		"bt_composites": bt_composites,
		"edge_waypoints": {},
		"roots": roots,
	}


static func _collect_roots(graph: MermaidGraphModel) -> Array[String]:
	var indegree: Dictionary = {}
	for nd: Dictionary in graph.nodes:
		indegree[str(nd["id"])] = 0
	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		if f != "*" and f != t and indegree.has(t):
			indegree[t] = int(indegree[t]) + 1

	var roots: Array[String] = []
	if not graph.initial_node_id.is_empty() and indegree.has(graph.initial_node_id):
		roots.append(graph.initial_node_id)
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		if int(indegree.get(nid, 0)) == 0 and not roots.has(nid):
			roots.append(nid)
	if roots.is_empty() and not graph.nodes.is_empty():
		roots.append(str(graph.nodes[0]["id"]))
	return roots


static func _dfs_classify_edges(
	u: String,
	raw_adj: Dictionary,
	root_set: Dictionary,
	visited: Dictionary,
	on_stack: Dictionary,
	fwd_out: Dictionary,
	fwd_in: Dictionary,
	back_edges: Dictionary
) -> void:
	visited[u] = true
	on_stack[u] = true
	for v_var: Variant in (raw_adj.get(u, []) as Array):
		var v: String = str(v_var)
		var key: String = "%s->%s" % [u, v]
		if u == v or on_stack.has(v) or (root_set.has(v) and visited.has(v)):
			back_edges[key] = true
		else:
			if not (fwd_out[u] as Array).has(v):
				(fwd_out[u] as Array).append(v)
				(fwd_in[v] as Array).append(u)
			if not visited.has(v):
				_dfs_classify_edges(v, raw_adj, root_set, visited, on_stack, fwd_out, fwd_in, back_edges)
	on_stack.erase(u)

#endregion


#region FSM 星型枢纽、全局汇点与消交叉排序实现

static func _analyze_fsm_topology(graph: MermaidGraphModel) -> Dictionary:
	var node_map: Dictionary = {}
	var node_order: Array[String] = []
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		node_map[nid] = nd
		node_order.append(nid)

	var hub_id: String = graph.initial_node_id
	if hub_id.is_empty() or not node_map.has(hub_id):
		var best_deg: int = -1
		for nid: String in node_order:
			var deg: int = 0
			for ed: Dictionary in graph.edges:
				if str(ed["from"]) == nid or str(ed["to"]) == nid:
					deg += 1
			if deg > best_deg:
				best_deg = deg
				hub_id = nid

	var hub_nd: Dictionary = node_map.get(hub_id, {}) as Dictionary
	var hub_short: String = MermaidMetrics.extract_short_name(str(hub_nd.get("title", hub_id)), hub_id)

	var struct_edges: Array[Dictionary] = []
	var wildcard_targets: Dictionary = {}
	var all_in_sources: Dictionary = {}
	var all_out_targets: Dictionary = {}
	for nid: String in node_order:
		all_in_sources[nid] = {}
		all_out_targets[nid] = {}

	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		if not node_map.has(t):
			continue
		if f == "*":
			wildcard_targets[t] = true
			continue
		if not node_map.has(f):
			continue
		if f != t:
			(all_in_sources[t] as Dictionary)[f] = true
			(all_out_targets[f] as Dictionary)[t] = true
		if not bool(ed.get("discovered", false)):
			struct_edges.append(ed)

	if struct_edges.is_empty():
		for ed: Dictionary in graph.edges:
			var f: String = str(ed["from"])
			var t: String = str(ed["to"])
			if f != "*" and node_map.has(f) and node_map.has(t):
				struct_edges.append(ed)

	var struct_adj: Dictionary = {}
	var edge_label_lookup: Dictionary = {}
	var has_labeled_non_hub_pred: Dictionary = {}
	for nid: String in node_order:
		struct_adj[nid] = []
	for ed: Dictionary in struct_edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		var elbl: String = str(ed.get("label", "")).strip_edges()
		edge_label_lookup["%s->%s" % [f, t]] = elbl
		if f != hub_id and f != t and not elbl.is_empty():
			has_labeled_non_hub_pred[t] = true
		if f != t and not (struct_adj[f] as Array).has(t):
			(struct_adj[f] as Array).append(t)

	# 优先遍历显式带条件标签的主干跃迁边
	for nid_s: String in node_order:
		(struct_adj[nid_s] as Array).sort_custom(func(a: Variant, b: Variant) -> bool:
			var la: bool = not str(edge_label_lookup.get("%s->%s" % [nid_s, str(a)], "")).is_empty()
			var lb: bool = not str(edge_label_lookup.get("%s->%s" % [nid_s, str(b)], "")).is_empty()
			if la != lb:
				return la
			return node_order.find(str(a)) < node_order.find(str(b))
		)

	var reachable: Dictionary = {hub_id: true}
	var bfs_q: Array[String] = [hub_id]
	var q_head: int = 0
	while q_head < bfs_q.size():
		var cur: String = bfs_q[q_head]
		q_head += 1
		for nxt_var: Variant in (struct_adj[cur] as Array):
			var nxt: String = str(nxt_var)
			if not reachable.has(nxt):
				reachable[nxt] = true
				bfs_q.append(nxt)

	# 识别全局被动打断态与多源终态汇点（如 Dead / HitStun / Staggered），避免跨全图死亡射线交叉
	var interrupt_nodes: Array[String] = []
	var interrupt_set: Dictionary = {}
	for nid: String in node_order:
		if nid == hub_id:
			continue
		var in_cnt: int = (all_in_sources[nid] as Dictionary).size()
		var total_out_cnt: int = (all_out_targets[nid] as Dictionary).size()
		var non_hub_out: int = 0
		for nxt_var: Variant in (struct_adj[nid] as Array):
			if str(nxt_var) != hub_id:
				non_hub_out += 1
		var is_convergent_sink: bool = (graph.nodes.size() >= 5 and in_cnt >= 2 and total_out_cnt == 0)
		var is_convergent_interrupt: bool = (in_cnt >= 3 and non_hub_out == 0)
		var is_interrupt: bool = (
			wildcard_targets.has(nid)
			or (not reachable.has(nid))
			or is_convergent_sink
			or is_convergent_interrupt
		)
		if is_interrupt:
			interrupt_nodes.append(nid)
			interrupt_set[nid] = true

	# 采用标签优先最短跳数 BFS 构建从 Hub 辐射的骨架深度，防止跨链边将 1 跳主状态劫持进深层子链
	var dag_depth: Dictionary = {hub_id: 0}
	var main_bfs: Array[String] = [hub_id]
	var m_head: int = 0
	while m_head < main_bfs.size():
		var u_b: String = main_bfs[m_head]
		m_head += 1
		var du_b: int = int(dag_depth[u_b])
		for v_var_b: Variant in (struct_adj[u_b] as Array):
			var v_b: String = str(v_var_b)
			if v_b == hub_id or interrupt_set.has(v_b):
				continue
			# 若 Hub 到 v_b 是无标签捷径，而 v_b 拥有带标签的子链前驱（如 Parry --hold--> Block），让位给显式主链
			if u_b == hub_id and str(edge_label_lookup.get("%s->%s" % [u_b, v_b], "")).is_empty() and has_labeled_non_hub_pred.has(v_b):
				continue
			if not dag_depth.has(v_b):
				dag_depth[v_b] = du_b + 1
				main_bfs.append(v_b)

	# 兜底处理仅通过无标签捷径可达的节点
	for nid_f: String in node_order:
		if nid_f != hub_id and not interrupt_set.has(nid_f) and not dag_depth.has(nid_f):
			dag_depth[nid_f] = 1
			main_bfs.append(nid_f)
	while m_head < main_bfs.size():
		var u_b2: String = main_bfs[m_head]
		m_head += 1
		var du_b2: int = int(dag_depth[u_b2])
		for v_var_b2: Variant in (struct_adj[u_b2] as Array):
			var v_b2: String = str(v_var_b2)
			if v_b2 != hub_id and not interrupt_set.has(v_b2) and not dag_depth.has(v_b2):
				dag_depth[v_b2] = du_b2 + 1
				main_bfs.append(v_b2)

	var fwd_out: Dictionary = {}
	var fwd_in: Dictionary = {}
	var back_edges: Dictionary = {}
	for nid: String in node_order:
		fwd_out[nid] = []
		fwd_in[nid] = []

	for u_e: String in node_order:
		if interrupt_set.has(u_e) or not dag_depth.has(u_e):
			continue
		var du_e: int = int(dag_depth[u_e])
		for v_var_e: Variant in (struct_adj[u_e] as Array):
			var v_e: String = str(v_var_e)
			if interrupt_set.has(v_e) or not dag_depth.has(v_e):
				continue
			var dv_e: int = int(dag_depth[v_e])
			var ekey_m: String = "%s->%s" % [u_e, v_e]
			if v_e != hub_id and dv_e == du_e + 1:
				(fwd_out[u_e] as Array).append(v_e)
				(fwd_in[v_e] as Array).append(u_e)
			elif v_e == hub_id or dv_e <= du_e:
				back_edges[ekey_m] = true

	var main_count: int = maxi(1, node_order.size() - interrupt_nodes.size())

	var branch_root_of: Dictionary = {}
	var branch_buckets: Dictionary = {}
	var branch_roots_ordered: Array[String] = []
	for nid: String in node_order:
		if nid == hub_id or interrupt_set.has(nid):
			continue
		# 若节点同时是枢纽直连 1 跳子节点且也是其他分支子目标，仅在其无独立后续链时归入较深链，否则保持 1 跳根身份
		var cur: String = nid
		var guard: int = 0
		while int(dag_depth.get(cur, 1)) > 1 and guard < main_count:
			guard += 1
			var preds: Array = fwd_in.get(cur, []) as Array
			var best_p: String = ""
			var best_score: int = -1
			for p_var: Variant in preds:
				var p: String = str(p_var)
				var dp: int = int(dag_depth.get(p, 0))
				if p != hub_id and dp < int(dag_depth.get(cur, 1)):
					var has_lbl: bool = not str(edge_label_lookup.get("%s->%s" % [p, cur], "")).is_empty()
					var sc: int = dp * 10 + (5 if has_lbl else 0)
					if sc > best_score:
						best_score = sc
						best_p = p
			if best_p.is_empty():
				break
			cur = best_p
		branch_root_of[nid] = cur
		if not branch_buckets.has(cur):
			branch_buckets[cur] = []
			branch_roots_ordered.append(cur)
		(branch_buckets[cur] as Array).append(nid)

	var satellite_1hop_set: Dictionary = {}
	var satellites_ordered: Array[String] = []
	var chains_ordered: Array[Array] = []
	for r_id: String in branch_roots_ordered:
		var members: Array = branch_buckets[r_id] as Array
		members.sort_custom(func(a: Variant, b: Variant) -> bool:
			var da: int = int(dag_depth.get(str(a), 1))
			var db: int = int(dag_depth.get(str(b), 1))
			if da != db:
				return da < db
			return node_order.find(str(a)) < node_order.find(str(b))
		)
		if members.size() == 1:
			satellite_1hop_set[r_id] = true
			satellites_ordered.append(r_id)
		else:
			chains_ordered.append(members)

	var portal_return_edges: Dictionary = {}
	var interrupt_redirect_edges: Dictionary = {}
	var local_back_edges: Dictionary = {}
	var cross_branch_edges: Dictionary = {}
	var transient_only_edges: Dictionary = {}

	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		if f == "*" or f == t:
			continue
		var key: String = "%s->%s" % [f, t]
		var is_disc: bool = bool(ed.get("discovered", false)) and not struct_edges.has(ed)

		if interrupt_set.has(t):
			interrupt_redirect_edges[key] = true
			continue

		if t == hub_id:
			if satellite_1hop_set.has(f) and not interrupt_set.has(f):
				continue
			var has_fwd_chain_child: bool = not (fwd_out.get(f, []) as Array).is_empty()
			if is_disc and has_fwd_chain_child and not interrupt_set.has(f):
				transient_only_edges[key] = true
				continue
			portal_return_edges[key] = true
			continue

		if interrupt_set.has(f):
			transient_only_edges[key] = true
			continue

		var br_f: String = str(branch_root_of.get(f, ""))
		var br_t: String = str(branch_root_of.get(t, ""))
		if is_disc and f != hub_id and br_f != br_t:
			transient_only_edges[key] = true
			continue

		if f != hub_id and br_f != br_t:
			cross_branch_edges[key] = true
			continue

		# 仅同分支内部反向跃迁归入链下回跳弧，彻底杜绝跨行纵向穿模
		if f != hub_id and br_f == br_t and int(dag_depth.get(f, 0)) >= int(dag_depth.get(t, 0)):
			local_back_edges[key] = true

	# 基于跨分支耦合度对多跳链与 1 跳卫星做消交叉预排序
	var ordered_chains: Array[Array] = _order_chains_for_min_crossings(chains_ordered, cross_branch_edges, branch_root_of)
	var sat_slot_hints: Dictionary = _compute_satellite_slot_hints(satellites_ordered, ordered_chains, cross_branch_edges, branch_root_of)

	return {
		"archetype": MermaidMetrics.ARCHETYPE_FSM_HUB,
		"hub_id": hub_id,
		"hub_short_title": hub_short,
		"interrupt_nodes": interrupt_nodes,
		"interrupt_set": interrupt_set,
		"satellite_1hop_set": satellite_1hop_set,
		"satellites_ordered": satellites_ordered,
		"satellite_slot_hints": sat_slot_hints,
		"chains_ordered": ordered_chains,
		"portal_return_edges": portal_return_edges,
		"interrupt_redirect_edges": interrupt_redirect_edges,
		"local_back_edges": local_back_edges,
		"cross_branch_edges": cross_branch_edges,
		"transient_only_edges": transient_only_edges,
		"branch_root_of": branch_root_of,
		"dag_depth": dag_depth,
		"fwd_out": fwd_out,
		"fwd_in": fwd_in,
		"back_edges": back_edges,
		"bt_composites": {},
		"edge_waypoints": {},
		"roots": [hub_id],
	}


static func _order_chains_for_min_crossings(
	chains: Array[Array],
	cross_branch_edges: Dictionary,
	branch_root_of: Dictionary
) -> Array[Array]:
	if chains.size() <= 2:
		return chains
	var root_idx_map: Dictionary = {}
	for i: int in range(chains.size()):
		var r: String = str((chains[i] as Array)[0])
		root_idx_map[r] = i

	var weights: Dictionary = {}
	for k_var: Variant in cross_branch_edges.keys():
		var parts: PackedStringArray = str(k_var).split("->")
		if parts.size() != 2:
			continue
		var ra: String = str(branch_root_of.get(parts[0], ""))
		var rb: String = str(branch_root_of.get(parts[1], ""))
		if root_idx_map.has(ra) and root_idx_map.has(rb) and ra != rb:
			var pair_k: String = "%s|%s" % [ra, rb] if ra < rb else "%s|%s" % [rb, ra]
			weights[pair_k] = int(weights.get(pair_k, 0)) + 1

	if weights.is_empty():
		return chains

	# 贪心线性排列使存在跨链耦合的动作链相邻排列，缩短跨行连线跨度
	var used: Dictionary = {0: true}
	var result: Array[Array] = [chains[0]]
	while result.size() < chains.size():
		var last_r: String = str((result[result.size() - 1] as Array)[0])
		var best_next: int = -1
		var best_w: int = -1
		for cand_i: int in range(chains.size()):
			if used.has(cand_i):
				continue
			var cand_r: String = str((chains[cand_i] as Array)[0])
			var pk: String = "%s|%s" % [last_r, cand_r] if last_r < cand_r else "%s|%s" % [cand_r, last_r]
			var w: int = int(weights.get(pk, 0))
			if w > best_w:
				best_w = w
				best_next = cand_i
		if best_next < 0:
			for cand_i2: int in range(chains.size()):
				if not used.has(cand_i2):
					best_next = cand_i2
					break
		used[best_next] = true
		result.append(chains[best_next])
	return result


static func _compute_satellite_slot_hints(
	satellites: Array[String],
	chains: Array[Array],
	cross_branch_edges: Dictionary,
	branch_root_of: Dictionary
) -> Dictionary:
	## 返回 `{sat_id: "north" | "south" | "west"}`，让与上方链耦合的卫星优先居北、与下方链耦合的卫星优先居南。
	var hints: Dictionary = {}
	if satellites.is_empty() or chains.is_empty():
		return hints
	var chain_root_rank: Dictionary = {}
	for i: int in range(chains.size()):
		chain_root_rank[str((chains[i] as Array)[0])] = i
	var mid_rank: float = float(chains.size() - 1) * 0.5

	for sid: String in satellites:
		var rank_sum: float = 0.0
		var cnt: int = 0
		for k_var: Variant in cross_branch_edges.keys():
			var parts: PackedStringArray = str(k_var).split("->")
			if parts.size() != 2:
				continue
			var other_root: String = ""
			if parts[0] == sid:
				other_root = str(branch_root_of.get(parts[1], ""))
			elif parts[1] == sid:
				other_root = str(branch_root_of.get(parts[0], ""))
			if chain_root_rank.has(other_root):
				rank_sum += float(chain_root_rank[other_root])
				cnt += 1
		if cnt > 0:
			var avg_r: float = rank_sum / float(cnt)
			hints[sid] = "north" if avg_r <= mid_rank else "south"
	return hints

#endregion
