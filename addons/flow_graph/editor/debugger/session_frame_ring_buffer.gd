@tool
extends RefCounted

## 会话 60 帧环形历史遥测缓冲（60-Frame Telemetry Ring Buffer）。[br]
##
## [b]核心设计：[/b][br]
## 1. 按 `session_id` 独立维护最近 [constant MAX_FRAMES] 帧**实质状态变化**快照；[br]
## 2. 计算结构化签名时自动剥离 `state_time` / `tick_count` / `elapsed_time` 与计时器徽章等纯时间递增噪音：待机静止帧原地刷新尾帧读数而不挤占历史槽位，确保 60 帧滑块真正记录最近 60 次状态跃迁或黑板突变；[br]
## 3. 支持停止运行时通过 [method copy_history] 无损继承至离线快照会话供时间轴倒带回放。

const MAX_FRAMES: int = 60

## 签名去重时忽略的纯时间/帧计数噪音键（避免静止待机时冲刷掉前序真实状态跳变历史）
const _VOLATILE_VAR_KEYS: Dictionary = {
	"state_time": true,
	"tick_count": true,
	"elapsed_time": true,
}

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
	var now_msec: int = Time.get_ticks_msec()

	if not force and not frames_arr.is_empty() and str(bucket.get("last_sig", "")) == sig:
		# 拓扑激活态与黑板实质变量均未变化：原地刷新尾帧的计时器读数，不挤占 60 帧历史槽位
		var tail: Dictionary = frames_arr[frames_arr.size() - 1]
		var prev_seq: int = int(tail.get("seq", 1))
		var updated_tail: Dictionary = frame.duplicate(true)
		updated_tail["seq"] = prev_seq
		updated_tail["timestamp_msec"] = now_msec
		frames_arr[frames_arr.size() - 1] = updated_tail
		return

	var seq_num: int = int(bucket.get("next_seq", 1))
	bucket["next_seq"] = seq_num + 1
	bucket["last_sig"] = sig

	var snap: Dictionary = frame.duplicate(true)
	snap["seq"] = seq_num
	snap["timestamp_msec"] = now_msec
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


#region 内部桶初始化与确定性轻量签名计算

func _ensure_bucket(session_id: String) -> Dictionary:
	if not _buffers.has(session_id):
		var empty_frames: Array[Dictionary] = []
		_buffers[session_id] = {
			"frames": empty_frames,
			"last_sig": "",
			"next_seq": 1,
		}
	return _buffers[session_id] as Dictionary


## 生成忽略纯计时器噪音的确定性帧签名（零 `JSON.stringify` 类型丢失与大对象分配）。
static func _compute_frame_signature(frame: Dictionary) -> String:
	var parts := PackedStringArray()

	var raw_nodes: Variant = frame.get("active_nodes", {})
	if raw_nodes is Dictionary:
		var nodes_dict: Dictionary = raw_nodes as Dictionary
		if not nodes_dict.is_empty():
			var nkeys := PackedStringArray()
			for nk: Variant in nodes_dict.keys():
				nkeys.append(str(nk))
			nkeys.sort()
			for nk_str: String in nkeys:
				var nv: Variant = nodes_dict.get(nk_str, null)
				var nstate: String = str((nv as Dictionary).get("state", "")) if nv is Dictionary else str(nv)
				parts.append("%s:%s" % [nk_str, nstate])

	parts.append("#")

	var raw_vars: Variant = frame.get("vars", {})
	if raw_vars is Dictionary:
		var vars_dict: Dictionary = raw_vars as Dictionary
		if not vars_dict.is_empty():
			var vkeys := PackedStringArray()
			for vk: Variant in vars_dict.keys():
				var vk_str: String = str(vk)
				if not _VOLATILE_VAR_KEYS.has(vk_str):
					vkeys.append(vk_str)
			vkeys.sort()
			for vk_str: String in vkeys:
				parts.append("%s=%s" % [vk_str, _format_sig_value(vars_dict.get(vk_str, null))])

	parts.append("#bp=" + str(frame.get("hit_breakpoint", "")))
	return "|".join(parts)


static func _format_sig_value(val: Variant) -> String:
	match typeof(val):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "1" if bool(val) else "0"
		TYPE_INT:
			return "i:%d" % int(val)
		TYPE_FLOAT:
			return "f:%.4f" % snappedf(float(val), 0.0001)
		TYPE_STRING, TYPE_STRING_NAME:
			return "s:%s" % str(val)
		TYPE_ARRAY:
			var arr: Array = val as Array
			var sub := PackedStringArray()
			for item: Variant in arr:
				sub.append(_format_sig_value(item))
			return "[%s]" % ",".join(sub)
		TYPE_DICTIONARY:
			var d: Dictionary = val as Dictionary
			var dkeys := PackedStringArray()
			for k: Variant in d.keys():
				dkeys.append(str(k))
			dkeys.sort()
			var dsub := PackedStringArray()
			for ks: String in dkeys:
				dsub.append("%s:%s" % [ks, _format_sig_value(d.get(ks, null))])
			return "{%s}" % ",".join(dsub)
		_:
			return "%d:%s" % [typeof(val), str(val)]

#endregion
