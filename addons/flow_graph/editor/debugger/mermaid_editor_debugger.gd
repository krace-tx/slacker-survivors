@tool
extends EditorDebuggerPlugin

## FlowGraph 跨进程调试器插件（Editor-Side IPC Receiver & Command Sender）。[br]
##
## [b]核心职责：[/b][br]
## 1. 捕获来自独立游戏进程的 `flow_graph:*` 消息（按继承基类与内存 `instance_id` 注册、状态快照、实时流转动画）；[br]
## 2. 维护多会话活跃集 `_active_sessions`，防止快速重启游戏（`F5`/`F6`）时旧会话延迟 `stopped` 信号误清空新会话；[br]
## 3. 向当前主调试会话发送交互式控制与蓝图热重载指令。


#region 信号定义

signal session_active_changed(is_active: bool)
signal instance_registered(memory_id: int, descriptor: Dictionary, topology: Dictionary, frame: Dictionary)
signal instance_unregistered(memory_id: int)
signal topology_received(memory_id: int, topology: Dictionary)
signal frame_received(memory_id: int, frame: Dictionary)
signal edge_flow_received(memory_id: int, from_id: String, to_id: String, label: String)

#endregion


#region 会话状态

var _active_session_id: int = -1
var _active_sessions: Dictionary = {} ## {int (session_id): bool}

#endregion


#region EditorDebuggerPlugin 重写钩子

func _setup_session(session_id: int) -> void:
	var session: EditorDebuggerSession = get_session(session_id)
	if session == null:
		return
	session.started.connect(func() -> void: _on_session_started(session_id))
	session.stopped.connect(func() -> void: _on_session_stopped(session_id))


func _on_session_started(session_id: int) -> void:
	var was_running: bool = _active_session_id >= 0
	_active_sessions[session_id] = true
	_active_session_id = session_id
	if not was_running:
		session_active_changed.emit(true)
	request_sync_all()


func _on_session_stopped(session_id: int) -> void:
	_active_sessions.erase(session_id)
	if _active_session_id != session_id:
		return

	# 若存在多开调试窗口，平滑切向仍在运行的另一个会话；仅当全部会话结束时才触发归档快照
	var fallback_id: int = -1
	for k: Variant in _active_sessions.keys():
		var cand_id: int = int(k)
		var cand_sess: EditorDebuggerSession = get_session(cand_id)
		if cand_sess != null and cand_sess.is_active():
			fallback_id = cand_id
			break
	_active_session_id = fallback_id
	if _active_session_id >= 0:
		request_sync_all()
	else:
		session_active_changed.emit(false)


func _has_capture(capture: String) -> bool:
	return capture == FlowGraphContracts.IPC_CAPTURE_PREFIX


func _capture(message: String, data: Array, session_id: int) -> bool:
	if _active_session_id < 0 and session_id >= 0:
		_active_sessions[session_id] = true
		_active_session_id = session_id
		session_active_changed.emit(true)
	elif _active_session_id >= 0 and session_id != _active_session_id:
		return true

	match message:
		FlowGraphContracts.IPC_MSG_REGISTER:
			if data.size() >= 3 and data[0] is Dictionary and data[1] is Dictionary and data[2] is Dictionary:
				var desc: Dictionary = data[0] as Dictionary
				var topo: Dictionary = data[1] as Dictionary
				var frame: Dictionary = data[2] as Dictionary
				var mid: int = int(desc.get("memory_id", 0))
				instance_registered.emit(mid, desc, topo, frame)
			return true
		FlowGraphContracts.IPC_MSG_UNREGISTER:
			if not data.is_empty():
				instance_unregistered.emit(int(data[0]))
			return true
		FlowGraphContracts.IPC_MSG_TOPOLOGY:
			if data.size() >= 2 and data[1] is Dictionary:
				topology_received.emit(int(data[0]), data[1] as Dictionary)
			return true
		FlowGraphContracts.IPC_MSG_FRAME:
			if data.size() >= 2 and data[1] is Dictionary:
				frame_received.emit(int(data[0]), data[1] as Dictionary)
			return true
		FlowGraphContracts.IPC_MSG_EDGE_FLOW:
			if data.size() >= 3:
				var lbl: String = str(data[3]) if data.size() >= 4 else ""
				edge_flow_received.emit(int(data[0]), str(data[1]), str(data[2]), lbl)
			return true
	return false

#endregion


#region 下行命令发送接口

func is_game_running() -> bool:
	if _active_session_id < 0:
		return false
	var session: EditorDebuggerSession = get_session(_active_session_id)
	return session != null and session.is_active()


func request_sync_all() -> void:
	_send_raw(FlowGraphContracts.IPC_SEND_SYNC_ALL, [])


func set_game_window_topmost(enabled: bool) -> void:
	_send_raw(FlowGraphContracts.IPC_SEND_WINDOW_TOPMOST, [enabled])


func send_instance_command(memory_id: int, command: StringName, payload: Dictionary = {}) -> void:
	if memory_id == 0:
		return
	_send_raw(FlowGraphContracts.IPC_SEND_CMD, [memory_id, String(command), payload])


func send_hot_reload_resource(resource_path: String, ir_dict: Dictionary) -> void:
	var clean_path: String = resource_path.strip_edges()
	if clean_path.is_empty():
		return
	_send_raw(FlowGraphContracts.IPC_SEND_HOT_RELOAD, [clean_path, ir_dict])


func _send_raw(msg: String, payload: Array) -> void:
	if _active_session_id < 0:
		return
	var session: EditorDebuggerSession = get_session(_active_session_id)
	if session != null and session.is_active():
		session.send_message(msg, payload)

#endregion
