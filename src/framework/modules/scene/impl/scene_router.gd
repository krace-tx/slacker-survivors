class_name SceneRouter
extends BaseSceneRouter

## 顶层场景路由与栈管理调度器 (Scene Router Facade)。[br]
##
## [b]核心职责与设计哲学（第一性原理）：[/b][br]
## 1. [b]极简门面 API[/b]：对外提供统一路由接口（[method replace] / [method push] / [method pop] / [method bind]）；[br]
## 2. [b]无死锁重入安全队列（Reentrant-Safe Signal Queue）[/b]：基于内部信号票据（[code]_NavTicket[/code]）实现零轮询唤醒；
##    当场景在 [method BaseScene._on_enter] / [method BaseScene._on_resume] 钩子内部重入发起嵌套跳转（Redirect）时，
##    自动接续消费队列，彻底杜绝自等待死锁；[br]
## 3. [b]栈顶精准挂起/恢复路由[/b]：统一监听 [signal EventBus.app_paused] 与 [signal EventBus.app_resumed]，
##    严格仅向当前栈顶活动场景转发，防止栈底休眠场景被错误唤醒；[br]
## 4. [b]显式依赖注入[/b]：底层场景加载与日志均通过注入接口解耦，杜绝反向依赖 App。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"scene"
const REQUIRED_MODULES: Array[StringName] = [&"asset"]
const OPTIONAL_MODULES: Array[StringName] = [&"logger"]
#endregion

#region Inner Types
class _NavTicket extends RefCounted:
	signal completed(result: Result)
	var op: String
	var path: String
	var params: BaseParams
	var transition: int
	var bound_scene: BaseScene
	var done: bool = false
	var result: Result = null

	func _init(
		p_op: String,
		p_path: String,
		p_params: BaseParams,
		p_transition: int,
		p_scene: BaseScene = null
	) -> void:
		op = p_op
		path = p_path
		params = p_params
		transition = p_transition
		bound_scene = p_scene

	func resolve(p_result: Result) -> void:
		if done:
			return
		done = true
		result = p_result
		completed.emit(p_result)
#endregion

#region Private Members
var _asset_system: BaseAssetSystem
var _logger: BaseFrameworkLogger

var _stack: SceneStack
var _transition: SceneTransition
var _active_workers: int = 0
var _nav_version: int = 0
var _pending: Array[_NavTicket] = []
#endregion

