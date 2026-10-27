@tool
extends RefCounted

## 画布运行期遥测高亮、脉冲彗星与打断提示生命周期状态机（Canvas Live Telemetry & Pulse State）。[br]
##
## 由 [`MermaidGraphCanvas`](mermaid_graph_canvas.gd) 持有并按帧推进，统一管理活跃节点态、常驻激活边、瞬态跃迁脉冲、尾迹与 `[Any State]` 打断来源胶囊倒计时。

const MermaidMetrics = preload(FlowGraphContracts.SCRIPT_METRICS)
const CanvasGeometry = preload(FlowGraphContracts.SCRIPT_CANVAS_GEOMETRY)

var active_node_states: Dictionary = {}
var continuous_edges: Array[Array] = []
var burst_pulses: Array[Dictionary] = []
var recent_trail_keys: Array[String] = []
var interrupt_source_hints: Dictionary = {}
var hub_arrival_flash: float = 0.0
var anim_clock: float = 0.0


func clear() -> void:
	active_node_states.clear()
	continuous_edges.clear()
	burst_pulses.clear()
	recent_trail_keys.clear()
	interrupt_source_hints.clear()
	hub_arrival_flash = 0.0


func has_active_animations() -> bool:
	return (
		(not active_node_states.is_empty())
		or (not continuous_edges.is_empty())
		or (not burst_pulses.is_empty())
		or (not interrupt_source_hints.is_empty())
		or hub_arrival_flash > 0.0
	)


func tick(delta: float) -> bool:
	if not has_active_animations():
		return false
	anim_clock += delta
	if hub_arrival_flash > 0.0:
		hub_arrival_flash = maxf(0.0, hub_arrival_flash - delta * 1.45)

	for i: int in range(burst_pulses.size() - 1, -1, -1):
		var p: Dictionary = burst_pulses[i]
		var dur: float = maxf(0.15, float(p.get("dur", 0.82)))
		var nt: float = float(p.get("t", 0.0)) + delta / dur
		if nt >= 1.0:
			burst_pulses.remove_at(i)
		else:
			p["t"] = nt

	var expired_hints: Array[String] = []
	for tid_var: Variant in interrupt_source_hints.keys():
		var tid: String = str(tid_var)
		var hrec: Dictionary = interrupt_source_hints[tid] as Dictionary
		var rem: float = float(hrec.get("ttl", 0.0)) - delta
		if rem <= 0.0:
			expired_hints.append(tid)
		else:
			hrec["ttl"] = rem
	for ex_id: String in expired_hints:
		interrupt_source_hints.erase(ex_id)
	return true


func apply_frame(frame: Dictionary) -> void:
	var raw_active: Variant = frame.get("active_nodes", {})
	active_node_states = (raw_active as Dictionary).duplicate(true) if raw_active is Dictionary else {}
	continuous_edges.clear()
	var raw_edges: Variant = frame.get("active_edges", [])
	if raw_edges is Array:
		for item: Variant in raw_edges as Array:
			if item is Array and (item as Array).size() >= 2:
				var pair: Array = item as Array
				continuous_edges.append([str(pair[0]), str(pair[1])])


func trigger_pulse(
	from_id: String,
	to_id: String,
	nodes: Dictionary,
	edge_by_key: Dictionary,
	plan: Dictionary
) -> void:
	if nodes.is_empty():
		return
	var hub_id: String = str(plan.get("hub_id", ""))
	var interrupt_set: Dictionary = plan.get("interrupt_set", {}) as Dictionary
	var route_key: String = "%s->%s" % [from_id, to_id]

	if interrupt_set.has(to_id):
		route_key = "*->%s" % to_id
		if nodes.has(from_id):
			var src_rec: Dictionary = nodes[from_id] as Dictionary
			var src_short: String = MermaidMetrics.extract_short_name(str(src_rec.get("title", from_id)), from_id)
			interrupt_source_hints[to_id] = {"from_title": src_short, "ttl": 2.4}

	var portal_map: Dictionary = plan.get("portal_return_edges", {}) as Dictionary
	if portal_map.has("%s->%s" % [from_id, to_id]) and to_id == hub_id:
		hub_arrival_flash = 1.0

	var transient_pts := PackedVector2Array()
	if not edge_by_key.has(route_key) and nodes.has(from_id) and nodes.has(to_id):
		var ra: Rect2 = (nodes[from_id] as Dictionary)["rect"] as Rect2
		var rb: Rect2 = (nodes[to_id] as Dictionary)["rect"] as Rect2
		var pa: Vector2 = CanvasGeometry.rect_perimeter_point(ra, rb.get_center())
		var pb: Vector2 = CanvasGeometry.rect_perimeter_point(rb, ra.get_center())
		var mid: Vector2 = (pa + pb) * 0.5
		var perp := Vector2(-(pb.y - pa.y), pb.x - pa.x).normalized()
		transient_pts = CanvasGeometry.sample_quad_bezier(pa, mid + perp * 28.0, pb, 16)

	burst_pulses.append({"key": route_key, "from": from_id, "to": to_id, "t": 0.0, "dur": 0.82, "custom_pts": transient_pts})
	recent_trail_keys.erase(route_key)
	recent_trail_keys.push_front(route_key)
	while recent_trail_keys.size() > 2:
		recent_trail_keys.pop_back()
