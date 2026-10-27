class_name GraphDebugBridge
extends RefCounted

## 全局算法图可视化桥接与双向遥测总线（Graph Debug Runtime Bridge）。[br]
##
## [b]核心设计：[/b][br]
## 1. 仅使用 Godot 原生 `EngineDebugger` IPC 协议通信，对任何编辑器插件保持 **零反向编译依赖**；[br]
## 2. 精准维护全局静态 `_paused_count`（覆盖命令暂停、单步与节点断点自动暂停），确保零暂停时 O(1) 布尔短路；[br]
## 3. 支持 `hot_reload_resource` 下行热更新（对共享享元 `BTTree` 自动按 `secondary_id` 去重仅编译一次）。

#region 常量与静态注册表
const CAPTURE_PREFIX: String = "flow_graph"
const DEFAULT_SYNC_INTERVAL_SEC: float = 0.06

static var _bindings: Dictionary = {} ## {int (memory_id): GraphDebugBinding}
static var _last_sync_msec: Dictionary = {} ## {int (memory_id): int}
static var _capture_registered: bool = false
static var _paused_count: int = 0
static var _headless_test_mode: bool = false
#endregion


#region 公开注册与生命周期 API
## 判断当前是否处于激活的远程调试器连接环境（Release 导出包恒为 `false`）。
static func is_debugger_connected() -> bool:
	return OS.is_debug_build() and EngineDebugger.is_active()


static func _is_session_enabled() -> bool:
	return _headless_test_mode or is_debugger_connected()


## 供无头自动化测试开启本地调试会话模拟（无需远程 `EngineDebugger` 连接即可测试断点挂起与热更）。
static func set_headless_test_mode(enabled: bool) -> void:
	_headless_test_mode = enabled
	if not enabled:
		_bindings.clear()
		_last_sync_msec.clear()
		_paused_count = 0


static func get_paused_count() -> int:
	return _paused_count


static func get_binding(memory_id: int) -> GraphDebugBinding:
	return _bindings.get(memory_id, null) as GraphDebugBinding


## 在 Debug / Editor 构建下自动捕获外部业务调用方的脚本路径与行号（Release 构建零开销直接返回空字典）。
static func capture_caller_source() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var stack: Array = get_stack()
	for frame_var: Variant in stack:
		if not (frame_var is Dictionary):
			continue
		var frame: Dictionary = frame_var as Dictionary
		var src: String = str(frame.get("source", ""))
		if src.is_empty() or src.begins_with("res://addons/flow_graph/"):
			continue
		return {
			"file": src,
			"line": int(frame.get("line", 1)),
			"function": str(frame.get("function", "")),
		}
	return {}


## 注册任意内置或继承自 `BaseDebuggableGraph` 的图实例（如 `StateMachine`），返回其内存 ID。
static func register(target: Object, owner: Object = null, title: String = "") -> int:
	if not _is_session_enabled() or not is_instance_valid(target):
		return 0
	_ensure_initialized()

	var binding := GraphDebugBinding.new()
	binding.setup_standard(
		target,
		owner,
		title,
		Callable(GraphDebugBridge, "_on_binding_edge_flow"),
		Callable(GraphDebugBridge, "_on_binding_topology_dirty")
	)
	_replace_existing_binding(binding.memory_id)
	_bindings[binding.memory_id] = binding
	_send_instance_registered(binding)
	return binding.memory_id


## 注册享元行为树与单实体运行上下文（以 `BTContext` 内存 ID 区分同屏多实体，同时关联共享 `BTTree` 内存 ID）。
static func register_bt(tree: BTTree, ctx: BTContext, owner: Object = null, title: String = "") -> int:
	if not _is_session_enabled() or tree == null or ctx == null:
		return 0
	_ensure_initialized()

	var binding := GraphDebugBinding.new()
	binding.setup_bt(
		tree,
		ctx,
		owner,
		title,
		Callable(GraphDebugBridge, "_on_binding_edge_flow"),
		Callable(GraphDebugBridge, "_on_binding_topology_dirty")
	)
	_replace_existing_binding(binding.memory_id)
	_bindings[binding.memory_id] = binding
	_send_instance_registered(binding)
	return binding.memory_id


