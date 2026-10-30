@tool
extends RefCounted

## Mermaid 四态统一会话仓库（Unified 4-Mode Session Store）。[br]
##
## 统一编排 `DRAFT` / `RESOURCE` / `LIVE` / `SNAPSHOT` 四类会话、跨模态断点集与 60 帧时间轴回放游标；子职责委派至 [`SessionDiskWatcher`](session_disk_watcher.gd)、[`SessionFrameRingBuffer`](session_frame_ring_buffer.gd)、[`SessionSourceApplier`](session_source_applier.gd) 与 [`SessionLiveTracker`](session_live_tracker.gd)。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidCodec = preload(FlowGraphContracts.SCRIPT_CODEC)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)
const MermaidResourceBridge = preload(FlowGraphContracts.SCRIPT_RESOURCE_BRIDGE)
const SessionDiskWatcher = preload(FlowGraphContracts.SCRIPT_SESSION_DISK_WATCHER)
const SessionFrameRingBuffer = preload(FlowGraphContracts.SCRIPT_SESSION_FRAME_BUFFER)
const SessionSourceApplier = preload(FlowGraphContracts.SCRIPT_SESSION_SOURCE_APPLIER)
const SessionLiveTracker = preload(FlowGraphContracts.SCRIPT_SESSION_LIVE_TRACKER)

const MODE_DRAFT: StringName = &"draft"
const MODE_RESOURCE: StringName = &"resource"
const MODE_LIVE: StringName = &"live"
const MODE_SNAPSHOT: StringName = &"snapshot"
const DRAFT_SESSION_KEY: String = "__draft__"

var active_mode: StringName = MODE_DRAFT
var active_key: String = ""
var scrub_index: int = -1
var draft_graph: MermaidGraphModel = MermaidGraphModel.new()
var draft_plan: Dictionary = {}
var resource_sessions: Dictionary = {}
var resource_key_list: Array[String] = []
var live_instances: Dictionary = {}
var instance_id_list: Array[int] = []
var snapshots: Dictionary = {}
var snapshot_key_list: Array[String] = []
var ring_buffer: SessionFrameRingBuffer = SessionFrameRingBuffer.new()
var breakpoints_by_key: Dictionary = {}
var _auto_switched_this_run: bool = false


#region 模式判定、断点管理与历史回放游标

static func format_mem_id(mid: int) -> String:
	return "0x0" if mid == 0 else ("0x%08X" % (mid & 0xFFFFFFFF))


func is_live_selected() -> bool:
	return active_mode == MODE_LIVE and active_key.is_valid_int() and live_instances.has(int(active_key))


func is_snapshot_selected() -> bool:
	return active_mode == MODE_SNAPSHOT and snapshots.has(active_key)


func is_resource_selected() -> bool:
	return active_mode == MODE_RESOURCE and resource_sessions.has(active_key)


func is_editable_mode() -> bool:
	return active_mode == MODE_DRAFT or is_resource_selected()


func is_read_only_topology() -> bool:
	return not is_editable_mode()


func get_selected_live_memory_id() -> int:
	return int(active_key) if is_live_selected() else 0


func get_session_undo_key() -> String:
	return active_key if is_resource_selected() else DRAFT_SESSION_KEY


func get_active_graph() -> MermaidGraphModel:
	return (get_active_record().get("graph", null) as MermaidGraphModel) if (is_live_selected() or is_snapshot_selected() or is_resource_selected()) else draft_graph


func get_graph_for_resource_path(path: String) -> MermaidGraphModel:
	var clean_path: String = path.strip_edges()
	if not clean_path.is_empty() and resource_sessions.has(clean_path):
		return (resource_sessions[clean_path] as Dictionary).get("graph", null) as MermaidGraphModel
	return get_active_graph()


func get_active_plan() -> Dictionary:
	return (get_active_record().get("plan", {}) as Dictionary) if (is_live_selected() or is_snapshot_selected() or is_resource_selected()) else draft_plan


func get_active_record() -> Dictionary:
	if is_live_selected():
		return live_instances[int(active_key)] as Dictionary
	if is_snapshot_selected():
		return snapshots[active_key] as Dictionary
	if is_resource_selected():
		return resource_sessions[active_key] as Dictionary
	return {}


func serialize_active_mermaid(include_pragmas: bool = false) -> String:
	return MermaidCodec.stringify(get_active_graph(), include_pragmas)


