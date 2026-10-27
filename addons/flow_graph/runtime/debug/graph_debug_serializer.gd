@tool
class_name GraphDebugSerializer
extends RefCounted

## 调试拓扑与帧快照无状态归一化器（Stateless Graph Debug Topology & Frame Serializer）。[br]
##
## [b]核心职责：[/b][br]
## 1. 将 [StateMachine] 与 [BTTree] 的静态 AST 归一化为标准图 IR（合并运行期动态发现的未声明状态边）；[br]
## 2. 单次零冗余拷贝采集 FSM / BT 的实时激活节点、流向边与黑板变量快照；[br]
## 3. 递归检索嵌套子图引用路径，支撑公共子图 `.tres` 保存时的父图联动热重载。


#region FSM & BT Topology Export

## 导出有限状态机拓扑字典，并追加运行期通过代码直接 `change_state` 动态发现的未声明边。
static func export_fsm_topology(fsm: StateMachine, discovered_edges: Dictionary) -> Dictionary:
	if fsm == null:
		return {}
	var ast: FsmGraphDef = fsm.get_ast()
	if ast == null:
		return {}
	var ir: Dictionary = ast.to_flow_graph_ir()
	if discovered_edges.is_empty():
		return ir

	var edges_out: Array[Dictionary] = []
	var existing_pairs: Dictionary = {}
	var raw_edges: Variant = ir.get("edges", [])
	if raw_edges is Array:
		for item: Variant in raw_edges as Array:
			if item is Dictionary:
				var ed: Dictionary = item as Dictionary
				edges_out.append(ed)
				existing_pairs["%s->%s" % [str(ed.get("from", "")), str(ed.get("to", ""))]] = true

	var order_i: int = edges_out.size()
	for pair_key: Variant in discovered_edges.keys():
		var pk: String = str(pair_key)
		if existing_pairs.has(pk):
			continue
		var parts: PackedStringArray = pk.split("->")
		if parts.size() == 2:
			edges_out.append({
				"from": parts[0],
				"to": parts[1],
				"label": str(discovered_edges[pk]),
				"priority": 0,
				"order": order_i,
				"discovered": true,
				"params": {},
			})
			order_i += 1
	ir["edges"] = edges_out
	return ir


## 递归检查指定图 AST（[FsmGraphDef] 或 [BTGraphDef]）内部是否直接或间接嵌套引用了目标 `sub_graph_path` 资源（最大深度 8 + 防环）。
static func ast_references_sub_graph(ast_res: Resource, target_path: String) -> bool:
	if ast_res == null or target_path.is_empty():
		return false
	var visited: Dictionary = {}
	if not ast_res.resource_path.is_empty():
		visited[ast_res.resource_path] = true
	return _ast_refs_sub_recursive(ast_res, target_path, 0, visited)


static func _ast_refs_sub_recursive(
	ast_res: Resource,
	target_path: String,
	depth: int,
	visited: Dictionary
) -> bool:
	if ast_res == null or depth >= 8:
		return false
	if ast_res is FsmGraphDef:
		for s_def: FsmStateDef in (ast_res as FsmGraphDef).states:
			if s_def == null:
				continue
			var sp: String = s_def.sub_graph_path.strip_edges()
			if sp.is_empty():
				continue
			if sp == target_path:
				return true
			if not visited.has(sp) and ResourceLoader.exists(sp):
				visited[sp] = true
				var child_res: Resource = ResourceLoader.load(sp, "", ResourceLoader.CACHE_MODE_REUSE)
				if _ast_refs_sub_recursive(child_res, target_path, depth + 1, visited):
					return true
		return false
	if ast_res is BTGraphDef:
		var bt_def: BTGraphDef = ast_res as BTGraphDef
		return _bt_node_references_sub_graph(bt_def.root, target_path, depth, visited)
	return false


static func _bt_node_references_sub_graph(
	node_def: BTNodeDef,
	target_path: String,
	depth: int,
	visited: Dictionary
) -> bool:
	if node_def == null:
		return false
	if node_def.node_type == &"SubTree":
		var sp: String = str(node_def.params.get("sub_graph_path", "")).strip_edges()
		if sp == target_path:
			return true
		if not sp.is_empty() and depth + 1 < 8 and not visited.has(sp) and ResourceLoader.exists(sp):
			visited[sp] = true
			var child_res: Resource = ResourceLoader.load(sp, "", ResourceLoader.CACHE_MODE_REUSE)
			if _ast_refs_sub_recursive(child_res, target_path, depth + 1, visited):
				return true
	for ch_var: Variant in node_def.children:
		if _bt_node_references_sub_graph(ch_var as BTNodeDef, target_path, depth, visited):
			return true
	return false

