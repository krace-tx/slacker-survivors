class_name StateMachine
extends RefCounted

## 有限与层次状态机（FSM / HFSM）执行内核与实时遥测器。[br]
##
## [b]核心特性：[/b][br]
## 1. [b]双模状态注册与 HFSM 子图[/b]：支持代码注册状态、蓝图 `.tres` 编译与 `sub_graph_path` 层次子状态机自动挂载；[br]
## 2. [b]黑板与脉冲事件 (`fire_event`)[/b]：内置 [BTBlackboard] 与单帧有效脉冲事件表，原生支持 `!cond`、`&& / ||` 与比较表达式；[br]
## 3. [b]运行期无损热重载[/b]：通过 [method hot_reload_from_ir] 热更转换拓扑与黑板 Schema，不断流保留当前驻留状态。

#region Signals & Public Properties
signal state_changed(new_state: StringName, prev_state: StringName, msg: Dictionary)

## 状态机内置共享黑板（自动与嵌套 HFSM 子状态机共享）。
var blackboard: BTBlackboard = BTBlackboard.new()
#endregion

#region Private State
const _MAX_HISTORY_LEN: int = 12

var _actor_id: int = 0
var _graph_id: StringName = &"fsm"
var _states: Dictionary = {} ## {StringName: BaseFsmState}
var _state_sources: Dictionary = {} ## {StringName: Dictionary}
var _ast_sub_machines: Dictionary = {} ## {StringName: bool}
var _runtime_transitions: Array[Dictionary] = [] ## [{def, predicate, seq, from_ast}]
var _ast: FsmGraphDef = FsmGraphDef.new()
var _condition_registry: Dictionary = {} ## {StringName: Callable}
var _pending_events: Dictionary = {} ## {StringName: Dictionary}

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


func get_actor() -> Object:
	return instance_from_id(_actor_id) if (_actor_id != 0 and is_instance_id_valid(_actor_id)) else null


func add_state(state_id: StringName, state: BaseFsmState, title: String = "", editor_pos: Vector2 = Vector2.ZERO, params: Dictionary = {}) -> StateMachine:
	if state_id.is_empty() or state == null:
		return self
	state.state_id = state_id
	state.title = title if not title.is_empty() else String(state_id)
	state.bind_context(self, get_actor())
	_states[state_id] = state

	var caller_src: Dictionary = GraphDebugBridge.capture_caller_source()
	if not caller_src.is_empty():
		_state_sources[state_id] = caller_src

	var existing_def: FsmStateDef = _ast.find_state_def(state_id)
	var auto_pos: Vector2 = editor_pos if editor_pos != Vector2.ZERO else Vector2(float((_states.size() - 1) % 3) * 190.0, float((_states.size() - 1) / 3) * 110.0)
	if existing_def == null:
		existing_def = FsmStateDef.create(state_id, state.title, auto_pos, params)
		_ast.states.append(existing_def)
	if not caller_src.is_empty():
		existing_def.debug_source_file = str(caller_src.get("file", ""))
		existing_def.debug_source_line = int(caller_src.get("line", 0))
	if _ast.initial_state.is_empty():
		_ast.initial_state = state_id
	return self


func add_callable(
	state_id: StringName, on_enter_cb: Callable = Callable(), on_update_cb: Callable = Callable(),
	on_exit_cb: Callable = Callable(), can_transition_cb: Callable = Callable(),
	title: String = "", editor_pos: Vector2 = Vector2.ZERO
) -> StateMachine:
	var lambda_state := FsmLambdaState.new(on_enter_cb, on_update_cb, on_exit_cb, can_transition_cb)
	return add_state(state_id, lambda_state, title, editor_pos)


func add_transition(
	from_state: StringName, to_state: StringName, predicate: Callable = Callable(),
	priority: int = 0, min_state_time: float = 0.0, description: String = "",
	condition_key: StringName = &"", trigger_event: StringName = &"", bb_expr: String = ""
) -> StateMachine:
	var tr_def := FsmTransitionDef.create(from_state, to_state, condition_key, priority, min_state_time, description, trigger_event, bb_expr)
	_ast.transitions.append(tr_def)
	_append_runtime_transition(tr_def, predicate, false)
	_sort_runtime_transitions()
	return self


func add_visual_edge(from_state: StringName, to_state: StringName, description: String = "") -> StateMachine:
	_ast.transitions.append(FsmTransitionDef.create(from_state, to_state, &"", 0, 0.0, description))
	return self


func register_condition(condition_key: StringName, predicate: Callable) -> StateMachine:
	if not condition_key.is_empty() and predicate.is_valid():
		_condition_registry[condition_key] = predicate
	return self


func compile_from_ast(graph_def: FsmGraphDef, depth: int = 0) -> FlowGraphResult:
	return FsmCompiler.compile_into(self, graph_def, depth)


func hot_reload_from_ir(ir: Dictionary) -> FlowGraphResult:
	return FsmCompiler.hot_reload_into(self, ir)
