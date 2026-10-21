class_name BaseScene
extends Node

## 顶层场景门面基类。[br]
## 规范定义 4 大场景生命周期钩子：[method _on_enter] / [method _on_exit] / [method _on_pause] / [method _on_resume]。[br]
## 内置绑定场景生命周期的 [member task_scope]（[TaskScope]），在场景退栈或销毁时自动取消悬挂异步任务。[br]
## [b]注意：[/b]应用切后台/回前台（[signal EventBus.app_paused] / [signal EventBus.app_resumed]）由 [SceneRouter]
## 严格仅向当前栈顶激活场景转发，栈底休眠场景不会被错误唤醒。

#region Task Lifecycle Scope
var _task_scope: TaskScope = null

## 当前场景绑定的异步任务作用域。场景退出或销毁时自动取消所有未完成任务。
var task_scope: TaskScope:
	get:
		if _task_scope == null or _task_scope.is_disposed():
			_task_scope = TaskScope.new(self, "Scene:%s" % get_class(), true)
		return _task_scope
#endregion


#region Lifecycle
func _enter_tree() -> void:
	if _task_scope == null or _task_scope.is_disposed():
		_task_scope = TaskScope.new(self, "Scene:%s" % get_class(), true)


func _exit_tree() -> void:
	if _task_scope != null:
		_task_scope.cancel_all("Scene exited tree.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task_scope != null:
		_task_scope.dispose("Scene freed.")


## 主动取消当前场景作用域下的所有异步任务（由 SceneStack 在退栈时或业务层按需调用）。
func cancel_tasks(reason: String = "Scene tasks cancelled.") -> void:
	if _task_scope != null:
		_task_scope.cancel_all(reason)
#endregion


#region Scene Hooks
## 1. 进入：新实例入树成为栈顶时调用。[param _params] 为强类型 [BaseParams] 派生契约实例（无参时为 null）。
func _on_enter(_params: BaseParams = null) -> void:
	pass


## 2. 退出：场景转场结束、即将从场景树销毁退栈时调用。
func _on_exit() -> void:
	pass


## 3. 暂停：被新场景 push 压入栈底，或处于栈顶时应用切后台 (Bus.app_paused) 时调用。
func _on_pause() -> void:
	pass


## 4. 恢复：上层场景 pop 离开重回栈顶，或处于栈顶时应用切回前台 (Bus.app_resumed) 时调用。[param _params] 为回传的 [BaseParams] 实例（无参时为 null）。
func _on_resume(_params: BaseParams = null) -> void:
	pass
#endregion
