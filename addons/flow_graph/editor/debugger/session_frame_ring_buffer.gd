@tool
extends RefCounted

## 会话 60 帧环形历史遥测缓冲（60-Frame Telemetry Ring Buffer）。[br]
##
## 按 `session_id` 独立维护最近 [constant MAX_FRAMES] 帧实质状态变化快照（对静止待机重复帧按 `active_nodes + vars` 签名去重），并支持停止运行时通过 [method copy_history] 无损继承至离线快照会话供时间轴倒带回放。

const MAX_FRAMES: int = 60

## `{String (session_id): {"frames": Array[Dictionary], "last_sig": String, "next_seq": int}}`
var _buffers: Dictionary = {}


#region 帧记录、读取与归档迁移接口

func record_frame(session_id: String, frame: Dictionary, force: bool = false) -> void:
	var clean_id: String = session_id.strip_edges()
	if clean_id.is_empty() or frame.is_empty():
		return

	var bucket: Dictionary = _ensure_bucket(clean_id)
	var frames_arr: Array[Dictionary] = bucket["frames"] as Array[Dictionary]
	var sig: String = _compute_frame_signature(frame)

	if not force and not frames_arr.is_empty() and str(bucket.get("last_sig", "")) == sig:
		return

	var seq_num: int = int(bucket.get("next_seq", 1))
	bucket["next_seq"] = seq_num + 1
	bucket["last_sig"] = sig

	var snap: Dictionary = frame.duplicate(true)
	snap["seq"] = seq_num
	snap["timestamp_msec"] = Time.get_ticks_msec()
	frames_arr.append(snap)

	while frames_arr.size() > MAX_FRAMES:
		frames_arr.pop_front()


func get_frame_count(session_id: String) -> int:
	if not _buffers.has(session_id):
		return 0
	var frames_arr: Array[Dictionary] = (_buffers[session_id] as Dictionary)["frames"] as Array[Dictionary]
	return frames_arr.size()


func get_frame_at(session_id: String, index: int) -> Dictionary:
	if not _buffers.has(session_id):
		return {}
	var frames_arr: Array[Dictionary] = (_buffers[session_id] as Dictionary)["frames"] as Array[Dictionary]
	if index < 0 or index >= frames_arr.size():
		return {}
	return (frames_arr[index] as Dictionary).duplicate(true)


func copy_history(from_key: String, to_snap_key: String) -> void:
	if from_key.is_empty() or to_snap_key.is_empty() or not _buffers.has(from_key):
		return
	var src_bucket: Dictionary = _buffers[from_key] as Dictionary
	var src_frames: Array[Dictionary] = src_bucket["frames"] as Array[Dictionary]
	var dst_frames: Array[Dictionary] = []
	for item: Dictionary in src_frames:
		var cloned: Dictionary = item.duplicate(true)
		cloned["paused"] = false
		dst_frames.append(cloned)
	_buffers[to_snap_key] = {
		"frames": dst_frames,
		"last_sig": str(src_bucket.get("last_sig", "")),
		"next_seq": int(src_bucket.get("next_seq", dst_frames.size() + 1)),
	}


func clear_session(session_id: String) -> void:
	_buffers.erase(session_id)


func clear_all() -> void:
	_buffers.clear()

#endregion


#region 内部桶初始化与签名计算

func _ensure_bucket(session_id: String) -> Dictionary:
	if not _buffers.has(session_id):
		var empty_frames: Array[Dictionary] = []
		_buffers[session_id] = {
			"frames": empty_frames,
			"last_sig": "",
			"next_seq": 1,
		}
	return _buffers[session_id] as Dictionary


static func _compute_frame_signature(frame: Dictionary) -> String:
	return JSON.stringify({
		"active_nodes": frame.get("active_nodes", {}),
		"vars": frame.get("vars", {}),
		"hit_bp": str(frame.get("hit_breakpoint", "")),
	})

#endregion
