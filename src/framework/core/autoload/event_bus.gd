extends Node
## 全局领域事件总线 (Autoload / EventBus)
## 只广播已发生的事实，不承载命令；做事走 App.xxx。
## 1. 框架系统级事实：直接通过内置强类型 signal 订阅（如 Bus.app_paused.connect(...)）；
## 2. 业务跨模块事实：通过动态主题方法订阅与广播（Bus.on / Bus.off / Bus.emit，配合各业务 Service 公开的 EVENT_* 常量）。

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
## 语言已切换。由 LocalizationSystem 发出。
signal locale_changed

## 当前激活输入设备（键鼠 / 手柄）或手柄品牌已切换。由 InputSystem 发出。
signal input_device_changed(device_type: int, joy_brand: int)

## 键位映射配置已变更或重置（[param action] 为空代表批量更新）。由 InputSystem 发出。
signal input_bindings_changed(action: StringName)

## 手柄物理连接状态已变更。由 InputSystem 发出。
signal joypad_connection_changed(device_id: int, connected: bool)
#endregion

#region Scene
## 顶层场景切换完成。由 SceneRouter 发出。[param path] 为 tscn 路径。
signal scene_changed(path: String)

## 顶层场景切换失败。由 SceneRouter 发出。[param path] 为当时请求的路径。
signal scene_change_failed(path: String)
#endregion

#region Dynamic Domain Events (Pub/Sub)
## 最大允许的事件递归触发深度（防止 A -> B -> A 无限递归死循环）
const _MAX_RECURSION_DEPTH: int = 8

## 动态事件订阅表：{ StringName: Array[Callable] }
var _listeners: Dictionary = {}
var _emit_depth: int = 0


## 订阅指定名称的领域事件（幂等：同一 Callable 不会重复订阅）。[br]
## [param event_name] 事件名称（推荐使用各业务 Service 公开的 [code]EVENT_*[/code] `StringName` 常量）。[br]
## [param callback] 回调函数，支持无参 [code]func()[/code] 或单参 [code]func(payload)[/code]。
func on(event_name: StringName, callback: Callable) -> void:
	if event_name.is_empty() or not callback.is_valid():
		return
	if not _listeners.has(event_name):
		_listeners[event_name] = []
	var list: Array = _listeners[event_name]
	if not list.has(callback):
		list.append(callback)


## 绑定宿主节点生命周期的领域事件订阅：当 [param owner_node] 退出场景树（`tree_exiting`）时自动解绑。
func on_scoped(event_name: StringName, owner_node: Node, callback: Callable) -> void:
	if event_name.is_empty() or owner_node == null or not is_instance_valid(owner_node) or not callback.is_valid():
		return
	on(event_name, callback)
	var unbind_fn := func() -> void:
		off(event_name, callback)
	if not owner_node.tree_exiting.is_connected(unbind_fn):
		owner_node.tree_exiting.connect(unbind_fn, CONNECT_ONE_SHOT)


## 取消订阅指定名称的领域事件。
func off(event_name: StringName, callback: Callable) -> void:
	if not _listeners.has(event_name):
		return
	var list: Array = _listeners[event_name]
	list.erase(callback)
	if list.is_empty():
		_listeners.erase(event_name)


## 广播指定名称的领域事件（同步按订阅顺序派发）。[br]
## 自动清理已失效（宿主对象已释放）的回调引用，并根据回调参数签名自适应传递 [param payload]。[br]
## 内置递归深度保护（最大深度 8），防止事件环路引发栈溢出。
func emit(event_name: StringName, payload: Variant = null) -> void:
	if not _listeners.has(event_name):
		return
	if _emit_depth >= _MAX_RECURSION_DEPTH:
		push_error("EventBus: Max event recursion depth (%d) exceeded when emitting '%s'." % [
			_MAX_RECURSION_DEPTH, String(event_name)
		])
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
	_emit_depth += 1
	# 复制快照遍历，防止回调内部调用 on/off 修改原数组导致迭代错位
	for cb in valid_callbacks.duplicate():
		if not cb.is_valid():
			continue
		if cb.get_argument_count() == 0:
			cb.call()
		else:
			cb.call(payload)
	_emit_depth = maxi(0, _emit_depth - 1)


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
