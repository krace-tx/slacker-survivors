@tool
extends RefCounted

## 资源会话磁盘加载、持久化与外部冲突监控器（Session Disk Watcher & IO Helper）。[br]
##
## 负责 `.tres` 会话记录构造、保存印章更新以及磁盘 `mtime` + `MD5` 变更比对，区分「干净会话无感自动重载」与「未保存脏会话冲突拦截」。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)
const MermaidResourceBridge = preload(FlowGraphContracts.SCRIPT_RESOURCE_BRIDGE)


#region 磁盘元数据与会话记录构造

static func query_disk_mtime(path: String) -> int:
	if path.begins_with("res://") and FileAccess.file_exists(path):
		return int(FileAccess.get_modified_time(path))
	return 0

static func query_disk_md5(path: String) -> String:
	if path.begins_with("res://") and FileAccess.file_exists(path):
		return FileAccess.get_md5(path)
	return ""

static func stamp_record(rec: Dictionary, path: String) -> void:
	rec["disk_mtime"] = query_disk_mtime(path)
	rec["disk_md5"] = query_disk_md5(path)

static func build_session_record(rkey: String, res: Resource, rpath: String) -> Dictionary:
	var g := MermaidGraphModel.new()
	g.load_from_topology_dict(MermaidResourceBridge.read_ir(res))
	g.schema_locked = true
	var rec: Dictionary = {
		"key": rkey, "resource": res, "path": rpath, "graph": g,
		"plan": MermaidLayout.apply_layout(g, false), "dirty": false, "external_conflict": false,
	}
	stamp_record(rec, rpath)
	return rec

static func save_resource_session(
	active_key: String,
	target_path: String,
	resource_sessions: Dictionary,
	resource_key_list: Array[String]
) -> Dictionary:
	var rec: Dictionary = resource_sessions[active_key] as Dictionary
	var res: Resource = rec.get("resource", null) as Resource
	var g: MermaidGraphModel = rec.get("graph", null) as MermaidGraphModel
	if res == null or g == null:
		return {"ok": false, "path": "", "new_key": active_key, "error": FlowEditorI18n.t(&"session.err_invalid")}
	MermaidResourceBridge.write_ir(res, g)
	var save_res: Dictionary = MermaidResourceBridge.save_resource(res, target_path)
	var next_key: String = active_key
	if bool(save_res.get("ok", false)):
		var saved_path: String = str(save_res.get("path", ""))
		rec["dirty"] = false
		rec["external_conflict"] = false
		rec["path"] = saved_path
		stamp_record(rec, saved_path)
		if saved_path != active_key and not saved_path.is_empty():
			rec["key"] = saved_path
			resource_sessions.erase(active_key)
			resource_sessions[saved_path] = rec
			var k_idx: int = resource_key_list.find(active_key)
			if k_idx >= 0:
				resource_key_list[k_idx] = saved_path
			else:
				resource_key_list.append(saved_path)
			next_key = saved_path
	save_res["new_key"] = next_key
	return save_res

#endregion


#region 外部变更比对与冲突管理

static func dismiss_conflict(resource_sessions: Dictionary, path: String) -> void:
	if resource_sessions.has(path):
		var rec: Dictionary = resource_sessions[path] as Dictionary
		rec["external_conflict"] = false
		stamp_record(rec, path)

static func check_external_changes(
	resource_sessions: Dictionary,
	resource_key_list: Array[String],
	reload_cb: Callable,
	force_content_check: bool = false
) -> Dictionary:
	var reloaded: Array[String] = []
	var conflicts: Array[String] = []
	for rkey: String in resource_key_list.duplicate():
		if not resource_sessions.has(rkey):
			continue
		var rec: Dictionary = resource_sessions[rkey] as Dictionary
		var rpath: String = str(rec.get("path", ""))
		if not rpath.begins_with("res://"):
			continue
		if not FileAccess.file_exists(rpath):
			if int(rec.get("disk_mtime", 0)) > 0:
				rec["disk_mtime"] = 0
				rec["disk_md5"] = ""
				rec["dirty"] = true
				conflicts.append(rpath)
			continue
		var cur_mtime: int = query_disk_mtime(rpath)
		if not force_content_check and cur_mtime == int(rec.get("disk_mtime", 0)):
			continue
		var cur_md5: String = query_disk_md5(rpath)
		if cur_md5.is_empty():
			continue
		if cur_md5 == str(rec.get("disk_md5", "")):
			rec["disk_mtime"] = cur_mtime
			continue
		if not bool(rec.get("dirty", false)):
			if reload_cb.is_valid():
				var r_res: Dictionary = reload_cb.call(rpath) as Dictionary
				if bool(r_res.get("ok", false)):
					reloaded.append(rpath)
		else:
			rec["disk_mtime"] = cur_mtime
			rec["disk_md5"] = cur_md5
			if not bool(rec.get("external_conflict", false)):
				rec["external_conflict"] = true
				conflicts.append(rpath)
	return {"reloaded": reloaded, "conflicts": conflicts}

#endregion
