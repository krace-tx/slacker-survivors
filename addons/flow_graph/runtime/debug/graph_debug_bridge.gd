class_name GraphDebugBridge
extends RefCounted

## 全局算法图可视化桥接与双向遥测总线（Graph Debug Runtime Bridge）。[br]
##
## [b]核心设计：[/b][br]
## 1. 仅使用 Godot 原生 `EngineDebugger` IPC 协议通信，对任何编辑器插件保持 **零反向编译依赖**；[br]
## 2. 精准维护全局静态 `_paused_count` 与周期性死实例清扫（GC Sweep），确保零暂停时 $O(1)$ 布尔短路且绝不悬空卡死；[br]
## 3. 节流窗口内通过 [method GraphDebugBinding.probe_breakpoints_fast] 执行零分配断点快筛，杜绝未命中帧的全量黑板深拷贝；[br]
## 4. 支持主图与嵌套公共子图 `hot_reload_resource` 下行热更新（对共享享元 [BTTree] 自动按 `secondary_id` 去重编译与导出拓扑）。


#region 协议常量与静态注册表

const CAPTURE_PREFIX: String = "flow_graph"
const DEFAULT_SYNC_INTERVAL_SEC: float = 0.06
const DEFAULT_SYNC_INTERVAL_MSEC: int = 60
const _DEAD_SWEEP_INTERVAL_MSEC: int = 2000

const MSG_REGISTER: String = "flow_graph:register"
const MSG_UNREGISTER: String = "flow_graph:unregister"
const MSG_TOPOLOGY: String = "flow_graph:topology"
const MSG_FRAME: String = "flow_graph:frame"
const MSG_EDGE_FLOW: String = "flow_graph:edge_flow"

const _INBOUND_SYNC_ALL: String = "sync_all"
const _INBOUND_WINDOW_TOPMOST: String = "window_topmost"
const _INBOUND_CMD: String = "cmd"
const _INBOUND_HOT_RELOAD: String = "hot_reload_resource"

static var _bindings: Dictionary = {}       ## {int (memory_id): GraphDebugBinding}
static var _last_sync_msec: Dictionary = {} ## {int (memory_id): int}
static var _capture_registered: bool = false
static var _paused_count: int = 0
static var _last_sweep_msec: int = 0
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
		clear_all()


## 销毁并清空所有已注册调试绑定（逐个调用 `dispose()` 断开信号，清零 `_paused_count`）。
static func clear_all() -> void:
	for k: Variant in _bindings.keys():
		var b: GraphDebugBinding = _bindings[k] as GraphDebugBinding
		if b != null:
			b.dispose()
	_bindings.clear()
	_last_sync_msec.clear()
	_paused_count = 0
	_last_sweep_msec = 0


static func get_paused_count() -> int:
	if _paused_count > 0:
		_prune_dead_bindings_now()
	return _paused_count


static func get_binding(memory_id: int) -> GraphDebugBinding:
	var b: GraphDebugBinding = _bindings.get(memory_id, null) as GraphDebugBinding
	if b != null and not b.is_alive():
		unregister(memory_id)
		return null
	return b


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


## 注册任意内置或继承自 [BaseDebuggableGraph] 的图实例（如 [StateMachine]），返回其内存 ID。
static func register(target: Object, owner: Object = null, title: String = "") -> int:
	if not _is_session_enabled() or not is_instance_valid(target):
		return 0
	_ensure_initialized()
	_sweep_dead_bindings_if_needed(Time.get_ticks_msec())

	var binding := GraphDebugBinding.new()
	binding.setup_standard(
		target,
		owner,
		title,
		Callable(GraphDebugBridge, "_on_binding_edge_flow"),
		Callable(GraphDebugBridge, "_on_binding_topology_dirty")
	)
	return _install_binding(binding)


## 注册享元行为树与单实体运行上下文（以 [BTContext] 内存 ID 区分同屏多实体，同时关联共享 [BTTree] 内存 ID）。
static func register_bt(tree: BTTree, ctx: BTContext, owner: Object = null, title: String = "") -> int:
	if not _is_session_enabled() or tree == null or ctx == null:
		return 0
	_ensure_initialized()
	_sweep_dead_bindings_if_needed(Time.get_ticks_msec())

	var binding := GraphDebugBinding.new()
	binding.setup_bt(
		tree,
		ctx,
		owner,
		title,
		Callable(GraphDebugBridge, "_on_binding_edge_flow"),
		Callable(GraphDebugBridge, "_on_binding_topology_dirty")
	)
	return _install_binding(binding)


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
	_sweep_dead_bindings_if_needed(Time.get_ticks_msec())

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
	return _install_binding(binding)


