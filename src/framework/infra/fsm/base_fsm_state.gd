class_name BaseFsmState
extends RefCounted

## 有限/层次状态机（FSM / HFSM）的强类型状态基类。[br]
##
## [b]设计契约：[/b][br]
## 1. 继承自 [RefCounted]，零 `SceneTree` 节点树开销；[br]
## 2. 通过弱引用访问宿主 `actor` 与所属 `StateMachine`，杜绝循环引用内存泄漏；[br]
## 3. 支持挂载嵌套子状态机 [member sub_machine]（HFSM 层次状态机），父状态进入/更新/退出时自动级联驱动子状态机。

#region Public Metadata & Sub-Machine
## 状态唯一标识（由 [StateMachine] 注册时自动注入）。
var state_id: StringName = &""

## 状态可视化显示标题（供 AST 蓝图与调试器显示）。
var title: String = ""

## 可选：嵌套子状态机（HFSM 层次状态支持）。
var sub_machine: RefCounted = null
#endregion

#region Private Weak References
var _machine_ref: WeakRef = null
var _actor_id: int = 0
#endregion


#region Context Accessors
## 内部由 [StateMachine] 注入上下文引用。
func bind_context(machine: RefCounted, actor: Object) -> void:
	_machine_ref = weakref(machine) if machine != null else null
	_actor_id = actor.get_instance_id() if is_instance_valid(actor) else 0


## 获取所属的 [StateMachine] 实例。
func get_machine() -> Variant:
	return _machine_ref.get_ref() if _machine_ref != null else null


## 获取绑定的业务宿主对象（如角色 `Node3D`、控制器或 Presenter）。
func get_actor() -> Object:
	if _actor_id == 0 or not is_instance_id_valid(_actor_id):
		return null
	return instance_from_id(_actor_id)


## 获取当前状态已驻留的秒数。
func get_state_time() -> float:
	var m: Variant = get_machine()
	return float(m.get_state_time()) if m != null else 0.0


## 请求所属状态机切换至目标状态。
func change_state(target_state_id: StringName, msg: Dictionary = {}) -> bool:
	var m: Variant = get_machine()
	if m == null:
		return false
	return bool(m.change_state(target_state_id, msg))
#endregion


#region Lifecycle Hooks (Override in Subclasses)
## 进入当前状态时调用。[br]
## [param _prev_state] 前一个状态 ID（首次启动为空 `&""`）。[br]
## [param _msg] 切换状态时附带的上下文参数字典。
func _on_enter(_prev_state: StringName, _msg: Dictionary) -> void:
	pass


## 每渲染帧或逻辑步进时调用。
func _on_update(_delta: float) -> void:
	pass


## 每物理帧步进时调用。
func _on_physics_update(_delta: float) -> void:
	pass


## 离开当前状态切往下一个状态前调用。
func _on_exit(_next_state: StringName) -> void:
	pass


## 处理外部投递给当前状态的语义事件（返回 `true` 表示事件已被消费）。
func _on_event(_event_name: StringName, _payload: Variant = null) -> bool:
	return false


## 转换守卫：判断是否允许从当前状态切往 [param _next_state]（默认允许）。[br]
## 可在霸体动作或死亡终态中重写此方法拦截非法切换。
func _can_transition_to(_next_state: StringName) -> bool:
	return true
#endregion
