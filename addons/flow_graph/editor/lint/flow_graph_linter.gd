@tool
extends RefCounted

## FlowGraph 静态拓扑校验器（Static Graph Topology Linter）。[br]
##
## 在编辑期即时诊断 FSM / BT 蓝图的常见结构缺陷（空图、缺失初始状态、孤岛节点、组合/装饰/叶节点子数违例及子图死循环/路径缺失）。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)

const SEVERITY_ERROR: String = "error"
const SEVERITY_WARNING: String = "warning"


static func lint(graph: MermaidGraphModel, owner_res_path: String = "") -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if graph == null or graph.nodes.is_empty():
		results.append(_make_issue(SEVERITY_WARNING, "EMPTY_GRAPH", "", FlowEditorI18n.t(&"lint.empty_graph")))
		return results

	var eff_schema: StringName = graph.resolve_effective_schema()
	var clean_owner: String = owner_res_path.strip_edges()

	var node_map: Dictionary = {}
	var out_adj: Dictionary = {}
	var in_deg: Dictionary = {}
	var wildcard_targets: Array[String] = []

	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		node_map[nid] = nd
		out_adj[nid] = []
		in_deg[nid] = 0

	for ed: Dictionary in graph.edges:
		if bool(ed.get("discovered", false)):
			continue
		var f: String = str(ed.get("from", "")).strip_edges()
		var t: String = str(ed.get("to", "")).strip_edges()
		if not node_map.has(t):
			continue
		if f == "*":
			if not wildcard_targets.has(t):
				wildcard_targets.append(t)
			continue
		if node_map.has(f) and f != t:
			var children: Array = out_adj[f] as Array
			if not children.has(t):
				children.append(t)
				in_deg[t] = int(in_deg[t]) + 1

	# 1. FSM 初始入口校验
	var seeds: Array[String] = []
	if eff_schema == MermaidGraphModel.SCHEMA_FSM:
		var init_id: String = graph.initial_node_id.strip_edges()
		if init_id.is_empty() or not node_map.has(init_id):
			results.append(_make_issue(
				SEVERITY_ERROR,
				"FSM_NO_INITIAL",
				"",
				FlowEditorI18n.t(&"lint.fsm_no_initial")
			))
		else:
			seeds.append(init_id)
		for wt: String in wildcard_targets:
			if not seeds.has(wt):
				seeds.append(wt)
	else:
		var bt_root: String = graph.initial_node_id.strip_edges()
		if bt_root.is_empty() or not node_map.has(bt_root):
			bt_root = _pick_primary_bt_root(graph, in_deg, out_adj)
		if not bt_root.is_empty():
			seeds.append(bt_root)

	# 2. 从入口（及 FSM 全局打断目标）做 BFS 可达性扫描
	if not seeds.is_empty():
		var visited: Dictionary = {}
		var queue: Array[String] = []
		for s_id: String in seeds:
			visited[s_id] = true
			queue.append(s_id)
		var head: int = 0
		while head < queue.size():
			var cur: String = queue[head]
			head += 1
			for nxt_v: Variant in (out_adj.get(cur, []) as Array):
				var nxt: String = str(nxt_v)
				if not visited.has(nxt):
					visited[nxt] = true
					queue.append(nxt)

		for nd: Dictionary in graph.nodes:
			var nid_u: String = str(nd.get("id", "")).strip_edges()
			if not nid_u.is_empty() and not visited.has(nid_u):
				var title_u: String = str(nd.get("title", nid_u))
				results.append(_make_issue(
					SEVERITY_WARNING,
					"UNREACHABLE_NODE",
					nid_u,
					FlowEditorI18n.t(&"lint.unreachable", [title_u, nid_u])
				))

	# 3. BT 节点度数语义与 FSM / BT 子图路径校验
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		var kind: String = str(nd.get("kind", ""))
		var ntitle: String = str(nd.get("title", nid))
		var child_cnt: int = (out_adj.get(nid, []) as Array).size()
		var params: Dictionary = nd.get("params", {}) as Dictionary if nd.get("params", {}) is Dictionary else {}

		if eff_schema == MermaidGraphModel.SCHEMA_BT:
			if kind == MermaidGraphModel.BT_ROOT_KIND:
				if int(in_deg.get(nid, 0)) > 0:
					results.append(_make_issue(
						SEVERITY_ERROR,
						"BT_ROOT_HAS_PARENT",
						nid,
						FlowEditorI18n.t(&"lint.bt_root_parent", [ntitle])
					))
				if child_cnt != 1:
					results.append(_make_issue(
						SEVERITY_ERROR,
						"BT_ROOT_ARITY",
						nid,
						FlowEditorI18n.t(&"lint.bt_root_arity", [ntitle, child_cnt])
					))
			elif MermaidGraphModel.BT_COMPOSITE_KINDS.has(kind) and child_cnt == 0:
				results.append(_make_issue(
					SEVERITY_ERROR,
					"BT_EMPTY_COMPOSITE",
					nid,
					FlowEditorI18n.t(&"lint.bt_empty_composite", [ntitle])
				))
			elif MermaidGraphModel.BT_DECORATOR_KINDS.has(kind) and child_cnt != 1:
				results.append(_make_issue(
					SEVERITY_ERROR,
					"BT_DECORATOR_ARITY",
					nid,
					FlowEditorI18n.t(&"lint.bt_decorator_arity", [ntitle, child_cnt])
				))
			elif MermaidGraphModel.BT_LEAF_KINDS.has(kind) and child_cnt > 0:
				results.append(_make_issue(
					SEVERITY_WARNING,
					"BT_LEAF_HAS_CHILDREN",
					nid,
					FlowEditorI18n.t(&"lint.bt_leaf_children", [ntitle, child_cnt])
				))

		var sub_path: String = str(params.get("sub_graph_path", nd.get("sub_graph_path", ""))).strip_edges()
		if kind == "SubTree" or not sub_path.is_empty() or bool(params.get("submachine", false)):
			if sub_path.is_empty():
				results.append(_make_issue(
					SEVERITY_ERROR,
					"SUBGRAPH_NOT_FOUND",
					nid,
					FlowEditorI18n.t(&"lint.subgraph_unset", [ntitle])
				))
			elif not clean_owner.is_empty() and sub_path == clean_owner:
				results.append(_make_issue(
					SEVERITY_ERROR,
					"SUBGRAPH_SELF_CYCLE",
					nid,
					FlowEditorI18n.t(&"lint.subgraph_self", [ntitle, sub_path])
				))
			elif not ResourceLoader.exists(sub_path) and not FileAccess.file_exists(sub_path):
				results.append(_make_issue(
					SEVERITY_ERROR,
					"SUBGRAPH_NOT_FOUND",
					nid,
					FlowEditorI18n.t(&"lint.subgraph_missing", [ntitle, sub_path])
				))

	return results


static func _pick_primary_bt_root(graph: MermaidGraphModel, in_deg: Dictionary, out_adj: Dictionary) -> String:
	var explicit_root: String = graph.find_bt_root_id()
	if not explicit_root.is_empty():
		return explicit_root
	var fallback_zero: String = ""
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		if int(in_deg.get(nid, 0)) == 0:
			if fallback_zero.is_empty():
				fallback_zero = nid
			if not (out_adj.get(nid, []) as Array).is_empty():
				return nid
	if not fallback_zero.is_empty():
		return fallback_zero
	return str(graph.nodes[0].get("id", "")).strip_edges()


static func _make_issue(severity: String, code: String, node_id: String, message: String) -> Dictionary:
	return {
		"severity": severity,
		"code": code,
		"node_id": node_id,
		"message": message,
	}
