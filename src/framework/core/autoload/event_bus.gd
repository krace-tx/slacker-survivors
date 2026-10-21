extends Node
## 全局领域事件总线 (Autoload / EventBus)
## 只广播已发生的事实，不承载命令；做事走 App.xxx。
## 1. 框架系统级事实：直接通过内置强类型 signal 订阅（如 Bus.app_paused.connect(...)）；
## 2. 业务跨模块事实：通过动态主题方法订阅与广播（Bus.on / Bus.off / Bus.emit，配合 GameEvents 常量）。

@warning_ignore_start("unused_signal") ## 信号按设计在外部 emit/connect

#region App
## 已切后台。由 App 发出。
signal app_paused

## 已回前台。由 App 发出。
signal app_resumed

## 硬件返回键 / 侧滑返回 / ESC 按下。由 App 发出。
signal app_back_pressed
#endregion

#region Service
## 语言已切换。由 LocaleService 发出。
signal locale_changed
#endregion

#region Scene
## 顶层场景切换完成。由 SceneService 发出。[param path] 为 tscn 路径。
signal scene_changed(path: String)

## 顶层场景切换失败。由 SceneService 发出。[param path] 为当时请求的路径。
signal scene_change_failed(path: String)
#endregion

#region Dynamic Domain Events (Pub/Sub)
## 动态事件订阅表：{ StringName: Array[Callable] }
var _listeners: Dictionary = {}


## 订阅指定名称的领域事件。[br]
## [param event_name] 事件名称（推荐使用 [GameEvents] 常量）。[br]
## [param callback] 回调函数，支持无参 [code]func()[/code] 或单参 [code]func(payload)[/code]。
func on(event_name: StringName, callback: Callable) -> void:
	if event_name.is_empty() or not callback.is_valid():
		return
	if not _listeners.has(event_name):
		_listeners[event_name] = []
	var list: Array = _listeners[event_name]
	if not list.has(callback):
		list.append(callback)


## 取消订阅指定名称的领域事件。
func off(event_name: StringName, callback: Callable) -> void:
	if not _listeners.has(event_name):
		return
	var list: Array = _listeners[event_name]
	list.erase(callback)
	if list.is_empty():
		_listeners.erase(event_name)


## 广播指定名称的领域事件。[br]
## 自动清理已失效（宿主对象已释放）的回调引用，并根据回调参数签名自适应传递 [param payload]。
func emit(event_name: StringName, payload: Variant = null) -> void:
	if not _listeners.has(event_name):
		return
	var list: Array = _listeners[event_name]
	var valid_callbacks: Array[Callable] = []
	for item in list:
		var cb: Callable = item as Callable
		if cb.is_valid():
			valid_callbacks.append(cb)

	if valid_callbacks.is_empty():
		_listeners.erase(event_name)
		return

	_listeners[event_name] = valid_callbacks
	# 复制快照遍历，防止回调内部调用 on/off 修改原数组导致迭代错位
	for cb in valid_callbacks.duplicate():
		if not cb.is_valid():
			continue
		if cb.get_argument_count() == 0:
			cb.call()
		else:
			cb.call(payload)


## 查询指定领域事件当前是否有活跃订阅者。
func has_listeners(event_name: StringName) -> bool:
	if not _listeners.has(event_name):
		return false
	var list: Array = _listeners[event_name]
	return list.any(func(cb: Callable) -> bool: return cb.is_valid())


## 清理指定事件（若为空则清理全部动态事件订阅）。
func clear(event_name: StringName = &"") -> void:
	if event_name.is_empty():
		_listeners.clear()
	else:
		_listeners.erase(event_name)
#endregion