#endregion


#region Execution, Pulse Events & Transitions
func start(initial_state_id: StringName = &"", msg: Dictionary = {}) -> bool:
	var target: StringName = initial_state_id if not initial_state_id.is_empty() else _ast.initial_state
	if target.is_empty() or not _states.has(target):
		return false
	_current_id = target
	_previous_id = &""
	_state_time = 0.0
	_pending_events.clear()
	_record_history(target)
	var st: BaseFsmState = _states[target] as BaseFsmState
	st._on_enter(&"", msg)
	if st.sub_machine is StateMachine:
		(st.sub_machine as StateMachine).start()
	state_changed.emit(_current_id, &"", msg)
	return true


func change_state(target_state_id: StringName, msg: Dictionary = {}, force: bool = false) -> bool:
	if target_state_id.is_empty() or not _states.has(target_state_id):
		return false
	if _current_id == target_state_id and not force:
		return false
	if _is_transitioning:
		_pending_target = target_state_id
		_pending_msg = msg
		return true

	var cur_state: BaseFsmState = _states.get(_current_id, null) as BaseFsmState
	if cur_state != null and not force and not cur_state._can_transition_to(target_state_id):
		return false

	_is_transitioning = true
	var prev_id: StringName = _current_id
	if cur_state != null:
		cur_state._on_exit(target_state_id)

	_previous_id = prev_id
	_current_id = target_state_id
	_state_time = 0.0
	_total_transitions += 1
	_last_transition_from = prev_id
	_last_transition_to = target_state_id
	_record_history(target_state_id)

	var next_state: BaseFsmState = _states[target_state_id] as BaseFsmState
	next_state._on_enter(prev_id, msg)
	if next_state.sub_machine is StateMachine:
		(next_state.sub_machine as StateMachine).start()
	state_changed.emit(_current_id, prev_id, msg)
	_is_transitioning = false

	if not _pending_target.is_empty():
		var pt: StringName = _pending_target
		var pm: Dictionary = _pending_msg
		_pending_target = &""
		_pending_msg = {}
		change_state(pt, pm)
	return true


func revert_to_previous(msg: Dictionary = {}) -> bool:
	return false if _previous_id.is_empty() else change_state(_previous_id, msg)


## 发射脉冲事件：优先交由激活子状态机消费，未消费则立即评估父级匹配边；残余事件在当帧 `update()` 末尾清空。
func fire_event(event_name: StringName, payload: Dictionary = {}) -> bool:
	if event_name.is_empty() or _current_id.is_empty() or not _states.has(_current_id):
		return false
	var cur_state: BaseFsmState = _states.get(_current_id, null) as BaseFsmState
	if cur_state != null and cur_state.sub_machine is StateMachine:
		if (cur_state.sub_machine as StateMachine).fire_event(event_name, payload):
			return true

	_pending_events[event_name] = payload
	for entry: Dictionary in _runtime_transitions:
		if _evaluate_transition_entry(entry, event_name):
			var tr_def: FsmTransitionDef = entry["def"] as FsmTransitionDef
			_pending_events.erase(event_name)
			if change_state(tr_def.to_state, payload):
				GraphDebugBridge.push_frame(get_instance_id(), true)
				return true
			_pending_events[event_name] = payload
	return false


func update(delta: float) -> void:
	if _current_id.is_empty() or not _states.has(_current_id):
		return
	var self_id: int = get_instance_id()
	if GraphDebugBridge.should_suspend_tick(self_id):
		return
	_state_time += maxf(0.0, delta)

	for entry: Dictionary in _runtime_transitions:
		if _evaluate_transition_entry(entry):
			var tr_def: FsmTransitionDef = entry["def"] as FsmTransitionDef
			var ev_msg: Dictionary = _pending_events[tr_def.trigger_event] as Dictionary if (not tr_def.trigger_event.is_empty() and _pending_events.has(tr_def.trigger_event)) else {}
			if change_state(tr_def.to_state, ev_msg):
				break
	_pending_events.clear()

	var cur_state: BaseFsmState = _states.get(_current_id, null) as BaseFsmState
	if cur_state != null:
		cur_state._on_update(delta)
		if cur_state.sub_machine is StateMachine:
			(cur_state.sub_machine as StateMachine).update(delta)
	GraphDebugBridge.push_frame(self_id)


func physics_update(delta: float) -> void:
	if _current_id.is_empty() or not _states.has(_current_id):
		return
	var cur_state: BaseFsmState = _states.get(_current_id, null) as BaseFsmState
	if cur_state != null:
		cur_state._on_physics_update(delta)
		if cur_state.sub_machine is StateMachine:
			(cur_state.sub_machine as StateMachine).physics_update(delta)


func send_event(event_name: StringName, payload: Variant = null) -> bool:
	var cur_state: BaseFsmState = _states.get(_current_id, null) as BaseFsmState
	if cur_state == null:
		return false
	if cur_state.sub_machine is StateMachine and (cur_state.sub_machine as StateMachine).send_event(event_name, payload):
		return true
	return cur_state._on_event(event_name, payload)
