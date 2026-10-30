class_name GuardFsmAgent
extends RefCounted

## 【标准范例 ①】基于 [FsmGraphDef] `.tres` 蓝图驱动的守卫状态机实体代理。[br]
##
## [b]架构示范：[/b][br]
## 1. **图与代码解耦**：状态节点与 7 条转换边（含读秒跳转、`condition_key` 与 `* -> stun` 全局打断）全部由 `.tres` 资源定义；[br]
## 2. **原子算子绑定**：本类仅注册各状态的进入/更新回调与布尔条件谓词，零硬编码状态连线；[br]
## 3. **可视化一键跳回**：在 Mermaid 画布点击任意状态并点「跳转代码」，编辑器将直接定位至下方注册行。


#region Signals

signal transition_occurred(from_state: StringName, to_state: StringName)

#endregion


#region Public Readout & Private State

var enemy_visible: bool = false
var action_summary: String = "站岗警戒中"

var _fsm: StateMachine = null
var _debug_id: int = 0
var _stun_requested: bool = false

#endregion


#region Lifecycle & Setup

## 从 [param blueprint] 装配状态机并挂载至 [GraphDebugBridge]。
func setup(host_owner: Object, blueprint: FsmGraphDef, debug_title: String = "守卫队长_FSM") -> Result:
	if blueprint == null:
		return Result.err_code("MermaidTest.NullFsmBlueprint", "Guard FSM blueprint is null.")

	# 克隆静态定义资源，确保运行期调试元数据绝不污染磁盘缓存
	var graph_ast: FsmGraphDef = blueprint.duplicate(true) as FsmGraphDef
	_fsm = StateMachine.new(host_owner, graph_ast.graph_id)

	# 1. 注册原子状态动作（自动捕获当前源码行号供 Mermaid 画布一键跳转）
	_fsm.add_callable(&"idle", _on_idle_enter, _on_idle_update, Callable(), Callable(), "待机警戒")
	_fsm.add_callable(&"patrol", _on_patrol_enter, _on_patrol_update, Callable(), Callable(), "巡逻移动")
	_fsm.add_callable(&"attack", _on_attack_enter, _on_attack_update, Callable(), Callable(), "追击挥砍")
	_fsm.add_callable(&"stun", _on_stun_enter, _on_stun_update, Callable(), Callable(), "受击眩晕")

	# 2. 注册蓝图转换边上配置的 condition_key 谓词
	_fsm.register_condition(&"enemy_in_sight", func() -> bool: return enemy_visible)
	_fsm.register_condition(&"enemy_lost", func() -> bool: return not enemy_visible)
	_fsm.register_condition(&"hit_stun_triggered", _consume_stun_flag)

	# 3. 编译蓝图拓扑、启动状态机并注册实时调试
	var compile_res: FlowGraphResult = _fsm.compile_from_ast(graph_ast)
	if compile_res.is_err():
		return Result.err_code(compile_res.error_code(), compile_res.error_message())

	_fsm.state_changed.connect(_on_fsm_state_changed)
	_fsm.start()
	_debug_id = GraphDebugBridge.register(_fsm, host_owner, debug_title)
	return Result.ok(self)


## 每帧推进状态机计时与自动条件评估。
func tick(delta: float) -> void:
	if _fsm != null:
		_fsm.update(delta)


## 释放运行期调试句柄与状态机闭包引用。
func dispose() -> void:
	GraphDebugBridge.unregister(_debug_id)
	_debug_id = 0
	if _fsm != null:
		if _fsm.state_changed.is_connected(_on_fsm_state_changed):
			_fsm.state_changed.disconnect(_on_fsm_state_changed)
		_fsm.clear()
		_fsm = null

#endregion


#region Domain Controls & Queries

func get_fsm() -> StateMachine:
	return _fsm


func toggle_enemy_sight() -> bool:
	enemy_visible = not enemy_visible
	return enemy_visible


func request_hit_stun() -> void:
	_stun_requested = true


func revert_previous_state() -> bool:
	return _fsm.revert_to_previous() if _fsm != null else false

#endregion


#region Atomic State Callbacks & Predicates

func _on_idle_enter(_prev: StringName, _msg: Dictionary) -> void:
	action_summary = "站岗警戒中 (驻留满 2.0s 自动转入巡逻)"


func _on_idle_update(_delta: float) -> void:
	pass


func _on_patrol_enter(_prev: StringName, _msg: Dictionary) -> void:
	action_summary = "沿路线巡逻中 (驻留满 3.0s 返回站岗)"


func _on_patrol_update(_delta: float) -> void:
	pass


func _on_attack_enter(_prev: StringName, _msg: Dictionary) -> void:
	action_summary = "拔剑追击挥砍! (目标脱离视野后收剑)"


func _on_attack_update(_delta: float) -> void:
	pass


func _on_stun_enter(_prev: StringName, _msg: Dictionary) -> void:
	action_summary = "遭受重击眩晕硬直! (1.4s 后自动恢复)"


func _on_stun_update(_delta: float) -> void:
	pass


func _consume_stun_flag() -> bool:
	if not _stun_requested:
		return false
	_stun_requested = false
	return true


func _on_fsm_state_changed(new_state: StringName, prev_state: StringName, _msg: Dictionary) -> void:
	transition_occurred.emit(prev_state, new_state)

#endregion
