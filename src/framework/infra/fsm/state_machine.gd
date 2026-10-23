class_name StateMachine
extends RefCounted

## 有限与层次状态机（FSM / HFSM）执行内核、AST 编译器与实时遥测器。[br]
##
## [b]核心特性：[/b][br]
## 1. [b]双模状态注册[/b]：既可注册强类型 [BaseFsmState] 子类，也可通过 [method add_callable] 快速注册内联闭包状态；[br]
## 2. [b]代码与 AST 蓝图同构[/b]：代码注册状态与转换边时自动同步构建 [FsmGraphDef] AST；亦可直接通过 [method compile_from_ast] 从蓝图数据装配状态机；[br]
## 3. [b]声明式自动转换边[/b]：每帧自动按优先级评估当前状态（含 `&"*"` 通配边）的 `min_state_time` 与条件谓词 `Callable`；[br]
## 4. [b]防重入与前驱回退[/b]：内置 `_is_transitioning` 队列锁防止 `_on_exit` 递归切状态死循环，支持 [method revert_to_previous] 一键回到前驱状态；[br]
## 5. [b]可视化实时遥测[/b]：随时通过 [method get_telemetry_snapshot] 导出当前激活状态、驻留时长与最近转换边，驱动可视化状态图高亮。

#region Signals
## 当状态发生切换时触发。
signal state_changed(new_state: StringName, prev_state: StringName, msg: Dictionary)
#endregion

#region Private State
const _MAX_HISTORY_LEN: int = 12

var _actor_id: int = 0
var _graph_id: StringName = &"fsm"
var _states: Dictionary = {} ## {StringName: BaseFsmState}
var _runtime_transitions: Array[Dictionary] = [] ## [{def: FsmTransitionDef, predicate: Callable, seq: int}]
var _ast: FsmGraphDef = FsmGraphDef.new()
var _condition_registry: Dictionary = {} ## {StringName: Callable}

var _current_id: StringName = &""
var _previous_id: StringName = &""
var _state_time: float = 0.0
var _total_transitions: int = 0
var _last_transition_from: StringName = &""
var _last_transition_to: StringName = &""
var _history: Array[StringName] = []

var _is_transitioning: bool = false
var _pending_target: StringName = &""
var _pending_msg: Dictionary = {}
var _seq_counter: int = 0
#endregion


#region Lifecycle & Registration
func _init(actor: Object = null, graph_id: StringName = &"fsm") -> void:
	_actor_id = actor.get_instance_id() if is_instance_valid(actor) else 0
	_graph_id = graph_id
	_ast.graph_id = graph_id


## 获取绑定的宿主对象。
func get_actor() -> Object:
	if _actor_id == 0 or not is_instance_id_valid(_actor_id):
		return null
	return instance_from_id(_actor_id)


## 注册一个强类型 [BaseFsmState] 实例，并同步写入 [FsmGraphDef] AST。
func add_state(
	state_id: StringName,
	state: BaseFsmState,
	title: String = "",
	editor_pos: Vector2 = Vector2.ZERO,
	params: Dictionary = {}
) -> StateMachine:
	if state_id.is_empty() or state == null:
		return self
	state.state_id = state_id
	state.title = title if not title.is_empty() else String(state_id)
	state.bind_context(self, get_actor())
	_states[state_id] = state

	var existing_def := _ast.find_state_def(state_id)
	var auto_pos := editor_pos if editor_pos != Vector2.ZERO else Vector2(float((_states.size() - 1) % 3) * 190.0, float((_states.size() - 1) / 3) * 110.0)
	if existing_def == null:
		_ast.states.append(FsmStateDef.create(state_id, state.title, auto_pos, params))
	if _ast.initial_state.is_empty():
		_ast.initial_state = state_id
	return self


## 快速注册一个由 `Callable` 驱动的轻量状态，并同步写入 [FsmGraphDef] AST。
func add_callable(
	state_id: StringName,
	on_enter_cb: Callable = Callable(),
	on_update_cb: Callable = Callable(),
	on_exit_cb: Callable = Callable(),
	can_transition_cb: Callable = Callable(),
	title: String = "",
	editor_pos: Vector2 = Vector2.ZERO
) -> StateMachine:
	var lambda_state := FsmLambdaState.new(on_enter_cb, on_update_cb, on_exit_cb, can_transition_cb)
	return add_state(state_id, lambda_state, title, editor_pos)


