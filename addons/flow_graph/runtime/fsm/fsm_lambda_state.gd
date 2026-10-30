@tool
class_name FsmLambdaState
extends BaseFsmState

## 轻量内联闭包状态（Lambda / Callable-Driven FSM State）。[br]
##
## 允许在不创建独立 `.gd` 子类文件的前提下，通过 `Callable` 快速组装状态逻辑，
## 或由 [FsmGraphDef] AST 编译器动态绑定注册表动作函数；构造期预缓存回调元数避免每帧反射开销。

#region Callbacks & Cached Arities
var _on_enter_cb: Callable = Callable()
var _on_update_cb: Callable = Callable()
var _on_physics_cb: Callable = Callable()
var _on_exit_cb: Callable = Callable()
var _can_transition_cb: Callable = Callable()
var _on_event_cb: Callable = Callable()

var _enter_argc: int = 0
var _update_argc: int = 0
var _physics_argc: int = 0
var _exit_argc: int = 0
var _can_trans_argc: int = 0
var _event_argc: int = 0
#endregion


#region Lifecycle
func _init(
	on_enter_cb: Callable = Callable(),
	on_update_cb: Callable = Callable(),
	on_exit_cb: Callable = Callable(),
	can_transition_cb: Callable = Callable(),
	on_physics_cb: Callable = Callable(),
	on_event_cb: Callable = Callable()
) -> void:
	_on_enter_cb = on_enter_cb
	_on_update_cb = on_update_cb
	_on_exit_cb = on_exit_cb
	_can_transition_cb = can_transition_cb
	_on_physics_cb = on_physics_cb
	_on_event_cb = on_event_cb

	_enter_argc = _on_enter_cb.get_argument_count() if _on_enter_cb.is_valid() else 0
	_update_argc = _on_update_cb.get_argument_count() if _on_update_cb.is_valid() else 0
	_physics_argc = _on_physics_cb.get_argument_count() if _on_physics_cb.is_valid() else 0
	_exit_argc = _on_exit_cb.get_argument_count() if _on_exit_cb.is_valid() else 0
	_can_trans_argc = _can_transition_cb.get_argument_count() if _can_transition_cb.is_valid() else 0
	_event_argc = _on_event_cb.get_argument_count() if _on_event_cb.is_valid() else 0


func _on_enter(prev_state: StringName, msg: Dictionary) -> void:
	if not _on_enter_cb.is_valid():
		return
	if _enter_argc >= 2:
		_on_enter_cb.call(prev_state, msg)
	elif _enter_argc == 1:
		_on_enter_cb.call(prev_state)
	else:
		_on_enter_cb.call()


func _on_update(delta: float) -> void:
	if not _on_update_cb.is_valid():
		return
	if _update_argc >= 1:
		_on_update_cb.call(delta)
	else:
		_on_update_cb.call()


func _on_physics_update(delta: float) -> void:
	if not _on_physics_cb.is_valid():
		return
	if _physics_argc >= 1:
		_on_physics_cb.call(delta)
	else:
		_on_physics_cb.call()


func _on_exit(next_state: StringName) -> void:
	if not _on_exit_cb.is_valid():
		return
	if _exit_argc >= 1:
		_on_exit_cb.call(next_state)
	else:
		_on_exit_cb.call()


func _on_event(event_name: StringName, payload: Variant = null) -> bool:
	if not _on_event_cb.is_valid():
		return false
	if _event_argc >= 2:
		return bool(_on_event_cb.call(event_name, payload))
	return bool(_on_event_cb.call(event_name))


func _can_transition_to(next_state: StringName) -> bool:
	if not _can_transition_cb.is_valid():
		return true
	if _can_trans_argc >= 1:
		return bool(_can_transition_cb.call(next_state))
	return bool(_can_transition_cb.call())


func clear() -> void:
	_on_enter_cb = Callable()
	_on_update_cb = Callable()
	_on_physics_cb = Callable()
	_on_exit_cb = Callable()
	_can_transition_cb = Callable()
	_on_event_cb = Callable()
#endregion