#endregion


#region Internal Compiler Hooks, Transition Evaluation & Telemetry
func _evaluate_transition_entry(entry: Dictionary, only_event: StringName = &"") -> bool:
	var tr_def: FsmTransitionDef = entry["def"] as FsmTransitionDef
	if (tr_def.from_state != _current_id and tr_def.from_state != FsmTransitionDef.ANY_STATE) or tr_def.to_state == _current_id:
		return false
	if (not only_event.is_empty() and tr_def.trigger_event != only_event) or (not tr_def.trigger_event.is_empty() and not _pending_events.has(tr_def.trigger_event)):
		return false
	if tr_def.min_state_time > 0.0 and _state_time < tr_def.min_state_time:
		return false

	var pred: Callable = entry["predicate"] as Callable
	var has_guard: bool = pred.is_valid() or not tr_def.trigger_event.is_empty() or not tr_def.condition_key.is_empty() or not tr_def.bb_expr.is_empty() or tr_def.min_state_time > 0.0
	if bool(entry.get("from_ast", false)) and not has_guard:
		return false

	var matched: bool = true
	if pred.is_valid():
		matched = bool(pred.call(self)) if pred.get_argument_count() >= 1 else bool(pred.call())
	elif not tr_def.condition_key.is_empty():
		matched = FlowBlackboardExpr.eval_expr(String(tr_def.condition_key), _lookup_condition, blackboard, self)
	if matched and not tr_def.bb_expr.is_empty():
		matched = FlowBlackboardExpr.eval_expr(tr_def.bb_expr, Callable(), blackboard, self)
	return matched


func _lookup_condition(cond_key: StringName) -> Callable:
	return _condition_registry.get(cond_key, Callable()) as Callable


func _set_compiled_ast(graph_def: FsmGraphDef) -> void:
	_ast = graph_def
	_graph_id = graph_def.graph_id
	_runtime_transitions.clear()


func _share_condition_registry(shared_reg: Dictionary) -> void: _condition_registry = shared_reg
func _get_states_internal() -> Dictionary: return _states
func _get_state_sources_internal() -> Dictionary: return _state_sources
func _get_ast_sub_machines_internal() -> Dictionary: return _ast_sub_machines
func _get_condition_registry_internal() -> Dictionary: return _condition_registry


func _reconcile_active_state_after_reload() -> void:
	if _current_id.is_empty():
		return
	if _states.has(_current_id):
		var cur_st: BaseFsmState = _states[_current_id] as BaseFsmState
		if cur_st != null and cur_st.sub_machine is StateMachine and (cur_st.sub_machine as StateMachine).get_current_state_id().is_empty():
			(cur_st.sub_machine as StateMachine).start()
	elif not _ast.initial_state.is_empty() and _states.has(_ast.initial_state):
		start(_ast.initial_state)
	else:
		_current_id = &""
		_state_time = 0.0


func _append_runtime_transition(tr_def: FsmTransitionDef, pred: Callable, from_ast: bool) -> void:
	_seq_counter += 1
	_runtime_transitions.append({"def": tr_def, "predicate": pred, "seq": _seq_counter, "from_ast": from_ast})


func _sort_runtime_transitions() -> void:
	_runtime_transitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: FsmTransitionDef = a["def"] as FsmTransitionDef
		var db: FsmTransitionDef = b["def"] as FsmTransitionDef
		return da.priority > db.priority if da.priority != db.priority else int(a["seq"]) < int(b["seq"])
	)


func has_state(state_id: StringName) -> bool: return _states.has(state_id)
func get_current_state_id() -> StringName: return _current_id
func get_previous_state_id() -> StringName: return _previous_id
func get_state_time() -> float: return _state_time
func get_ast() -> FsmGraphDef: return _ast


func clear() -> void:
	_states.clear()
	_state_sources.clear()
	_ast_sub_machines.clear()
	_runtime_transitions.clear()
	_condition_registry.clear()
	_pending_events.clear()
	_current_id = &""
	_previous_id = &""


func get_telemetry_snapshot() -> Dictionary:
	var cur_st: BaseFsmState = _states.get(_current_id, null) as BaseFsmState
	var sub_st: String = String((cur_st.sub_machine as StateMachine).get_current_state_id()) if (cur_st != null and cur_st.sub_machine is StateMachine) else ""
	return {
		"graph_id": String(_graph_id), "current_state": String(_current_id), "sub_state": sub_st,
		"previous_state": String(_previous_id), "state_time": snappedf(_state_time, 0.01),
		"total_transitions": _total_transitions, "last_edge": [String(_last_transition_from), String(_last_transition_to)],
		"history": _history.duplicate(), "blackboard": blackboard.get_all(),
	}


func _record_history(state_id: StringName) -> void:
	_history.append(state_id)
	if _history.size() > _MAX_HISTORY_LEN:
		_history.pop_front()
#endregion
