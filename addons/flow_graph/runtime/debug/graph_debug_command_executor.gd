@tool
class_name GraphDebugCommandExecutor
extends RefCounted

## 跨进程下行调试指令与热重载执行器（Graph Debug Command & Hot-Reload Executor）。[br]
##
## [b]核心职责：[/b][br]
## 从 [GraphDebugBinding] 中解耦所有交互式控制指令与运行期热更新逻辑：[br]
## 1. 生命周期控制：`&"set_pause"`、`&"step_once"`；[br]
## 2. 节点断点管理：`&"set_breakpoint"`、`&"clear_breakpoints"`；[br]
## 3. 实时黑板热改：`&"set_var"`（经 [FlowBlackboardExpr] 安全转型后写入 [BTContext] 或 [StateMachine] 黑板）；[br]
## 4. 状态与事件测试：`&"force_node"`、`&"fire_event"`，以及蓝图 `hot_reload`。


#region 调试命令常量

const CMD_SET_PAUSE: StringName = &"set_pause"
const CMD_STEP_ONCE: StringName = &"step_once"
const CMD_SET_BREAKPOINT: StringName = &"set_breakpoint"
const CMD_CLEAR_BREAKPOINTS: StringName = &"clear_breakpoints"
const CMD_FORCE_NODE: StringName = &"force_node"
const CMD_SET_VAR: StringName = &"set_var"
const CMD_FIRE_EVENT: StringName = &"fire_event"

#endregion


#region 指令分发与热重载执行

## 执行编辑器下发的单实例控制命令；返回 `true` 表示状态发生变更需立即回推最新帧。
static func execute(binding: GraphDebugBinding, command: StringName, payload: Dictionary) -> bool:
	if binding == null:
		return false

	match command:
		CMD_SET_PAUSE:
			var target_pause: bool = bool(payload.get("paused", false))
			binding.set_paused_state(target_pause)
			if not target_pause:
				binding.step_budget = 0
			return true
		CMD_STEP_ONCE:
			binding.request_step_once()
			return true
		CMD_SET_BREAKPOINT:
			var bp_node_id: String = str(payload.get("node_id", "")).strip_edges()
			if bp_node_id.is_empty():
				return false
			var enabled: bool = bool(payload.get("enabled", true))
			binding.set_breakpoint(bp_node_id, enabled)
			return true
		CMD_CLEAR_BREAKPOINTS:
			binding.clear_breakpoints()
			return true

	if not binding.is_alive():
		return false

	match binding.recognized_kind:
		GraphDebugBinding.KIND_FSM:
			var fsm: StateMachine = instance_from_id(binding.memory_id) as StateMachine
			return _execute_fsm_command(fsm, command, payload) if fsm != null else false
		GraphDebugBinding.KIND_BT:
			var ctx: BTContext = instance_from_id(binding.memory_id) as BTContext
			return _execute_bt_command(ctx, command, payload) if ctx != null else false
		GraphDebugBinding.KIND_DEBUGGABLE:
			var dbg: BaseDebuggableGraph = instance_from_id(binding.memory_id) as BaseDebuggableGraph
			return dbg._on_debug_command(command, payload) if dbg != null else false
		_:
			return binding.invoke_custom_command(command, payload)


## 将标准图 IR 热更新注入在线图实例（校验失败时保持原运行态不中断）。
static func hot_reload(binding: GraphDebugBinding, ir: Dictionary) -> bool:
	if binding == null or not binding.is_alive() or ir.is_empty():
		return false
	match binding.recognized_kind:
		GraphDebugBinding.KIND_FSM:
			var fsm: StateMachine = instance_from_id(binding.memory_id) as StateMachine
			if fsm != null and fsm.hot_reload_from_ir(ir).is_ok():
				binding.reset_after_hot_reload()
				return true
		GraphDebugBinding.KIND_BT:
			var tree: BTTree = instance_from_id(binding.secondary_id) as BTTree
			if tree != null and tree.hot_reload_from_ir(ir).is_ok():
				binding.reset_after_hot_reload()
				return true
	return false

#endregion


#region 类型专属指令处理器

static func _execute_fsm_command(fsm: StateMachine, command: StringName, payload: Dictionary) -> bool:
	match command:
		CMD_FORCE_NODE:
			var target_state := StringName(str(payload.get("node_id", "")).strip_edges())
			return fsm.change_state(target_state, {}, true)
		CMD_SET_VAR:
			return _apply_blackboard_var(fsm.blackboard, payload)
		CMD_FIRE_EVENT:
			var ev_str: String = str(payload.get("event", payload.get("event_name", ""))).strip_edges()
			if ev_str.is_empty():
				return false
			var raw_ev_data: Variant = payload.get("payload", {})
			var ev_data: Dictionary = raw_ev_data as Dictionary if raw_ev_data is Dictionary else {}
			return fsm.fire_event(StringName(ev_str), ev_data)
		_:
			return false


static func _execute_bt_command(ctx: BTContext, command: StringName, payload: Dictionary) -> bool:
	match command:
		CMD_SET_VAR:
			return _apply_blackboard_var(ctx.blackboard, payload)
		CMD_FORCE_NODE:
			var parsed_nid: int = parse_bt_node_id(str(payload.get("node_id", "")))
			if parsed_nid > 0:
				ctx.request_debug_force_node(parsed_nid, 1.5)
				return true
			var node_key: String = str(payload.get("action_key", "")).strip_edges()
			if not node_key.is_empty():
				ctx.blackboard.set_var(&"debug_forced_action", StringName(node_key))
				return true
			return false
		_:
			return false


static func _apply_blackboard_var(bb: BTBlackboard, payload: Dictionary) -> bool:
	if bb == null:
		return false
	var key_str: String = str(payload.get("key", "")).strip_edges()
	if key_str.is_empty():
		return false
	var coerced: Variant = FlowBlackboardExpr.coerce_value(payload.get("value", null), str(payload.get("type", "")))
	bb.set_var(StringName(key_str), coerced)
	return true


## 解析 `"n12"` 或 `"12"` 为行为树整型 `node_id`（非法字符串返回 `0`）。
static func parse_bt_node_id(raw_id: String) -> int:
	var clean: String = raw_id.strip_edges()
	if clean.begins_with("n") and clean.substr(1).is_valid_int():
		return int(clean.substr(1))
	if clean.is_valid_int():
		return int(clean)
	return 0

#endregion
