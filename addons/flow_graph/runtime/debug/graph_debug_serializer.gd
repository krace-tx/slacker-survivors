class_name GraphDebugSerializer
extends RefCounted

## 调试拓扑与帧快照无状态归一化器（Stateless Graph Debug Topology & Frame Serializer）。[br]
##
## 由 [GraphDebugBinding] 委托调用，将 `StateMachine` 与 `BTTree` 的运行态与静态 AST 归一化为标准图 IR 与帧遥测字典。


#region FSM & BT Topology / Frame Builders
static func export_fsm_topology(fsm: StateMachine, discovered_edges: Dictionary) -> Dictionary:
	if fsm == null or fsm.get_ast() == null:
		return {}
	var ir: Dictionary = fsm.get_ast().to_mermaid_ir()
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
				"from": parts[0], "to": parts[1], "label": str(discovered_edges[pk]),
				"priority": 0, "order": order_i, "discovered": true, "params": {},
			})
			order_i += 1
	ir["edges"] = edges_out
	return ir


static func capture_fsm_frame(fsm: StateMachine) -> Dictionary:
	var snap: Dictionary = fsm.get_telemetry_snapshot()
	var cur_id: String = str(snap.get("current_state", ""))
	var st_time: float = float(snap.get("state_time", 0.0))
	var active_nodes: Dictionary = {}
	if not cur_id.is_empty():
		active_nodes[cur_id] = {"state": "RUNNING", "badge": "%.2fs" % st_time}

	var vars_out: Dictionary = fsm.blackboard.get_all()
	vars_out["current_state"] = cur_id
	vars_out["previous_state"] = str(snap.get("previous_state", ""))
	vars_out["state_time"] = st_time
	vars_out["total_transitions"] = int(snap.get("total_transitions", 0))
	var sub_st: String = str(snap.get("sub_state", ""))
	if not sub_st.is_empty():
		vars_out["sub_state"] = sub_st

	return {"active_nodes": active_nodes, "active_edges": [], "vars": vars_out}


static func capture_bt_frame(tree: BTTree, ctx: BTContext, binding: GraphDebugBinding) -> Dictionary:
	var ast: BTGraphDef = tree.get_ast() if tree != null else null
	var active_nodes: Dictionary = {}
	var active_edges: Array[Array] = []
	if ast != null and ast.root != null and ctx != null:
		_collect_bt_live_status(ast.root, ctx, active_nodes, active_edges)

	if ctx != null and binding != null:
		binding.evaluate_bt_breakpoints(ctx.tick_count, active_nodes)

	var clean_vars: Dictionary = {}
	if ctx != null:
		var bb_snap: Dictionary = ctx.blackboard.get_data_snapshot()
		for k: Variant in bb_snap.keys():
			var ks: String = str(k)
			if not ks.begins_with("__bt_"):
				clean_vars[ks] = bb_snap[k]
		clean_vars["tick_count"] = ctx.tick_count
		clean_vars["active_leaf"] = ctx.get_active_leaf_title()

	return {"active_nodes": active_nodes, "active_edges": active_edges, "vars": clean_vars}


static func _collect_bt_live_status(
	node_def: BTNodeDef,
	ctx: BTContext,
	active_nodes: Dictionary,
	active_edges: Array[Array]
) -> int:
	if node_def == null:
		return -1
	var st: int = ctx.get_live_node_status(node_def.node_id)
	var nid_str: String = "n%d" % node_def.node_id
	if st >= 0:
		var st_name: String = String(BTStatus.to_string_name(st))
		active_nodes[nid_str] = {"state": st_name, "badge": st_name}
	for ch_var: Variant in node_def.children:
		var ch_def: BTNodeDef = ch_var as BTNodeDef
		if ch_def == null:
			continue
		var child_st: int = _collect_bt_live_status(ch_def, ctx, active_nodes, active_edges)
		var is_running_flow: bool = (st == BTStatus.Status.RUNNING and child_st == BTStatus.Status.RUNNING)
		var is_success_flow: bool = (st == BTStatus.Status.SUCCESS and child_st == BTStatus.Status.SUCCESS)
		if is_running_flow or is_success_flow:
			active_edges.append([nid_str, "n%d" % ch_def.node_id])
	return st
#endregion