func get_active_history_session_id() -> String:
	return active_key if (is_live_selected() or is_snapshot_selected()) else ""


func get_active_history_count() -> int:
	var sid: String = get_active_history_session_id()
	return ring_buffer.get_frame_count(sid) if not sid.is_empty() else 0


func is_scrubbing() -> bool:
	return scrub_index >= 0 and get_active_history_count() > 0


func set_scrub_index(idx: int) -> void:
	var cnt: int = get_active_history_count()
	scrub_index = -1 if (idx < 0 or cnt <= 0) else clampi(idx, 0, cnt - 1)


func get_active_display_frame() -> Dictionary:
	if not is_live_selected() and not is_snapshot_selected():
		return {}
	var sid: String = get_active_history_session_id()
	var cnt: int = ring_buffer.get_frame_count(sid)
	if scrub_index >= 0 and cnt > 0:
		var idx: int = clampi(scrub_index, 0, cnt - 1)
		var f: Dictionary = ring_buffer.get_frame_at(sid, idx)
		f["_is_scrubbing"] = true
		f["_scrub_index"] = idx
		f["_scrub_total"] = cnt
		return f
	return get_active_record().get("frame", {}) as Dictionary


func get_active_breakpoint_key() -> String:
	return active_key if (is_live_selected() or is_snapshot_selected() or is_resource_selected()) else DRAFT_SESSION_KEY


func get_active_breakpoints() -> Array[String]:
	var bkey: String = get_active_breakpoint_key()
	if not breakpoints_by_key.has(bkey):
		var empty: Array[String] = []
		return empty
	return (breakpoints_by_key[bkey] as Array[String]).duplicate()


func has_breakpoint(node_id: String) -> bool:
	return get_active_breakpoints().has(node_id.strip_edges())


## 切换指定节点断点，并在 `RESOURCE` / `LIVE` / `SNAPSHOT` 关联会话间双向同步。
func toggle_breakpoint(node_id: String) -> bool:
	var clean_id: String = node_id.strip_edges()
	if clean_id.is_empty():
		return false
	var bkey: String = get_active_breakpoint_key()
	var list: Array[String] = get_active_breakpoints()
	var next_on: bool = not list.has(clean_id)
	if next_on:
		list.append(clean_id)
	else:
		list.erase(clean_id)
	breakpoints_by_key[bkey] = list

	if is_live_selected() or is_snapshot_selected():
		var linked_res: String = get_active_linked_resource_path()
		if not linked_res.is_empty():
			breakpoints_by_key[linked_res] = list.duplicate()
		if is_live_selected() and live_instances.has(int(active_key)):
			(live_instances[int(active_key)] as Dictionary)["pending_bp_sync_ttl"] = 8
	elif is_resource_selected():
		# 在 .tres 蓝图视图中切换断点时，同步更新所有关联在线实例的本地断点缓存
		for match_rec: Dictionary in find_live_instances_for_resource(active_key):
			var mid: int = int(match_rec.get("memory_id", 0))
			if mid == 0:
				continue
			var mid_key: String = str(mid)
			var inst_bps: Array[String] = []
			if breakpoints_by_key.has(mid_key):
				inst_bps = (breakpoints_by_key[mid_key] as Array[String]).duplicate()
			if next_on and not inst_bps.has(clean_id):
				inst_bps.append(clean_id)
			elif not next_on:
				inst_bps.erase(clean_id)
			breakpoints_by_key[mid_key] = inst_bps
			if live_instances.has(mid):
				(live_instances[mid] as Dictionary)["pending_bp_sync_ttl"] = 8
	return next_on


## 获取当前断点变更应当实时下发 IPC 同步的所有在线实例 `memory_id` 列表。
func get_target_live_ids_for_active_breakpoint() -> Array[int]:
	var ids: Array[int] = []
	if is_live_selected():
		var mid: int = get_selected_live_memory_id()
		if mid != 0:
			ids.append(mid)
	elif is_resource_selected():
		for match_rec: Dictionary in find_live_instances_for_resource(active_key):
			var mid: int = int(match_rec.get("memory_id", 0))
			if mid != 0:
				ids.append(mid)
	return ids