#endregion


#region FSM & BT Frame Telemetry Capture

## 单次采样 [StateMachine] 当前帧快照（零历史数组冗余克隆、黑板仅单次浅拷贝）。
static func capture_fsm_frame(fsm: StateMachine) -> Dictionary:
	if fsm == null:
		return {"active_nodes": {}, "active_edges": [], "edge_badges": {}, "vars": {}}

	var cur_id: String = String(fsm.get_current_state_id())
	var st_time: float = snappedf(fsm.get_state_time(), 0.01)
	var active_nodes: Dictionary = {}
	if not cur_id.is_empty():
		active_nodes[cur_id] = {"state": "RUNNING", "badge": "%.2fs" % st_time}

	var vars_out: Dictionary = fsm.blackboard.get_all()
	vars_out["current_state"] = cur_id
	vars_out["previous_state"] = String(fsm.get_previous_state_id())
	vars_out["state_time"] = st_time
	vars_out["total_transitions"] = fsm.get_total_transitions()
	var sub_st: String = fsm.get_active_sub_state_path()
	if not sub_st.is_empty():
		vars_out["sub_state"] = sub_st

	return {"active_nodes": active_nodes, "active_edges": [], "edge_badges": {}, "vars": vars_out}


## 采样享元 [BTTree] 在指定 [BTContext] 上的当前帧节点状态、流向边、效用分支实时分值与黑板快照。
static func capture_bt_frame(tree: BTTree, ctx: BTContext, binding: GraphDebugBinding) -> Dictionary:
	var ast: BTGraphDef = tree.get_ast() if tree != null else null
	var active_nodes: Dictionary = {}
	var active_edges: Array[Array] = []
	var edge_badges: Dictionary = {}
	if ast != null and ast.root != null and ctx != null:
		_collect_bt_live_status(ast.root, ctx, active_nodes, active_edges, edge_badges)

	if ctx != null and binding != null:
		binding.evaluate_active_node_breakpoints(ctx.tick_count, active_nodes)

	var clean_vars: Dictionary = {}
	if ctx != null:
		var bb_snap: Dictionary = ctx.blackboard.get_data_snapshot()
		for k: Variant in bb_snap.keys():
			var ks: String = str(k)
			if not ks.begins_with("__bt_"):
				clean_vars[ks] = bb_snap[k]
		clean_vars["tick_count"] = ctx.tick_count
		clean_vars["active_leaf"] = ctx.get_active_leaf_title()

	return {
		"active_nodes": active_nodes,
		"active_edges": active_edges,
		"edge_badges": edge_badges,
		"vars": clean_vars,
	}


static func _collect_bt_live_status(
	node_def: BTNodeDef,
	ctx: BTContext,
	active_nodes: Dictionary,
	active_edges: Array[Array],
	edge_badges: Dictionary
) -> int:
	if node_def == null:
		return -1
	var st: int = ctx.get_live_node_status(node_def.node_id)
	var nid_str: String = "n%d" % node_def.node_id
	if st >= 0:
		var st_name: String = String(BTStatus.to_string_name(st))
		active_nodes[nid_str] = {"state": st_name, "badge": st_name}
		if node_def.node_type == &"UtilitySelector":
			var raw_scores: Variant = ctx.blackboard.get_node_mem(node_def.node_id, &"last_scores", null)
			if raw_scores is Array:
				var sc_arr: Array = raw_scores as Array
				for i: int in range(mini(node_def.children.size(), sc_arr.size())):
					var u_ch: BTNodeDef = node_def.children[i] as BTNodeDef
					if u_ch != null:
						edge_badges["%s->n%d" % [nid_str, u_ch.node_id]] = "%.2f" % float(sc_arr[i])
	for ch_var: Variant in node_def.children:
		var ch_def: BTNodeDef = ch_var as BTNodeDef
		if ch_def == null:
			continue
		var child_st: int = _collect_bt_live_status(ch_def, ctx, active_nodes, active_edges, edge_badges)
		var is_running_flow: bool = (st == BTStatus.Status.RUNNING and child_st == BTStatus.Status.RUNNING)
		var is_success_flow: bool = (st == BTStatus.Status.SUCCESS and child_st == BTStatus.Status.SUCCESS)
		if is_running_flow or is_success_flow:
			active_edges.append([nid_str, "n%d" % ch_def.node_id])
	return st

#endregion