## 通过方法闭包与可选 `Signal` 零侵入绑定任意自定义复杂算法实例。
static func register_custom(
	target: Object,
	owner: Object,
	title: String,
	export_cb: Callable,
	capture_cb: Callable,
	command_cb: Callable = Callable(),
	flow_signal: Signal = Signal()
) -> int:
	if not _is_session_enabled() or not is_instance_valid(target):
		return 0
	_ensure_initialized()

	var binding := GraphDebugBinding.new()
	binding.setup_custom(
		target,
		owner,
		title,
		export_cb,
		capture_cb,
		command_cb,
		flow_signal,
		Callable(GraphDebugBridge, "_on_binding_edge_flow"),
		Callable(GraphDebugBridge, "_on_binding_topology_dirty")
	)
	_replace_existing_binding(binding.memory_id)
	_bindings[binding.memory_id] = binding
	_send_instance_registered(binding)
	return binding.memory_id


static func _replace_existing_binding(memory_id: int) -> void:
	if _bindings.has(memory_id):
		var old_b: GraphDebugBinding = _bindings[memory_id] as GraphDebugBinding
		if old_b != null and old_b.is_paused:
			_paused_count = maxi(0, _paused_count - 1)


## 注销指定内存 ID 的调试实例。
static func unregister(memory_id: int) -> void:
	if memory_id == 0 or not _bindings.has(memory_id):
		return
	var b: GraphDebugBinding = _bindings[memory_id] as GraphDebugBinding
	if b != null and b.is_paused:
		_paused_count = maxi(0, _paused_count - 1)
	_bindings.erase(memory_id)
	_last_sync_msec.erase(memory_id)
	if is_debugger_connected():
		EngineDebugger.send_message("flow_graph:unregister", [memory_id])
#endregion


#region 暂停计数同步、帧遥测推送与单步挂起门禁
## 由 `GraphDebugBinding` 在暂停状态变化时统一回调，精准维护 `_paused_count`。
static func notify_binding_paused_changed(was_paused: bool, now_paused: bool) -> void:
	if was_paused == now_paused:
		return
	if now_paused:
		_paused_count += 1
	else:
		_paused_count = maxi(0, _paused_count - 1)


## 断点命中自动暂停时的语义通知入口。
static func notify_binding_paused_from_breakpoint() -> void:
	notify_binding_paused_changed(false, true)


## 供算法主循环调用：检查该内存 ID 是否被编辑器单步或断点暂停。零暂停实例时 O(1) 布尔短路。
static func should_suspend_tick(memory_id: int) -> bool:
	if _paused_count <= 0 or memory_id == 0:
		return false
	var b: GraphDebugBinding = _bindings.get(memory_id, null) as GraphDebugBinding
	return b.consume_suspend_gate() if b != null else false


## 节流推送指定内存 ID 的最新状态快照至编辑器画布（默认 60ms 分频防 IPC 拥塞；`force=true` 立即推送）。
static func push_frame(memory_id: int, force: bool = false) -> void:
	if not _is_session_enabled() or memory_id == 0 or not _bindings.has(memory_id):
		return
	var b: GraphDebugBinding = _bindings[memory_id] as GraphDebugBinding
	if b == null or not b.is_alive():
		unregister(memory_id)
		return

	# 若绑定配置了节点断点，确保每帧均采样以捕获瞬时断点命中，绝不因 60ms IPC 节流漏检
	var has_bps: bool = not b.breakpoint_nodes.is_empty()
	var now_ms: int = Time.get_ticks_msec()
	var prev_ms: int = int(_last_sync_msec.get(memory_id, 0))
	var throttled: bool = (not force) and (now_ms - prev_ms) < int(DEFAULT_SYNC_INTERVAL_SEC * 1000.0)
	if throttled and not has_bps:
		return

	var frame_dict: Dictionary = b.capture_frame_dict()
	var hit_just_now: bool = b.is_paused and not b.last_hit_breakpoint.is_empty()
	if throttled and not hit_just_now:
		return
	_last_sync_msec[memory_id] = now_ms

	if is_debugger_connected():
		if b.topology_dirty:
			EngineDebugger.send_message("flow_graph:topology", [memory_id, b.export_topology_dict()])
		EngineDebugger.send_message("flow_graph:frame", [memory_id, frame_dict])