#region Lifecycle
func _init(asset_system: BaseAssetSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_asset_system = asset_system
	_logger = logger
	_transition = SceneTransition.new(self)
	_stack = SceneStack.new(self, _transition, _asset_system)


func initialize() -> Result:
	return Result.ok()


func _enter_tree() -> void:
	if Bus != null:
		if not Bus.app_paused.is_connected(_on_app_paused):
			Bus.app_paused.connect(_on_app_paused)
		if not Bus.app_resumed.is_connected(_on_app_resumed):
			Bus.app_resumed.connect(_on_app_resumed)


func _exit_tree() -> void:
	_disconnect_bus()


func dispose() -> void:
	_disconnect_bus()
	for ticket in _pending:
		ticket.resolve(Result.err_code("Scene.Disposed", "SceneRouter was disposed before request could execute."))
	_pending.clear()
	if _stack != null:
		_stack.dispose()
	if _transition != null:
		_transition.dispose()
	if is_inside_tree():
		queue_free()


func set_asset_system(asset_system: BaseAssetSystem) -> void:
	_asset_system = asset_system
	if _stack != null:
		_stack._asset_service = asset_system


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger
#endregion

#region Public API - Status Queries
## 获取当前栈顶场景实例；栈空时为 null
func current() -> BaseScene:
	return _stack.current()


## 获取当前栈顶场景路径；栈空时为空字符串
func current_path() -> String:
	return _stack.current_path()


## 获取当前场景栈深度
func depth() -> int:
	return _stack.depth()


## 场景栈是否为空
func is_empty() -> bool:
	return _stack.is_empty()
#endregion

#region Public API - Scene Operations
## 替换栈顶场景 (Replace)
## 默认采用 Apple/字节 景深缩放交融（0.96x 聚焦推近 + 旧场景 1.03x 散开淡出）
func replace(
	path: String,
	params: BaseParams = null,
	transition: int = SceneTransitionType.AUTO
) -> Result:
	return await _enqueue("replace", path, params, transition)


## 压栈新场景 (Push)
## 默认采用进场淡入覆盖（0.0 -> 1.0）
func push(
	path: String,
	params: BaseParams = null,
	transition: int = SceneTransitionType.AUTO
) -> Result:
	return await _enqueue("push", path, params, transition)


## 出栈当前场景并返回上一级 (Pop)
## 默认采用退场溶解揭开（1.0 -> 0.0）
func pop(
	params: BaseParams = null,
	transition: int = SceneTransitionType.AUTO
) -> Result:
	return await _enqueue("pop", "", params, transition)


## 绑定初始场景（纳入统一串行队列并在完成后广播 Bus.scene_changed）
func bind(path: String, scene: BaseScene, params: BaseParams = null) -> Result:
	return await _enqueue("bind", path, params, SceneTransitionType.NONE, scene)
#endregion

#region Reentrant-Safe Request Queue & Execution
func _enqueue(
	op: String,
	path: String,
	params: BaseParams,
	transition: int,
	bound_scene: BaseScene = null
) -> Result:
	var ticket := _NavTicket.new(op, path, params, transition, bound_scene)
	_pending.append(ticket)

	# 若当前无活动消费者，或当前正处于生命周期钩子（_on_enter / _on_resume）内发起重入跳转，
	# 立即启动队列消费协程，彻底避免钩子内 await App.scene.replace(...) 引发的自等待死锁。
	if _active_workers == 0 or _stack.is_in_lifecycle_hook():
		await _process_queue()

	if not ticket.done:
		await ticket.completed

	return ticket.result


func _process_queue() -> void:
	_active_workers += 1

	while not _pending.is_empty():
		var req: _NavTicket = _pending.pop_front()
		_nav_version += 1
		var exec_version := _nav_version
		var result: Result

		match req.op:
			"replace":
				result = await _stack.replace(req.path, req.params, req.transition)
			"push":
				result = await _stack.push(req.path, req.params, req.transition)
			"pop":
				result = await _stack.pop(req.params, req.transition)
			"bind":
				result = await _stack.bind(req.path, req.bound_scene, req.params)
			_:
				result = Result.err_code("Scene.UnknownOperation", "Unknown scene operation: %s" % req.op)

		if result.is_err():
			_log_error("%s" % result.error)
			if Bus != null:
				Bus.scene_change_failed.emit(req.path)
		elif exec_version == _nav_version:
			var active_path := _stack.current_path()
			_log_info("Now at '%s'." % active_path)
			if Bus != null:
				Bus.scene_changed.emit(active_path)

		req.resolve(result)

	_active_workers -= 1
#endregion

#region App Pause / Resume Top-Scene Forwarding
func _on_app_paused() -> void:
	var top := _stack.current()
	if is_instance_valid(top):
		top._on_pause()


func _on_app_resumed() -> void:
	var top := _stack.current()
	if is_instance_valid(top):
		top._on_resume(null)


func _disconnect_bus() -> void:
	if Bus != null:
		if Bus.app_paused.is_connected(_on_app_paused):
			Bus.app_paused.disconnect(_on_app_paused)
		if Bus.app_resumed.is_connected(_on_app_resumed):
			Bus.app_resumed.disconnect(_on_app_resumed)
#endregion

#region Internal Logging Helpers
func _log_info(message: String) -> void:
	if _logger != null:
		_logger.info("SceneRouter", message)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, "SceneRouter", message)


func _log_error(message: String) -> void:
	if _logger != null:
		_logger.error("SceneRouter", message)
	else:
		FrameworkLogger.print_raw(LogLevel.ERROR, "SceneRouter", message)
#endregion
