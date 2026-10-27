@tool
extends RefCounted

## Mermaid 多态自动布局调度门面（Unified Layout Facade）。[br]
##
## 串联拓扑语义分类器（[`MermaidTopologyAnalyzer`](mermaid_topology_analyzer.gd)）、三套专用布局算法、硬性包围盒零重叠推离保障与完整包络世界原点归一化。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const MermaidTopologyAnalyzer = preload(FlowGraphContracts.SCRIPT_TOPOLOGY_ANALYZER)
const FsmHubLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT_FSM_HUB)
const BtContourLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT_BT_CONTOUR)
const SugiyamaDagLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT_SUGIYAMA_DAG)

const ARCHETYPE_FSM_HUB: StringName = MermaidMetrics.ARCHETYPE_FSM_HUB
const ARCHETYPE_BT_TREE: StringName = MermaidMetrics.ARCHETYPE_BT_TREE
const ARCHETYPE_DAG_PIPELINE: StringName = MermaidMetrics.ARCHETYPE_DAG_PIPELINE


static func analyze_topology(graph: MermaidGraphModel) -> Dictionary:
	return MermaidTopologyAnalyzer.analyze_topology(graph)


static func apply_layout(graph: MermaidGraphModel, force_override: bool = false) -> Dictionary:
	if graph == null or graph.nodes.is_empty():
		return {}

	var need_layout: bool = force_override
	if not need_layout:
		for nd: Dictionary in graph.nodes:
			if not bool(nd.get("has_pos", false)):
				need_layout = true
				break

	var plan: Dictionary = MermaidTopologyAnalyzer.analyze_topology(graph)
	if not need_layout:
		return plan

	var arch: StringName = plan["archetype"] as StringName
	match arch:
		ARCHETYPE_FSM_HUB:
			FsmHubLayout.apply(graph, plan)
		ARCHETYPE_BT_TREE:
			BtContourLayout.apply(graph, plan)
		_:
			SugiyamaDagLayout.apply(graph, plan)

	_enforce_zero_node_overlap(graph, plan)
	_normalize_graph_origin(graph, plan)
	return plan


