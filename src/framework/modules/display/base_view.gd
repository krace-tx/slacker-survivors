class_name BaseView
extends Control

## 顶层场景或视图面板的视图根基类（MSVP View Base Class）。[br]
##
## [b]核心职责：[/b][br]
## 1. [b]统一视图生命周期契约[/b]：提供标准的 [method open] / [method close] 及子类钩子 [method _on_open] / [method _on_close]；[br]
## 2. [b]强类型参数透传[/b]：通过 [method get_params] 持有强类型 [BaseParams] 入参契约实例；[br]
## 3. [b]异步生命周期作用域[/b]：内置 [member task_scope]（[TaskScope]），在 [method close] 或节点退树时自动取消悬挂异步任务；[br]
## 4. [b]异形屏安全区与宽高比自适应[/b]：通过 [member safe_area_mode] 三态枚举自动响应视口缩放与全局安全比例重排。

signal opened
signal closed

#region Enums & Exports
## 视图安全区适配策略枚举
enum SafeAreaMode {
	NONE = 0,          ## 不应用安全区（用于模态弹窗 BaseDialog、内嵌子组件、全屏贴边背景/闪屏）
	SAFE_RECT = 1,     ## 适配硬件异形屏与全局安全比例，宽高比自由铺满（用于战斗 HUD、大厅主视图）
	DESIGN_ASPECT = 2, ## 适配安全区并强制居中锁定项目基准设计宽高比（用于固定构图的全屏系统面板）
}

@export_group("Layout")
## 当前视图的安全区适配策略（全局安全区比例统一在 DisplaySystem / GameSettingsModel 中配置）
@export var safe_area_mode: SafeAreaMode = SafeAreaMode.SAFE_RECT
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
	if safe_area_mode != SafeAreaMode.NONE:
		_adapt_safe_area()
		var vp := get_viewport()
		if vp != null and not vp.size_changed.is_connected(_adapt_safe_area):
			vp.size_changed.connect(_adapt_safe_area)
		DisplaySystem.connect_safe_area_changed(_adapt_safe_area)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_adapt_safe_area):
		vp.size_changed.disconnect(_adapt_safe_area)
	DisplaySystem.disconnect_safe_area_changed(_adapt_safe_area)
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
func _on_open(_open_params: BaseParams = null) -> void:
	pass


## 视图关闭时回调（用于清理动效、注销本地信号）
func _on_close() -> void:
	pass
#endregion

#region Safe Area
## 按 safe_area_mode 适配异形屏与全局安全比例边距
func _adapt_safe_area() -> void:
	if safe_area_mode == SafeAreaMode.NONE:
		return
	var lock_aspect: bool = (safe_area_mode == SafeAreaMode.DESIGN_ASPECT)
	DisplaySystem.adapt_control_safe_area(self, lock_aspect)
#endregion