## 当可编辑图发生节点重命名或删除时，同步迁移或清理残留节点断点。
func migrate_breakpoint_on_node_change(old_id: String, new_id: String = "") -> void:
	var clean_old: String = old_id.strip_edges()
	var clean_new: String = new_id.strip_edges()
	if clean_old.is_empty() or clean_old == clean_new:
		return
	var bkey: String = get_active_breakpoint_key()
	if not breakpoints_by_key.has(bkey):
		return
	var list: Array[String] = (breakpoints_by_key[bkey] as Array[String]).duplicate()
	var idx: int = list.find(clean_old)
	if idx < 0:
		return
	if clean_new.is_empty():
		list.remove_at(idx)
	elif not list.has(clean_new):
		list[idx] = clean_new
	else:
		list.remove_at(idx)
	breakpoints_by_key[bkey] = list

#endregion


#region 下拉列表组装与会话切换

func get_dropdown_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [{"mode": MODE_DRAFT, "key": "", "label": FlowEditorI18n.t(&"session.dropdown_draft")}]
	for rkey: String in resource_key_list:
		if resource_sessions.has(rkey):
			var rrec: Dictionary = resource_sessions[rkey] as Dictionary
			var rpath: String = str(rrec.get("path", ""))
			var fname: String = rpath.get_file() if not rpath.is_empty() else FlowEditorI18n.t(&"session.dropdown_unnamed")
			var mark: String = " !*" if bool(rrec.get("external_conflict", false)) else (" *" if bool(rrec.get("dirty", false)) else "")
			entries.append({"mode": MODE_RESOURCE, "key": rkey, "label": FlowEditorI18n.t(&"session.dropdown_res", [fname, mark])})
	for mid: int in instance_id_list:
		if live_instances.has(mid):
			var desc: Dictionary = (live_instances[mid] as Dictionary)["desc"] as Dictionary
			entries.append({"mode": MODE_LIVE, "key": str(mid), "label": FlowEditorI18n.t(&"session.dropdown_live", [str(desc.get("primary_class", "Graph")), str(desc.get("title", "Instance")), format_mem_id(mid)])})
	for skey: String in snapshot_key_list:
		if snapshots.has(skey):
			var sdesc: Dictionary = (snapshots[skey] as Dictionary)["desc"] as Dictionary
			entries.append({"mode": MODE_SNAPSHOT, "key": skey, "label": FlowEditorI18n.t(&"session.dropdown_snap", [str(sdesc.get("primary_class", "Graph")), str(sdesc.get("title", "Instance"))])})
	return entries


func select_by_dropdown_index(idx: int) -> void:
	scrub_index = -1
	var entries: Array[Dictionary] = get_dropdown_entries()
	if idx < 0 or idx >= entries.size():
		select_draft()
		return
	active_mode = entries[idx]["mode"] as StringName
	active_key = str(entries[idx]["key"])


func select_draft() -> void:
	active_mode = MODE_DRAFT
	active_key = ""
	scrub_index = -1

#endregion


#region 资源 (.tres) 直编、外部热重载与实例双向关联

func open_resource_session(res: Resource) -> String:
	if not MermaidResourceBridge.is_supported_resource(res):
		return ""
	var rpath: String = res.resource_path
	var rkey: String = rpath if not rpath.is_empty() else ("mem://%d" % res.get_instance_id())
	scrub_index = -1
	if not (resource_sessions.has(rkey) and bool((resource_sessions[rkey] as Dictionary).get("dirty", false))):
		resource_sessions[rkey] = SessionDiskWatcher.build_session_record(rkey, res, rpath)
		if not resource_key_list.has(rkey):
			resource_key_list.append(rkey)
	active_mode = MODE_RESOURCE
	active_key = rkey
	return rkey


func open_or_focus_resource_path(path: String) -> Dictionary:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty():
		return {"ok": false, "reused": false, "error": FlowEditorI18n.t(&"session.err_empty_path")}
	scrub_index = -1
	if resource_sessions.has(clean_path):
		active_mode = MODE_RESOURCE
		active_key = clean_path
		return {"ok": true, "reused": true, "error": ""}
	var load_res: Dictionary = MermaidResourceBridge.load_resource_at_path(clean_path, false)
	if not bool(load_res.get("ok", false)):
		return {"ok": false, "reused": false, "error": str(load_res.get("error", ""))}
	var rkey: String = open_resource_session(load_res["resource"] as Resource)
	return {"ok": not rkey.is_empty(), "reused": false, "error": "" if not rkey.is_empty() else FlowEditorI18n.t(&"session.err_open_failed", [clean_path])}


