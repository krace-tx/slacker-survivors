class_name BaseView
extends Control

## 顶层场景或视图面板的视图根基类（MSVP View Base Class）。[br]
##
## [b]核心职责：[/b][br]
## 1. [b]统一视图生命周期契约[/b]：提供标准的 [method open] / [method close] 及子类钩子 [method _on_open] / [method _on_close]；[br]
## 2. [b]强类型参数透传[/b]：通过 [method get_params] 持有强类型 [BaseParams] 入参契约实例；[br]
## 3. [b]异步生命周期作用域[/b]：内置 [member task_scope]（[TaskScope]），在 [method close] 或节点退树时自动取消悬挂异步任务；[br]
## 4. [b]异形屏安全区与宽高比自适应[/b]：通过 [member apply_safe_area] 与 [member lock_design_aspect] 自动响应视口旋转与缩放重排。

signal opened
signal closed

#region Exports
@export_group("Layout")
## 是否自动适配异形屏安全区（刘海屏 / 灵动岛 / 底部 Home 条）
@export var apply_safe_area: bool = true
## 是否在异形屏/超宽屏安全区内进一步锁定设计宽高比（居中内接，防止固定比例面板被拉宽变形）
@export var lock_design_aspect: bool = false
#endregion

#region State
var _params: BaseParams = null
var _is_opened: bool = false
var _task_scope: TaskScope = null

## 当前视图绑定的异步任务作用域。在 close() 或节点退出树时自动取消未完成任务。
var task_scope: TaskScope:
	get:
		if _task_scope == null or _task_scope.is_disposed():
			_task_scope = TaskScope.new(self, "View:%s" % name, true)
		return _task_scope
#endregion

#region Lifecycle
func _ready() -> void:
	if apply_safe_area:
		_adapt_safe_area()
		var vp := get_viewport()
		if vp != null and not vp.size_changed.is_connected(_adapt_safe_area):
			vp.size_changed.connect(_adapt_safe_area)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_adapt_safe_area):
		vp.size_changed.disconnect(_adapt_safe_area)
	if _task_scope != null:
		_task_scope.cancel_all("View exited tree.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task_scope != null:
		_task_scope.dispose("View freed.")


## 打开/呈现该视图
func open(params: BaseParams = null) -> void:
	_params = params
	visible = true
	_is_opened = true
	_on_open(_params)
	opened.emit()


## 关闭/隐藏该视图
func close() -> void:
	if not _is_opened:
		return
	_is_opened = false
	if _task_scope != null:
		_task_scope.cancel_all("View closed.")
	_on_close()
	visible = false
	closed.emit()


## 当前视图是否处于打开状态
func is_opened() -> bool:
	return _is_opened


## 获取打开时透传的强类型参数契约实例
func get_params() -> BaseParams:
	return _params
#endregion

#region Subclass Hooks
## 视图打开时回调（用于挂载数据、刷新界面）
func _on_open(_params: BaseParams = null) -> void:
	pass


## 视图关闭时回调（用于清理动效、注销本地信号）
func _on_close() -> void:
	pass
#endregion

#region Safe Area
## 适配移动端异形屏与安全区边距（通过 DisplaySystem 执行逆矩阵逻辑像素投影与宽高比防拉伸保护）
func _adapt_safe_area() -> void:
	if apply_safe_area:
		DisplaySystem.adapt_control_safe_area(self, lock_design_aspect)
#endregion
