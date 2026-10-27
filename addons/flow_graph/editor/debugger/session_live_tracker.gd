@tool
extends RefCounted

## 运行期多实例注册表与离线快照归档辅助器（Session Live & Snapshot Tracker）。[br]
##
## 封装 `LIVE` 实例注册/注销、拓扑/遥测帧写入及停止运行后向 `SNAPSHOT` 无损归档（含继承 60 帧历史与断点集）。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)
const SessionFrameRingBuffer = preload(FlowGraphContracts.SCRIPT_SESSION_FRAME_BUFFER)


static func make_snapshot_key(desc: Dictionary) -> String:
	return "%s::%s" % [str(desc.get("primary_class", "Graph")), str(desc.get("title", "Instance"))]


static func store_snapshot(
	mid: int,
	live_rec: Dictionary,
	snapshots: Dictionary,
	snapshot_key_list: Array[String],
	ring_buffer: SessionFrameRingBuffer,
	breakpoints_by_key: Dictionary
) -> String:
	var desc: Dictionary = (live_rec.get("desc", {}) as Dictionary).duplicate(true)
	var snap_key: String = make_snapshot_key(desc)
	var frame_copy: Dictionary = (live_rec.get("frame", {}) as Dictionary).duplicate(true)
	frame_copy["paused"] = false
	snapshots[snap_key] = {
		"key": snap_key, "desc": desc, "graph": live_rec.get("graph", null),
		"plan": (live_rec.get("plan", {}) as Dictionary).duplicate(true), "frame": frame_copy,
	}
	if not snapshot_key_list.has(snap_key):
		snapshot_key_list.append(snap_key)
	var mid_key: String = str(mid)
	ring_buffer.copy_history(mid_key, snap_key)
	ring_buffer.clear_session(mid_key)
	if breakpoints_by_key.has(mid_key):
		breakpoints_by_key[snap_key] = (breakpoints_by_key[mid_key] as Array[String]).duplicate()
	return snap_key


static func register_instance(
	memory_id: int,
	descriptor: Dictionary,
	topology: Dictionary,
	frame: Dictionary,
	live_instances: Dictionary,
	instance_id_list: Array[int],
	snapshots: Dictionary,
	snapshot_key_list: Array[String],
	ring_buffer: SessionFrameRingBuffer,
	breakpoints_by_key: Dictionary
) -> String:
	var g := MermaidGraphModel.new()
	g.load_from_topology_dict(topology)
	live_instances[memory_id] = {
		"desc": descriptor, "graph": g,
		"plan": MermaidLayout.apply_layout(g, false), "frame": frame,
	}
	if not instance_id_list.has(memory_id):
		instance_id_list.append(memory_id)

	var mid_key: String = str(memory_id)
	ring_buffer.clear_session(mid_key)
	ring_buffer.record_frame(mid_key, frame, true)
	var src_path: String = str(descriptor.get("source_resource_path", ""))
	if not src_path.is_empty() and breakpoints_by_key.has(src_path):
		breakpoints_by_key[mid_key] = (breakpoints_by_key[src_path] as Array[String]).duplicate()

	var snap_key: String = make_snapshot_key(descriptor)
	if snapshots.has(snap_key):
		snapshots.erase(snap_key)
		snapshot_key_list.erase(snap_key)
	return snap_key


static func update_topology(memory_id: int, topology: Dictionary, live_instances: Dictionary) -> bool:
	if not live_instances.has(memory_id):
		return false
	var rec: Dictionary = live_instances[memory_id] as Dictionary
	var prev_g: MermaidGraphModel = rec.get("graph", null) as MermaidGraphModel
	var g := MermaidGraphModel.new()
	g.load_from_topology_dict(topology)
	if prev_g != null:
		for prev_nd: Dictionary in prev_g.nodes:
			if bool(prev_nd.get("has_pos", false)):
				g.set_node_pos(str(prev_nd["id"]), prev_nd.get("pos", Vector2.ZERO) as Vector2)
	rec["graph"] = g
	rec["plan"] = MermaidLayout.apply_layout(g, false)
	return true


static func update_frame(
	memory_id: int,
	frame: Dictionary,
	live_instances: Dictionary,
	ring_buffer: SessionFrameRingBuffer,
	breakpoints_by_key: Dictionary
) -> bool:
	if not live_instances.has(memory_id):
		return false
	var rec: Dictionary = live_instances[memory_id] as Dictionary
	rec["frame"] = frame
	var mid_key: String = str(memory_id)
	var force_rec: bool = not str(frame.get("hit_breakpoint", "")).is_empty()
	ring_buffer.record_frame(mid_key, frame, force_rec)
	if frame.has("breakpoints") and frame["breakpoints"] is Array:
		var bp_list: Array[String] = []
		for bp_v: Variant in frame["breakpoints"] as Array:
			bp_list.append(str(bp_v))
		breakpoints_by_key[mid_key] = bp_list
	return true