func reload_resource_from_disk(path: String) -> Dictionary:
	var clean_path: String = path.strip_edges()
	var load_res: Dictionary = MermaidResourceBridge.load_resource_at_path(clean_path, true)
	if not bool(load_res.get("ok", false)):
		return {"ok": false, "path": clean_path, "error": str(load_res.get("error", ""))}
	resource_sessions[clean_path] = SessionDiskWatcher.build_session_record(clean_path, load_res["resource"] as Resource, clean_path)
	if not resource_key_list.has(clean_path):
		resource_key_list.append(clean_path)
	return {"ok": true, "path": clean_path, "error": ""}


func dismiss_external_conflict(path: String) -> void:
	SessionDiskWatcher.dismiss_conflict(resource_sessions, path)


func check_external_resource_changes(force_content_check: bool = false) -> Dictionary:
	return SessionDiskWatcher.check_external_changes(resource_sessions, resource_key_list, reload_resource_from_disk, force_content_check)


func get_open_resource_status_map() -> Dictionary:
	var out: Dictionary = {}
	for rkey: String in resource_key_list:
		if resource_sessions.has(rkey):
			var rec: Dictionary = resource_sessions[rkey] as Dictionary
			var rpath: String = str(rec.get("path", ""))
			if not rpath.is_empty():
				out[rpath] = "conflict" if bool(rec.get("external_conflict", false)) else ("dirty" if bool(rec.get("dirty", false)) else "clean")
	return out


func get_live_source_paths() -> Dictionary:
	var out: Dictionary = {}
	for mid: int in instance_id_list:
		if live_instances.has(mid):
			var src_p: String = str(((live_instances[mid] as Dictionary).get("desc", {}) as Dictionary).get("source_resource_path", ""))
			if not src_p.is_empty():
				out[src_p] = mid
	return out


func get_active_linked_resource_path() -> String:
	return str((get_active_record().get("desc", {}) as Dictionary).get("source_resource_path", "")) if (is_live_selected() or is_snapshot_selected()) else ""


