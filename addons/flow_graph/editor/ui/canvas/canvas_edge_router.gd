@tool
extends RefCounted

## 障碍物感知多态边路由薄协调门面（Obstacle-Aware Multi-Archetype Edge Router Facade）。[br]
##
## 统一编排四遍正交路由管线并委派至专用子模块：[br]
## - [`FsmHubEdgeRouter`](routing/fsm_hub_edge_router.gd)：本地回流胶囊、套娃回跳弧、平行双轨与 `[Any State]` 总线；[br]
## - [`BtBusEdgeRouter`](routing/bt_bus_edge_router.gd)：BT 正交分叉主干与 `#1/#2` 优先级/权重元数据；[br]
## - [`DagChannelEdgeRouter`](routing/dag_channel_edge_router.gd)：Sugiyama 哑节点走廊与四向分槽折线；[br]
## - [`EdgeObstacleAvoidance`](routing/edge_obstacle_avoidance.gd)：净空巷道扫描与零碰撞外包络绕行搜索。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)
const EdgeObstacleAvoidance = preload(FlowGraphContracts.SCRIPT_ROUTE_OBSTACLE)
const FsmHubEdgeRouter = preload(FlowGraphContracts.SCRIPT_ROUTE_FSM_HUB)
const BtBusEdgeRouter = preload(FlowGraphContracts.SCRIPT_ROUTE_BT_BUS)
const DagChannelEdgeRouter = preload(FlowGraphContracts.SCRIPT_ROUTE_DAG_CHANNEL)