static func _enforce_zero_node_overlap(graph: MermaidGraphModel, plan: Dictionary) -> void:
	## 刚性包围盒（含右侧/顶部回流胶囊包络）零重叠兜底分离遍，从数学上杜绝任何节点或终端重叠。
	var count: int = graph.nodes.size()
	if count < 2:
		return

	var hub_id: String = str(plan.get("hub_id", ""))
	var hub_short: String = str(plan.get("hub_short_title", hub_id))
	var portal_returns: Dictionary = plan.get("portal_return_edges", {}) as Dictionary
	var fwd_out: Dictionary = plan.get("fwd_out", {}) as Dictionary
	var edge_labels: Dictionary = {}
	for ed: Dictionary in graph.edges:
		edge_labels["%s->%s" % [str(ed["from"]), str(ed["to"])]] = str(ed.get("label", ""))

	var sizes: Array[Vector2] = []
	var extra_tl: Array[Vector2] = []
	var extra_br: Array[Vector2] = []
	for i: int in range(count):
		var nd: Dictionary = graph.nodes[i]
		var nid: String = str(nd["id"])
		var sz: Vector2 = MermaidMetrics.estimate_node_size(nd)
		sizes.append(sz)
		var tl := Vector2.ZERO
		var br := Vector2.ZERO
		var pkey: String = "%s->%s" % [nid, hub_id]
		if portal_returns.has(pkey):
			var plbl: String = str(edge_labels.get(pkey, ""))
			var pw: float = MermaidMetrics.estimate_portal_pill_width(hub_short, plbl)
			if (fwd_out.get(nid, []) as Array).is_empty():
				br.x = 30.0 + pw
			else:
				tl.y = 42.0
				br.x = maxf(0.0, (sz.x * 0.66 + pw * 0.5) - sz.x)
		extra_tl.append(tl)
		extra_br.append(br)

	var pad := Vector2(20.0, 18.0)
	for _iter: int in range(8):
		var moved: bool = false
		for i: int in range(count):
			var pi: Vector2 = graph.nodes[i].get("pos", Vector2.ZERO) as Vector2
			var ri := Rect2(pi - extra_tl[i], sizes[i] + extra_tl[i] + extra_br[i]).grow_individual(pad.x * 0.5, pad.y * 0.5, pad.x * 0.5, pad.y * 0.5)
			for j: int in range(i + 1, count):
				var pj: Vector2 = graph.nodes[j].get("pos", Vector2.ZERO) as Vector2
				var rj := Rect2(pj - extra_tl[j], sizes[j] + extra_tl[j] + extra_br[j]).grow_individual(pad.x * 0.5, pad.y * 0.5, pad.x * 0.5, pad.y * 0.5)
				if not ri.intersects(rj):
					continue
				var overlap_x: float = minf(ri.end.x, rj.end.x) - maxf(ri.position.x, rj.position.x)
				var overlap_y: float = minf(ri.end.y, rj.end.y) - maxf(ri.position.y, rj.position.y)
				var nid_i: String = str(graph.nodes[i]["id"])
				var nid_j: String = str(graph.nodes[j]["id"])
				var wi: float = 0.0 if nid_i == hub_id else 0.5
				var wj: float = 1.0 if nid_i == hub_id else (0.0 if nid_j == hub_id else 0.5)
				if nid_j == hub_id:
					wi = 1.0
				if overlap_y <= overlap_x:
					var dir_y: float = -1.0 if ri.get_center().y <= rj.get_center().y else 1.0
					pi.y += dir_y * overlap_y * wi
					pj.y -= dir_y * overlap_y * wj
				else:
					var dir_x: float = -1.0 if ri.get_center().x <= rj.get_center().x else 1.0
					pi.x += dir_x * overlap_x * wi
					pj.x -= dir_x * overlap_x * wj
				graph.nodes[i]["pos"] = pi
				graph.nodes[j]["pos"] = pj
				ri = Rect2(pi - extra_tl[i], sizes[i] + extra_tl[i] + extra_br[i]).grow_individual(pad.x * 0.5, pad.y * 0.5, pad.x * 0.5, pad.y * 0.5)
				moved = true
		if not moved:
			break


static func _normalize_graph_origin(graph: MermaidGraphModel, plan: Dictionary) -> void:
	if graph.nodes.is_empty():
		return
	var hub_id: String = str(plan.get("hub_id", ""))
	var portal_returns: Dictionary = plan.get("portal_return_edges", {}) as Dictionary
	var fwd_out: Dictionary = plan.get("fwd_out", {}) as Dictionary
	var int_set: Dictionary = plan.get("interrupt_set", {}) as Dictionary

	var min_pt := Vector2(INF, INF)
	for nd: Dictionary in graph.nodes:
		var nid: String = str(nd["id"])
		var p: Vector2 = nd.get("pos", Vector2.ZERO) as Vector2
		var env_tl: Vector2 = p
		if portal_returns.has("%s->%s" % [nid, hub_id]) and not (fwd_out.get(nid, []) as Array).is_empty():
			env_tl.y -= 44.0
		if int_set.has(nid):
			env_tl.x -= 156.0
			env_tl.y -= 54.0
		min_pt = min_pt.min(env_tl)
	if not is_finite(min_pt.x):
		return
	var delta: Vector2 = MermaidMetrics.ORIGIN_PAD - min_pt
	for nd: Dictionary in graph.nodes:
		var p: Vector2 = nd.get("pos", Vector2.ZERO) as Vector2
		nd["pos"] = p + delta
		nd["has_pos"] = true

	var ew_raw: Variant = plan.get("edge_waypoints", {})
	if ew_raw is Dictionary:
		var ew: Dictionary = ew_raw as Dictionary
		for k: Variant in ew.keys():
			var pts: Array = ew[k] as Array
			var shifted: Array[Vector2] = []
			for pt_var: Variant in pts:
				shifted.append((pt_var as Vector2) + delta)
			ew[k] = shifted
