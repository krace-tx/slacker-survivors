@tool
extends RefCounted

## 运行期多实例注册表与离线快照归档辅助器（Session Live & Snapshot Tracker）。[br]
##
## [b]核心职责：[/b][br]
## 1. 封装 `LIVE` 实例注册/注销、拓扑/遥测帧写入及停止运行后向 `SNAPSHOT` 无损归档（含继承 60 帧历史与断点集）；[br]
## 2. 剥离默认标题中的瞬态内存 ID 后缀生成稳定跨轮次快照键，并在同轮多同名实例归档时自动消歧防覆盖；[br]
## 3. 保护跨轮次继承断点免受首帧异步 IPC 空断点集误冲刷，并在归档时回收失效 `memory_id` 键防止字典膨胀。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)
const SessionFrameRingBuffer = preload(FlowGraphContracts.SCRIPT_SESSION_FRAME_BUFFER)


## 生成跨运行轮次稳定的快照主键（自动剥离默认标题尾部的 `(#12345)` 瞬态实例号）。
static func make_snapshot_key(desc: Dictionary, used_keys_in_pass: Dictionary = {}) -> String:
	var pclass: String = str(desc.get("primary_class", "Graph"))
	var raw_title: String = _strip_transient_id_suffix(str(desc.get("title", "Instance")))
	var owner_name: String = str(desc.get("owner_name", ""))
	var base_key: String = "%s::%s" % [pclass, raw_title]
	if not owner_name.is_empty() and not raw_title.contains(owner_name):
		base_key = "%s::%s@%s" % [pclass, owner_name, raw_title]
	if used_keys_in_pass.is_empty() or not used_keys_in_pass.has(base_key):
		return base_key
	var suffix_idx: int = int(used_keys_in_pass[base_key]) + 1
	used_keys_in_pass[base_key] = suffix_idx
	return "%s #%d" % [base_key, suffix_idx]


static func _strip_transient_id_suffix(title: String) -> String:
	var open_idx: int = title.rfind(" (#")
	if open_idx > 0 and title.ends_with(")"):
		var num_part: String = title.substr(open_idx + 3, title.length() - open_idx - 4)
		if num_part.is_valid_int() or (num_part.begins_with("-") and num_part.substr(1).is_valid_int()):
			return title.substr(0, open_idx)
	return title


static func store_snapshot(
	mid: int,
	live_rec: Dictionary,
	snapshots: Dictionary,
	snapshot_key_list: Array[String],
	ring_buffer: SessionFrameRingBuffer,
	breakpoints_by_key: Dictionary,
	used_keys_in_pass: Dictionary = {}
) -> String:
	var desc: Dictionary = (live_rec.get("desc", {}) as Dictionary).duplicate(true)
	var snap_key: String = make_snapshot_key(desc, used_keys_in_pass)
	if not used_keys_in_pass.has(snap_key):
		used_keys_in_pass[snap_key] = 1

	var frame_copy: Dictionary = (live_rec.get("frame", {}) as Dictionary).duplicate(true)
	frame_copy["paused"] = false
	snapshots[snap_key] = {
		"key": snap_key,
		"desc": desc,
		"graph": live_rec.get("graph", null),
		"plan": (live_rec.get("plan", {}) as Dictionary).duplicate(true),
		"frame": frame_copy,
	}
	if not snapshot_key_list.has(snap_key):
		snapshot_key_list.append(snap_key)

	var mid_key: String = str(mid)
	ring_buffer.copy_history(mid_key, snap_key)
	ring_buffer.clear_session(mid_key)
	if breakpoints_by_key.has(mid_key):
		var bp_copy: Array[String] = (breakpoints_by_key[mid_key] as Array[String]).duplicate()
		breakpoints_by_key[snap_key] = bp_copy
		breakpoints_by_key.erase(mid_key)
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
	g.schema_locked = true

	var mid_key: String = str(memory_id)
	var snap_key: String = make_snapshot_key(descriptor)
	var src_path: String = str(descriptor.get("source_resource_path", ""))

	# 合并来自关联蓝图 (.tres) 或上一轮离线快照 (SNAPSHOT) 预设的节点断点
	var inherited_bps: Array[String] = []
	if not src_path.is_empty() and breakpoints_by_key.has(src_path):
		for bp_id: String in (breakpoints_by_key[src_path] as Array[String]):
			if not inherited_bps.has(bp_id):
				inherited_bps.append(bp_id)
	if breakpoints_by_key.has(snap_key):
		for bp_id: String in (breakpoints_by_key[snap_key] as Array[String]):
			if not inherited_bps.has(bp_id):
				inherited_bps.append(bp_id)

	var has_pending_bps: bool = not inherited_bps.is_empty()
	if has_pending_bps:
		breakpoints_by_key[mid_key] = inherited_bps

	live_instances[memory_id] = {
		"desc": descriptor,
		"graph": g,
		"plan": MermaidLayout.apply_layout(g, false),
		"frame": frame,
		"pending_bp_sync_ttl": 8 if has_pending_bps else 0,
	}
	if not instance_id_list.has(memory_id):
		instance_id_list.append(memory_id)

	ring_buffer.clear_session(mid_key)
	ring_buffer.record_frame(mid_key, frame, true)

	if snapshots.has(snap_key):
		snapshots.erase(snap_key)
		snapshot_key_list.erase(snap_key)
		breakpoints_by_key.erase(snap_key)
	return snap_key


static func update_topology(memory_id: int, topology: Dictionary, live_instances: Dictionary) -> bool:
	if not live_instances.has(memory_id):
		return false
	var rec: Dictionary = live_instances[memory_id] as Dictionary
	var prev_g: MermaidGraphModel = rec.get("graph", null) as MermaidGraphModel
	var g := MermaidGraphModel.new()
	g.load_from_topology_dict(topology)
	g.schema_locked = true
	if prev_g != null:
		for prev_nd: Dictionary in prev_g.nodes:
			if bool(prev_nd.get("has_pos", false)):
				g.set_node_pos(str(prev_nd["id"]), prev_nd.get("pos", Vector2.ZERO) as Vector2)
	rec["graph"] = g
	rec["plan"] = MermaidLayout.apply_layout(g, false)
	rec["pending_bp_sync_ttl"] = 0
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
		var sync_ttl: int = int(rec.get("pending_bp_sync_ttl", 0))
		if sync_ttl > 0:
			var expected_bps: Array[String] = []
			if breakpoints_by_key.has(mid_key):
				expected_bps = breakpoints_by_key[mid_key] as Array[String]
			# 等待异步 set_breakpoint 指令在游戏侧回传一致确认帧后再采信远端列表，防止途中排队的旧帧冲刷本地状态
			if _is_same_breakpoint_set(bp_list, expected_bps) or sync_ttl <= 1:
				rec["pending_bp_sync_ttl"] = 0
				breakpoints_by_key[mid_key] = bp_list
			else:
				rec["pending_bp_sync_ttl"] = sync_ttl - 1
		else:
			breakpoints_by_key[mid_key] = bp_list
	return true


static func _is_same_breakpoint_set(a: Array[String], b: Array[String]) -> bool:
	if a.size() != b.size():
		return false
	for item: String in a:
		if not b.has(item):
			return false
	return true