func find_live_instances_for_resource(path: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	if path.is_empty():
		return matches
	for mid: int in instance_id_list:
		if live_instances.has(mid):
			var desc: Dictionary = (live_instances[mid] as Dictionary).get("desc", {}) as Dictionary
			if str(desc.get("source_resource_path", "")) == path:
				matches.append({"memory_id": mid, "title": str(desc.get("title", "Instance")), "primary_class": str(desc.get("primary_class", "Graph"))})
	return matches


func find_live_memory_id_for_resource(path: String) -> int:
	var matches: Array[Dictionary] = find_live_instances_for_resource(path)
	return 0 if matches.is_empty() else int(matches[0]["memory_id"])


func select_live_instance(memory_id: int) -> bool:
	if not live_instances.has(memory_id):
		return false
	active_mode = MODE_LIVE
	active_key = str(memory_id)
	scrub_index = -1
	return true


func sync_active_resource_mutation() -> void:
	if is_resource_selected():
		var rec: Dictionary = resource_sessions[active_key] as Dictionary
		var res: Resource = rec.get("resource", null) as Resource
		var g: MermaidGraphModel = rec.get("graph", null) as MermaidGraphModel
		if res != null and g != null:
			MermaidResourceBridge.write_ir(res, g)
			rec["dirty"] = true


func save_or_export_active(target_path: String = "") -> Dictionary:
	if is_resource_selected():
		var save_res: Dictionary = SessionDiskWatcher.save_resource_session(active_key, target_path, resource_sessions, resource_key_list)
		active_key = str(save_res.get("new_key", active_key))
		return save_res
	var exp_res: Dictionary = MermaidResourceBridge.export_new_resource(get_active_graph(), target_path)
	if bool(exp_res.get("ok", false)) and exp_res.get("resource", null) is Resource:
		open_resource_session(exp_res["resource"] as Resource)
	return exp_res

#endregion


#region 源码同步、排版与运行期多实例归档

func apply_draft_source(source: String) -> Dictionary:
	return apply_source_to_active(source, true)


func apply_source_to_active(source: String, force_draft: bool = false) -> Dictionary:
	if force_draft:
		select_draft()
	elif not is_editable_mode():
		return {"ok": false, "error": FlowEditorI18n.t(&"session.err_readonly")}
	var parsed: Dictionary = SessionSourceApplier.parse_and_build(source, get_active_graph())
	if not bool(parsed.get("ok", false)):
		return parsed
	if is_resource_selected():
		var rec: Dictionary = resource_sessions[active_key] as Dictionary
		rec["graph"] = parsed["graph"]
		rec["plan"] = parsed["plan"]
		sync_active_resource_mutation()
	else:
		draft_graph = parsed["graph"] as MermaidGraphModel
		draft_plan = parsed["plan"] as Dictionary
	return {"ok": true, "error": ""}


func relayout_active(toggle_direction: bool = false) -> void:
	var g: MermaidGraphModel = get_active_graph()
	if g == null:
		return
	if toggle_direction:
		g.direction = &"TD" if (g.direction == &"LR" or g.direction == &"RL") else &"LR"
	if g.nodes.is_empty():
		return
	var new_plan: Dictionary = MermaidLayout.apply_layout(g, true)
	if is_live_selected() or is_snapshot_selected() or is_resource_selected():
		get_active_record()["plan"] = new_plan
		if is_resource_selected():
			sync_active_resource_mutation()
	else:
		draft_plan = new_plan


func refresh_editable_topology_plan() -> void:
	var g: MermaidGraphModel = get_active_graph()
	if g == null:
		return
	var next_plan: Dictionary = MermaidLayout.analyze_topology(g)
	if is_resource_selected():
		(resource_sessions[active_key] as Dictionary)["plan"] = next_plan
		sync_active_resource_mutation()
	elif active_mode == MODE_DRAFT:
		draft_plan = next_plan


func archive_live_sessions_to_snapshots() -> void:
	var was_live_mid: int = get_selected_live_memory_id()
	var fallback_snap_key: String = ""
	var used_keys_in_pass: Dictionary = {}
	for mid: int in instance_id_list:
		if live_instances.has(mid):
			var s_key: String = SessionLiveTracker.store_snapshot(
				mid,
				live_instances[mid] as Dictionary,
				snapshots,
				snapshot_key_list,
				ring_buffer,
				breakpoints_by_key,
				used_keys_in_pass
			)
			if mid == was_live_mid:
				fallback_snap_key = s_key
	live_instances.clear()
	instance_id_list.clear()
	_auto_switched_this_run = false
	scrub_index = -1
	if was_live_mid != 0 and not fallback_snap_key.is_empty() and snapshots.has(fallback_snap_key):
		active_mode = MODE_SNAPSHOT
		active_key = fallback_snap_key


func register_live_instance(memory_id: int, descriptor: Dictionary, topology: Dictionary, frame: Dictionary) -> bool:
	var snap_key: String = SessionLiveTracker.make_snapshot_key(descriptor)
	var was_watching_same_snapshot: bool = (active_mode == MODE_SNAPSHOT and active_key == snap_key)
	SessionLiveTracker.register_instance(
		memory_id,
		descriptor,
		topology,
		frame,
		live_instances,
		instance_id_list,
		snapshots,
		snapshot_key_list,
		ring_buffer,
		breakpoints_by_key
	)
	if was_watching_same_snapshot or not _auto_switched_this_run:
		_auto_switched_this_run = true
		active_mode = MODE_LIVE
		active_key = str(memory_id)
		scrub_index = -1
		return true
	return false


func unregister_live_instance(memory_id: int) -> bool:
	var archived_snap_key: String = (
		SessionLiveTracker.store_snapshot(
			memory_id,
			live_instances[memory_id] as Dictionary,
			snapshots,
			snapshot_key_list,
			ring_buffer,
			breakpoints_by_key
		)
		if live_instances.has(memory_id)
		else ""
	)
	live_instances.erase(memory_id)
	instance_id_list.erase(memory_id)
	if active_mode == MODE_LIVE and active_key == str(memory_id):
		scrub_index = -1
		if not instance_id_list.is_empty():
			active_mode = MODE_LIVE
			active_key = str(instance_id_list[0])
		elif not archived_snap_key.is_empty() and snapshots.has(archived_snap_key):
			active_mode = MODE_SNAPSHOT
			active_key = archived_snap_key
		else:
			select_draft()
		return true
	return false


func update_live_topology(memory_id: int, topology: Dictionary) -> bool:
	return SessionLiveTracker.update_topology(memory_id, topology, live_instances) and is_live_selected() and int(active_key) == memory_id


func update_live_frame(memory_id: int, frame: Dictionary) -> bool:
	return SessionLiveTracker.update_frame(memory_id, frame, live_instances, ring_buffer, breakpoints_by_key) and is_live_selected() and int(active_key) == memory_id

#endregion