## 主动上报一次有向边流转（驱动编辑器画布播放流光粒子脉冲）。
static func notify_edge_flow(memory_id: int, from_id: String, to_id: String, label: String = "") -> void:
	if not _is_session_enabled() or memory_id == 0:
		return
	if is_debugger_connected():
		EngineDebugger.send_message("flow_graph:edge_flow", [memory_id, from_id, to_id, label])
	push_frame(memory_id, true)


## 按磁盘资源路径热重载所有关联运行实例（共享享元 `BTTree` 按 `secondary_id` 去重仅重编译 1 次）。
static func hot_reload_by_resource_path(resource_path: String, ir_dict: Dictionary) -> int:
	if resource_path.is_empty():
		return 0
	var reloaded_trees: Dictionary = {}
	var updated_count: int = 0
	for k: Variant in _bindings.keys():
		var mid: int = int(k)
		var b: GraphDebugBinding = _bindings[mid] as GraphDebugBinding
		if b == null or not b.is_alive():
			continue
		if b.resolve_source_resource_path() != resource_path:
			continue

		var ok: bool = false
		if b.recognized_kind == GraphDebugBinding.KIND_BT and b.secondary_id != 0:
			if reloaded_trees.has(b.secondary_id):
				ok = bool(reloaded_trees[b.secondary_id])
				if ok:
					b.topology_dirty = true
			else:
				ok = b.hot_reload_ir(ir_dict)
				reloaded_trees[b.secondary_id] = ok
		else:
			ok = b.hot_reload_ir(ir_dict)

		if ok:
			updated_count += 1
			if is_debugger_connected():
				EngineDebugger.send_message("flow_graph:topology", [mid, b.export_topology_dict()])
				EngineDebugger.send_message("flow_graph:frame", [mid, b.capture_frame_dict()])
	return updated_count
#endregion


#region 内部 IPC 通道初始化与命令接收
static func _ensure_initialized() -> void:
	if _capture_registered or not is_debugger_connected():
		return
	_capture_registered = true
	OS.low_processor_usage_mode = false
	EngineDebugger.register_message_capture(CAPTURE_PREFIX, Callable(GraphDebugBridge, "_on_debugger_message"))


static func _send_instance_registered(binding: GraphDebugBinding) -> void:
	if not is_debugger_connected():
		return
	EngineDebugger.send_message("flow_graph:register", [
		binding.get_descriptor_dict(),
		binding.export_topology_dict(),
		binding.capture_frame_dict(),
	])


static func _on_binding_edge_flow(memory_id: int, from_id: String, to_id: String, label: String) -> void:
	notify_edge_flow(memory_id, from_id, to_id, label)


static func _on_binding_topology_dirty(memory_id: int) -> void:
	if not is_debugger_connected() or not _bindings.has(memory_id):
		return
	var b: GraphDebugBinding = _bindings[memory_id] as GraphDebugBinding
	if b != null and b.is_alive():
		EngineDebugger.send_message("flow_graph:topology", [memory_id, b.export_topology_dict()])


static func _on_debugger_message(message: String, data: Array) -> bool:
	if message == "sync_all":
		var stale_ids: Array[int] = []
		for k: Variant in _bindings.keys():
			var mid: int = int(k)
			var b: GraphDebugBinding = _bindings[mid] as GraphDebugBinding
			if b == null or not b.is_alive():
				stale_ids.append(mid)
			else:
				_send_instance_registered(b)
		for sid: int in stale_ids:
			unregister(sid)
		return true

	if message == "window_topmost":
		var enable_top: bool = bool(data[0]) if not data.is_empty() else false
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enable_top)
		return true

	if message == "cmd" and data.size() >= 3:
		var target_mid: int = int(data[0])
		var cmd_name := StringName(str(data[1]))
		var payload: Dictionary = data[2] as Dictionary if data[2] is Dictionary else {}
		var b: GraphDebugBinding = _bindings.get(target_mid, null) as GraphDebugBinding
		if b != null and b.is_alive():
			if b.execute_command(cmd_name, payload):
				push_frame(target_mid, true)
		return true

	if message == "hot_reload_resource" and data.size() >= 2:
		var res_path: String = str(data[0]).strip_edges()
		var ir_dict: Dictionary = data[1] as Dictionary if data[1] is Dictionary else {}
		hot_reload_by_resource_path(res_path, ir_dict)
		return true

	return false
#endregion