static func build_routes(
	graph: MermaidGraphModel,
	plan: Dictionary,
	nodes: Dictionary,
	node_order: Array[String]
) -> Dictionary:
	var routed_edges: Array[Dictionary] = []
	var edge_by_key: Dictionary = {}
	var any_origin_boxes: Array[Rect2] = []
	var any_zone_rect := Rect2()
	var has_any_state_zone: bool = false

	if graph == null or nodes.is_empty():
		return {
			"routed_edges": routed_edges,
			"edge_by_key": edge_by_key,
			"has_any_state_zone": false,
			"any_zone_rect": any_zone_rect,
			"any_origin_boxes": any_origin_boxes,
		}

	var arch: StringName = plan.get("archetype", MermaidMetrics.ARCHETYPE_DAG_PIPELINE) as StringName
	var interrupt_redirects: Dictionary = plan.get("interrupt_redirect_edges", {}) as Dictionary
	var transient_only: Dictionary = plan.get("transient_only_edges", {}) as Dictionary
	var interrupt_nodes: Array = plan.get("interrupt_nodes", []) as Array
	var bt_composites: Dictionary = plan.get("bt_composites", {}) as Dictionary
	var edge_wps_map: Dictionary = plan.get("edge_waypoints", {}) as Dictionary
	var is_vertical: bool = (graph.direction == &"TD" or graph.direction == &"TB")

	var bt_fallback_children: Dictionary = BtBusEdgeRouter.build_bt_children_order_map(graph, nodes)
	var portal_obstacles: Array[Rect2] = []
	var existing_polylines: Array[PackedVector2Array] = []
	var deferred_backs: Dictionary = {}
	var corridor_lanes: Dictionary = {}

	# Pass 1: 优先放置 [-> Hub] 本地回流胶囊并注册为硬障碍物
	FsmHubEdgeRouter.route_portal_returns(
		graph, plan, nodes, node_order, portal_obstacles, existing_polylines, routed_edges, edge_by_key
	)

	# Pass 2: 同行/同列回跳弧按跨度升序俄罗斯套娃排轨
	FsmHubEdgeRouter.route_same_band_back_arcs(
		graph, plan, nodes, node_order, is_vertical, deferred_backs, existing_polylines, routed_edges, edge_by_key
	)

	# Pass 3: 正交主干、BT 分叉总线、双向双轨、Sugiyama 走廊与自动避障绕行
	var raw_pair_set: Dictionary = {}
	for ed_scan: Dictionary in graph.edges:
		var fs: String = str(ed_scan["from"])
		var ts: String = str(ed_scan["to"])
		var pair_k: String = "%s->%s" % [fs, ts]
		if fs != "*" and not edge_by_key.has(pair_k) and not interrupt_redirects.has(pair_k) and not transient_only.has(pair_k):
			raw_pair_set[pair_k] = true

	var port_maps: Dictionary = DagChannelEdgeRouter.build_directional_port_maps(
		graph, nodes, edge_by_key, interrupt_redirects, transient_only, arch
	)
	var row_alleys_y: Array[float] = EdgeObstacleAvoidance.collect_horizontal_alleys(nodes, node_order, portal_obstacles)
	var col_alleys_x: Array[float] = EdgeObstacleAvoidance.collect_vertical_alleys(nodes, node_order, portal_obstacles)

	for ed: Dictionary in graph.edges:
		var f: String = str(ed["from"])
		var t: String = str(ed["to"])
		if f == "*" or f == t or not nodes.has(f) or not nodes.has(t):
			continue
		var key: String = "%s->%s" % [f, t]
		if edge_by_key.has(key) or interrupt_redirects.has(key) or transient_only.has(key):
			continue

		var lbl: String = str(ed.get("label", "")).strip_edges()
		var target_rec: Dictionary = nodes[t] as Dictionary
		var rf: Rect2 = (nodes[f] as Dictionary)["rect"] as Rect2
		var rt: Rect2 = target_rec["rect"] as Rect2
		var obstacles: Array[Rect2] = EdgeObstacleAvoidance.gather_obstacles_excluding(f, t, nodes, node_order, portal_obstacles)
		var bt_siblings: Array = (
			bt_composites[f] as Array if bt_composites.has(f)
			else (bt_fallback_children.get(f, []) as Array)
		)

		# 3A. Sugiyama 跨层哑节点走廊
		var sugi_res: Dictionary = DagChannelEdgeRouter.try_route_sugiyama_corridor(
			key, f, t, lbl, rf, rt, edge_wps_map, is_vertical
		)
		if bool(sugi_res["ok"]):
			var rec_wp: Dictionary = sugi_res["record"] as Dictionary
			if not bt_siblings.is_empty():
				BtBusEdgeRouter.annotate_bt_metadata(rec_wp, ed, target_rec, bt_siblings, t)
			existing_polylines.append(rec_wp["pts"] as PackedVector2Array)
			routed_edges.append(rec_wp)
			edge_by_key[key] = rec_wp
			continue

		# 3B. BT 正交分叉主干总线 + #1/#2 优先级序号
		if arch == MermaidMetrics.ARCHETYPE_BT_TREE and bt_composites.has(f):
			var bt_res: Dictionary = BtBusEdgeRouter.try_route_bt_bus(
				ed, key, f, t, lbl, rf, rt, bt_siblings, target_rec, is_vertical, obstacles
			)
			if bool(bt_res["ok"]):
				var rec_bt: Dictionary = bt_res["record"] as Dictionary
				existing_polylines.append(rec_bt["pts"] as PackedVector2Array)
				routed_edges.append(rec_bt)
				edge_by_key[key] = rec_bt
				continue

		# 3C. 双向平行双轨
		var rev_key: String = "%s->%s" % [t, f]
		if raw_pair_set.has(rev_key) and not deferred_backs.has(key):
			var twin_res: Dictionary = FsmHubEdgeRouter.try_route_orthogonal_twin(f, t, rf, rt, lbl, obstacles)
			if bool(twin_res["ok"]):
				var pts_tw: PackedVector2Array = twin_res["pts"] as PackedVector2Array
				existing_polylines.append(pts_tw)
				var rec_tw: Dictionary = {
					"key": key, "from": f, "to": t, "label": lbl,
					"route": CanvasGeometry.ROUTE_TWIN, "pts": pts_tw,
					"pill_pos": twin_res["pill_pos"] as Vector2, "branch_index": -1,
				}
				routed_edges.append(rec_tw)
				edge_by_key[key] = rec_tw
				continue

		# 3D. 单向无遮挡直连或端口分槽正交圆角折线
		if not deferred_backs.has(key):
			var direct_res: Dictionary = DagChannelEdgeRouter.try_route_clean_direct_or_elbow(f, t, rf, rt, port_maps, obstacles)
			if bool(direct_res["ok"]):
				var pts_d: PackedVector2Array = direct_res["pts"] as PackedVector2Array
				existing_polylines.append(pts_d)
				var rec_d: Dictionary = {
					"key": key, "from": f, "to": t, "label": lbl,
					"route": int(direct_res["route"]), "pts": pts_d,
					"pill_pos": direct_res["pill_pos"] as Vector2, "branch_index": -1,
				}
				if not bt_siblings.is_empty():
					BtBusEdgeRouter.annotate_bt_metadata(rec_d, ed, target_rec, bt_siblings, t)
				routed_edges.append(rec_d)
				edge_by_key[key] = rec_d
				continue

		# 3E. 障碍物外包络或净空巷道绕行兜底
		var detour_res: Dictionary = EdgeObstacleAvoidance.route_obstacle_free_detour(
			f, t, rf, rt, obstacles, existing_polylines, row_alleys_y, col_alleys_x, corridor_lanes
		)
		var pts_det: PackedVector2Array = detour_res["pts"] as PackedVector2Array
		existing_polylines.append(pts_det)
		var rec_det: Dictionary = {
			"key": key, "from": f, "to": t, "label": lbl,
			"route": CanvasGeometry.ROUTE_ORTHO_ELBOW, "pts": pts_det,
			"pill_pos": detour_res["pill_pos"] as Vector2, "branch_index": -1,
		}
		if not bt_siblings.is_empty():
			BtBusEdgeRouter.annotate_bt_metadata(rec_det, ed, target_rec, bt_siblings, t)
		routed_edges.append(rec_det)
		edge_by_key[key] = rec_det

	# Pass 4: 构建底部 [Any State] 全局中断区总线
	if arch == MermaidMetrics.ARCHETYPE_FSM_HUB and not interrupt_nodes.is_empty():
		var any_info: Dictionary = FsmHubEdgeRouter.build_any_state_zone_routes(interrupt_nodes, nodes, routed_edges, edge_by_key)
		has_any_state_zone = bool(any_info["has_zone"])
		any_zone_rect = any_info["zone_rect"] as Rect2
		any_origin_boxes = any_info["origin_boxes"] as Array[Rect2]

	return {
		"routed_edges": routed_edges,
		"edge_by_key": edge_by_key,
		"has_any_state_zone": has_any_state_zone,
		"any_zone_rect": any_zone_rect,
		"any_origin_boxes": any_origin_boxes,
	}
