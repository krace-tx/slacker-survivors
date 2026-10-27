@tool
extends RefCounted

## 多会话图拓扑撤销与重做历史栈（Multi-Session Graph Undo / Redo Stack）。[br]
##
## 按 `session_key` 物理隔离各 `.tres` 资源或草稿会话的编辑历史，基于快照 JSON 签名自动消除连续重复帧，单会话步数上限为 [constant MAX_STEPS]。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)

const MAX_STEPS: int = 64

## `{String (session_key): {"undo": Array[Dictionary], "redo": Array[Dictionary]}}`
var _sessions: Dictionary = {}


#region 核心快照撤销与重做接口

func push_snapshot(session_key: String, snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var rec: Dictionary = _ensure_session(session_key)
	var undo_arr: Array[Dictionary] = rec["undo"] as Array[Dictionary]
	var redo_arr: Array[Dictionary] = rec["redo"] as Array[Dictionary]
	redo_arr.clear()

	var sig: String = JSON.stringify(snapshot)
	if not undo_arr.is_empty():
		var top_entry: Dictionary = undo_arr[undo_arr.size() - 1]
		if str(top_entry.get("sig", "")) == sig:
			return

	undo_arr.append({
		"sig": sig,
		"snap": snapshot.duplicate(true),
	})
	while undo_arr.size() > MAX_STEPS:
		undo_arr.pop_front()


func can_undo(session_key: String) -> bool:
	if not _sessions.has(session_key):
		return false
	var undo_arr: Array[Dictionary] = (_sessions[session_key] as Dictionary)["undo"] as Array[Dictionary]
	return not undo_arr.is_empty()


func can_redo(session_key: String) -> bool:
	if not _sessions.has(session_key):
		return false
	var redo_arr: Array[Dictionary] = (_sessions[session_key] as Dictionary)["redo"] as Array[Dictionary]
	return not redo_arr.is_empty()


func undo(session_key: String, current_snapshot: Dictionary) -> Dictionary:
	if not can_undo(session_key):
		return {}
	var rec: Dictionary = _sessions[session_key] as Dictionary
	var undo_arr: Array[Dictionary] = rec["undo"] as Array[Dictionary]
	var redo_arr: Array[Dictionary] = rec["redo"] as Array[Dictionary]

	var cur_sig: String = JSON.stringify(current_snapshot)
	if undo_arr.size() >= 2 and str(undo_arr[undo_arr.size() - 1].get("sig", "")) == cur_sig:
		undo_arr.pop_back()

	if not current_snapshot.is_empty():
		redo_arr.append({
			"sig": cur_sig,
			"snap": current_snapshot.duplicate(true),
		})
		while redo_arr.size() > MAX_STEPS:
			redo_arr.pop_front()

	var prev_entry: Dictionary = undo_arr.pop_back() as Dictionary
	return (prev_entry["snap"] as Dictionary).duplicate(true)


func redo(session_key: String, current_snapshot: Dictionary) -> Dictionary:
	if not can_redo(session_key):
		return {}
	var rec: Dictionary = _sessions[session_key] as Dictionary
	var undo_arr: Array[Dictionary] = rec["undo"] as Array[Dictionary]
	var redo_arr: Array[Dictionary] = rec["redo"] as Array[Dictionary]

	if not current_snapshot.is_empty():
		var cur_sig: String = JSON.stringify(current_snapshot)
		undo_arr.append({
			"sig": cur_sig,
			"snap": current_snapshot.duplicate(true),
		})
		while undo_arr.size() > MAX_STEPS:
			undo_arr.pop_front()

	var next_entry: Dictionary = redo_arr.pop_back() as Dictionary
	return (next_entry["snap"] as Dictionary).duplicate(true)


func clear_session(session_key: String) -> void:
	_sessions.erase(session_key)


func clear_all() -> void:
	_sessions.clear()

#endregion


#region 模型便捷包装接口

func record_before_edit(session_key: String, graph: MermaidGraphModel) -> void:
	if graph != null:
		push_snapshot(session_key, graph.to_snapshot_dict())


func undo_graph(session_key: String, graph: MermaidGraphModel) -> bool:
	if graph == null or not can_undo(session_key):
		return false
	var prev_snap: Dictionary = undo(session_key, graph.to_snapshot_dict())
	if prev_snap.is_empty():
		return false
	graph.restore_snapshot_dict(prev_snap)
	return true


func redo_graph(session_key: String, graph: MermaidGraphModel) -> bool:
	if graph == null or not can_redo(session_key):
		return false
	var next_snap: Dictionary = redo(session_key, graph.to_snapshot_dict())
	if next_snap.is_empty():
		return false
	graph.restore_snapshot_dict(next_snap)
	return true


func _ensure_session(session_key: String) -> Dictionary:
	if not _sessions.has(session_key):
		var empty_undo: Array[Dictionary] = []
		var empty_redo: Array[Dictionary] = []
		_sessions[session_key] = {
			"undo": empty_undo,
			"redo": empty_redo,
		}
	return _sessions[session_key] as Dictionary

#endregion