## 注册一条声明式状态转换有向边（支持条件 `predicate` 与最小驻留时长 `min_state_time`）。
func add_transition(
	from_state: StringName,
	to_state: StringName,
	predicate: Callable = Callable(),
	priority: int = 0,
	min_state_time: float = 0.0,
	description: String = "",
	condition_key: StringName = &""
) -> StateMachine:
	var tr_def := FsmTransitionDef.create(from_state, to_state, condition_key, priority, min_state_time, description)
	_ast.transitions.append(tr_def)
	_seq_counter += 1
	_runtime_transitions.append({
		"def": tr_def,
		"predicate": predicate,
		"seq": _seq_counter,
	})
	_runtime_transitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: FsmTransitionDef = a["def"]
		var db: FsmTransitionDef = b["def"]
		if da.priority != db.priority:
			return da.priority > db.priority
		return int(a["seq"]) < int(b["seq"])
	)
	return self


## 注册命名条件谓词（供 [method compile_from_ast] 解析蓝图中的 `condition_key`）。
func register_condition(condition_key: StringName, predicate: Callable) -> StateMachine:
	if not condition_key.is_empty() and predicate.is_valid():
		_condition_registry[condition_key] = predicate
	return self


## 从 [FsmGraphDef] 抽象语法树编译并装配状态转换边（状态本体若未预注册则自动生成空壳状态）。
func compile_from_ast(graph_def: FsmGraphDef) -> Result:
	if graph_def == null:
		return Result.err_code("FSM.NullGraphDef", "Cannot compile null FsmGraphDef.")
	var val_res := graph_def.validate()
	if val_res.is_err():
		return val_res

	_ast = graph_def
	_graph_id = graph_def.graph_id
	_runtime_transitions.clear()

	for s_def: FsmStateDef in graph_def.states:
		if not _states.has(s_def.state_id):
			var placeholder := FsmLambdaState.new()
			placeholder.state_id = s_def.state_id
			placeholder.title = s_def.title
			placeholder.bind_context(self, get_actor())
			_states[s_def.state_id] = placeholder

	for tr_def: FsmTransitionDef in graph_def.transitions:
		var pred: Callable = _condition_registry.get(tr_def.condition_key, Callable())
		_seq_counter += 1
		_runtime_transitions.append({
			"def": tr_def,
			"predicate": pred,
			"seq": _seq_counter,
		})

	_runtime_transitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: FsmTransitionDef = a["def"]
		var db: FsmTransitionDef = b["def"]
		if da.priority != db.priority:
			return da.priority > db.priority
		return int(a["seq"]) < int(b["seq"])
	)
	return Result.ok(self)
#endregion


#region Execution & Transitions
## 启动状态机并进入初始状态（不传则使用 AST 的 `initial_state`）。
func start(initial_state_id: StringName = &"", msg: Dictionary = {}) -> bool:
	var target := initial_state_id if not initial_state_id.is_empty() else _ast.initial_state
	if target.is_empty() or not _states.has(target):
		return false
	_current_id = target
	_previous_id = &""
	_state_time = 0.0
	_record_history(target)
	var st: BaseFsmState = _states[target]
	st._on_enter(&"", msg)
	if st.sub_machine is StateMachine:
		(st.sub_machine as StateMachine).start()
	state_changed.emit(_current_id, &"", msg)
	return true


## 请求切换到目标状态（自动经过当前状态的 `_can_transition_to` 守卫校验与防重入保护）。
func change_state(target_state_id: StringName, msg: Dictionary = {}, force: bool = false) -> bool:
	if target_state_id.is_empty() or not _states.has(target_state_id):
		return false
	if _current_id == target_state_id and not force:
		return false

	if _is_transitioning:
		_pending_target = target_state_id
		_pending_msg = msg
		return true

	var cur_state: BaseFsmState = _states.get(_current_id, null)
	if cur_state != null and not force:
		if not cur_state._can_transition_to(target_state_id):
			return false

	_is_transitioning = true
	var prev_id := _current_id
	if cur_state != null:
		cur_state._on_exit(target_state_id)

	_previous_id = prev_id
	_current_id = target_state_id
	_state_time = 0.0
	_total_transitions += 1
	_last_transition_from = prev_id
	_last_transition_to = target_state_id
	_record_history(target_state_id)

	var next_state: BaseFsmState = _states[target_state_id]
	next_state._on_enter(prev_id, msg)
	if next_state.sub_machine is StateMachine:
		(next_state.sub_machine as StateMachine).start()
	state_changed.emit(_current_id, prev_id, msg)
	_is_transitioning = false

	if not _pending_target.is_empty():
		var pt := _pending_target
		var pm := _pending_msg
		_pending_target = &""
		_pending_msg = {}
		change_state(pt, pm)

	return true