static func _install_binding(binding: GraphDebugBinding) -> int:
	_replace_existing_binding(binding.memory_id)
	_bindings[binding.memory_id] = binding
	_send_instance_registered(binding)
	return binding.memory_id


static func _replace_existing_binding(memory_id: int) -> void:
	if not _bindings.has(memory_id):
		return
	var old_b: GraphDebugBinding = _bindings[memory_id] as GraphDebugBinding
	if old_b != null:
		if old_b.is_paused:
			_paused_count = maxi(0, _paused_count - 1)
		old_b.dispose()
	_bindings.erase(memory_id)
	_last_sync_msec.erase(memory_id)


## 注销指定内存 ID 的调试实例并彻底断开信号连接。
static func unregister(memory_id: int) -> void:
	if memory_id == 0 or not _bindings.has(memory_id):
		return
	var b: GraphDebugBinding = _bindings[memory_id] as GraphDebugBinding
	_bindings.erase(memory_id)
	_last_sync_msec.erase(memory_id)
	if b != null:
		if b.is_paused:
			_paused_count = maxi(0, _paused_count - 1)
		b.dispose()
	if is_debugger_connected():
		EngineDebugger.send_message(MSG_UNREGISTER, [memory_id])


static func _sweep_dead_bindings_if_needed(now_ms: int) -> void:
	if _bindings.is_empty() or (now_ms - _last_sweep_msec) < _DEAD_SWEEP_INTERVAL_MSEC:
		return
	_last_sweep_msec = now_ms
	_prune_dead_bindings_now()


static func _prune_dead_bindings_now() -> void:
	if _bindings.is_empty():
		return
	var dead_ids: PackedInt64Array = PackedInt64Array()
	for k: Variant in _bindings.keys():
		var mid: int = int(k)
		var b: GraphDebugBinding = _bindings[mid] as GraphDebugBinding
		if b == null or not b.is_alive():
			dead_ids.append(mid)
	for dead_id: int in dead_ids:
		unregister(dead_id)

#endregion


#region 暂停计数同步、帧遥测推送与单步挂起门禁

## 由 [GraphDebugBinding] 在暂停状态变化时统一回调，精准维护 `_paused_count`。
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


## 供算法主循环调用：检查该内存 ID 是否被编辑器单步或断点暂停。零暂停实例时 $O(1)$ 布尔短路。
static func should_suspend_tick(memory_id: int) -> bool:
	if _paused_count <= 0 or memory_id == 0:
		return false
	var b: GraphDebugBinding = _bindings.get(memory_id, null) as GraphDebugBinding
	if b == null:
		_sweep_dead_bindings_if_needed(Time.get_ticks_msec())
		return false
	if not b.is_alive():
		unregister(memory_id)
		return false
	return b.consume_suspend_gate()


## 节流推送指定内存 ID 的最新状态快照至编辑器画布（默认 60ms 分频防 IPC 拥塞；`force=true` 或刚命中断点时立即穿透推送）。
static func push_frame(memory_id: int, force: bool = false) -> void:
	if not _is_session_enabled() or memory_id == 0 or not _bindings.has(memory_id):
		return
	var b: GraphDebugBinding = _bindings[memory_id] as GraphDebugBinding
	if b == null or not b.is_alive():
		unregister(memory_id)
		return

	var now_ms: int = Time.get_ticks_msec()
	_sweep_dead_bindings_if_needed(now_ms)
	var prev_ms: int = int(_last_sync_msec.get(memory_id, 0))
	var throttled: bool = (not force) and (now_ms - prev_ms) < DEFAULT_SYNC_INTERVAL_MSEC

	if throttled:
		# 在 60ms 节流窗口内仅执行 $O(B)$ 零分配断点快筛，未命中时直接返回，避免全量序列化与黑板拷贝开销
		if not b.probe_breakpoints_fast():
			return

	var frame_dict: Dictionary = b.capture_frame_dict()
	var hit_just_now: bool = b.consume_breakpoint_hit_pending()
	if throttled and not hit_just_now:
		return
	_last_sync_msec[memory_id] = now_ms

	if is_debugger_connected():
		if b.topology_dirty:
			EngineDebugger.send_message(MSG_TOPOLOGY, [memory_id, b.export_topology_dict()])
		EngineDebugger.send_message(MSG_FRAME, [memory_id, frame_dict])