## 一键回退至前一个状态（常用于受击硬直、冰冻结束后的状态恢复）。
func revert_to_previous(msg: Dictionary = {}) -> bool:
	if _previous_id.is_empty():
		return false
	return change_state(_previous_id, msg)


## 每帧推进状态机计时、自动评估条件转换边并执行当前状态的 `_on_update`。
func update(delta: float) -> void:
	if _current_id.is_empty() or not _states.has(_current_id):
		return
	_state_time += maxf(0.0, delta)

	# 1. 自动评估声明式转换边
	for entry: Dictionary in _runtime_transitions:
		var tr_def: FsmTransitionDef = entry["def"]
		if tr_def.from_state != _current_id and tr_def.from_state != FsmTransitionDef.ANY_STATE:
			continue
		if tr_def.to_state == _current_id:
			continue
		if tr_def.min_state_time > 0.0 and _state_time < tr_def.min_state_time:
			continue
		var pred: Callable = entry["predicate"]
		var matched := true
		if pred.is_valid():
			matched = bool(pred.call(self)) if pred.get_argument_count() >= 1 else bool(pred.call())
		elif not tr_def.condition_key.is_empty() and _condition_registry.has(tr_def.condition_key):
			var reg_pred: Callable = _condition_registry[tr_def.condition_key]
			matched = bool(reg_pred.call(self)) if reg_pred.get_argument_count() >= 1 else bool(reg_pred.call())
		elif not tr_def.condition_key.is_empty() and tr_def.min_state_time <= 0.0:
			matched = false

		if matched:
			if change_state(tr_def.to_state):
				break

	# 2. 驱动当前状态与嵌套子状态机更新
	var cur_state: BaseFsmState = _states.get(_current_id, null)
	if cur_state != null:
		cur_state._on_update(delta)
		if cur_state.sub_machine is StateMachine:
			(cur_state.sub_machine as StateMachine).update(delta)


## 物理帧更新。
func physics_update(delta: float) -> void:
	if _current_id.is_empty() or not _states.has(_current_id):
		return
	var cur_state: BaseFsmState = _states.get(_current_id, null)
	if cur_state != null:
		cur_state._on_physics_update(delta)
		if cur_state.sub_machine is StateMachine:
			(cur_state.sub_machine as StateMachine).physics_update(delta)


## 向当前状态（及嵌套子状态机）投递语义事件。
func send_event(event_name: StringName, payload: Variant = null) -> bool:
	var cur_state: BaseFsmState = _states.get(_current_id, null)
	if cur_state == null:
		return false
	if cur_state.sub_machine is StateMachine:
		if (cur_state.sub_machine as StateMachine).send_event(event_name, payload):
			return true
	return cur_state._on_event(event_name, payload)
#endregion


#region Queries & Live Telemetry
func has_state(state_id: StringName) -> bool:
	return _states.has(state_id)


func get_current_state_id() -> StringName:
	return _current_id


func get_previous_state_id() -> StringName:
	return _previous_id


func get_state_time() -> float:
	return _state_time


func get_ast() -> FsmGraphDef:
	return _ast


## 释放全部状态与闭包回调引用，打破潜在的宿主 Lambda 环路。
func clear() -> void:
	_states.clear()
	_runtime_transitions.clear()
	_condition_registry.clear()
	_current_id = &""
	_previous_id = &""


## 获取实时遥测快照（供可视化蓝图面板高亮当前激活状态与最近转换边）。
func get_telemetry_snapshot() -> Dictionary:
	return {
		"graph_id": String(_graph_id),
		"current_state": String(_current_id),
		"previous_state": String(_previous_id),
		"state_time": snappedf(_state_time, 0.01),
		"total_transitions": _total_transitions,
		"last_edge": [String(_last_transition_from), String(_last_transition_to)],
		"history": _history.duplicate(),
	}


func _record_history(state_id: StringName) -> void:
	_history.append(state_id)
	if _history.size() > _MAX_HISTORY_LEN:
		_history.pop_front()
#endregion