## 主动上报一次有向边流转（驱动编辑器画布播放流光粒子脉冲）。
static func notify_edge_flow(memory_id: int, from_id: String, to_id: String, label: String = "") -> void:
	if not _is_session_enabled() or memory_id == 0 or not _bindings.has(memory_id):
		return
	if is_debugger_connected():
		EngineDebugger.send_message(MSG_EDGE_FLOW, [memory_id, from_id, to_id, label])
	push_frame(memory_id, true)


## 按磁盘资源路径热重载所有关联运行实例（支持直接主图匹配与嵌套子图联动重编译，共享享元 [BTTree] 自动按 `secondary_id` 去重）。
static func hot_reload_by_resource_path(resource_path: String, ir_dict: Dictionary) -> int:
	var clean_path: String = resource_path.strip_edges()
	if clean_path.is_empty():
		return 0

	var reloaded_trees: Dictionary = {}      ## {int (secondary_id): bool}
	var reloaded_tree_topos: Dictionary = {} ## {int (secondary_id): Dictionary}
	var updated_count: int = 0
	var dead_ids: PackedInt64Array = PackedInt64Array()

	for k: Variant in _bindings.keys():
		var mid: int = int(k)
		var b: GraphDebugBinding = _bindings[mid] as GraphDebugBinding
		if b == null or not b.is_alive():
			dead_ids.append(mid)
			continue

		var is_direct_match: bool = (b.resolve_source_resource_path() == clean_path)
		var is_sub_match: bool = (not is_direct_match) and b.references_sub_resource_path(clean_path)
		if not is_direct_match and not is_sub_match:
			continue

		var target_ir: Dictionary = ir_dict if is_direct_match else b.export_topology_dict()
		if target_ir.is_empty():
			continue

		var ok: bool = false
		var topo_payload: Dictionary = {}
		if b.recognized_kind == GraphDebugBinding.KIND_BT and b.secondary_id != 0:
			if reloaded_trees.has(b.secondary_id):
				ok = bool(reloaded_trees[b.secondary_id])
				if ok:
					b.reset_after_hot_reload()
					topo_payload = reloaded_tree_topos.get(b.secondary_id, {}) as Dictionary
			else:
				ok = b.hot_reload_ir(target_ir)
				reloaded_trees[b.secondary_id] = ok
				if ok:
					topo_payload = b.export_topology_dict()
					reloaded_tree_topos[b.secondary_id] = topo_payload
		else:
			ok = b.hot_reload_ir(target_ir)
			if ok:
				topo_payload = b.export_topology_dict()

		if ok:
			b.topology_dirty = false
			updated_count += 1
			if is_debugger_connected():
				EngineDebugger.send_message(MSG_TOPOLOGY, [mid, topo_payload])
				EngineDebugger.send_message(MSG_FRAME, [mid, b.capture_frame_dict()])

	for dead_id: int in dead_ids:
		unregister(dead_id)
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
	EngineDebugger.send_message(MSG_REGISTER, [
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
		EngineDebugger.send_message(MSG_TOPOLOGY, [memory_id, b.export_topology_dict()])


static func _on_debugger_message(message: String, data: Array) -> bool:
	match message:
		_INBOUND_SYNC_ALL:
			var stale_ids: PackedInt64Array = PackedInt64Array()
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

		_INBOUND_WINDOW_TOPMOST:
			var enable_top: bool = bool(data[0]) if not data.is_empty() else false
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enable_top)
			return true

		_INBOUND_CMD:
			if data.size() >= 3:
				var target_mid: int = int(data[0])
				var cmd_name := StringName(str(data[1]))
				var payload: Dictionary = data[2] as Dictionary if data[2] is Dictionary else {}
				var b: GraphDebugBinding = _bindings.get(target_mid, null) as GraphDebugBinding
				if b != null:
					if not b.is_alive():
						unregister(target_mid)
					elif b.execute_command(cmd_name, payload):
						push_frame(target_mid, true)
			return true

		_INBOUND_HOT_RELOAD:
			if data.size() >= 2:
				var res_path: String = str(data[0]).strip_edges()
				var ir_dict: Dictionary = data[1] as Dictionary if data[1] is Dictionary else {}
				hot_reload_by_resource_path(res_path, ir_dict)
			return true

	return false

#endregion
