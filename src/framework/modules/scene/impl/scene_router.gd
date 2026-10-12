class_name SceneRouter
extends BaseSceneRouter

## 顶层场景路由与栈管理调度器 (Scene Router Facade)。
## 
## [b]核心职责与设计哲学：[/b]
## 1. [b]极简门面 API[/b]：对外提供一目了然的场景路由接口（[method replace] / [method push] / [method pop] / [method bind]）；
## 2. [b]苹果/字节级流式交互[/b]：摒弃黑屏/遮罩掩耳盗铃，默认智能匹配视差侧滑与景深弹性缩放；
## 3. [b]串行防重入请求队列调度[/b]：防手速连点导致的场景栈错乱与内存撕裂；
## 4. [b]事件解耦广播[/b]：在场景流转完成后广播全局 [signal EventBus.scene_changed] 事件；
## 5. [b]显式依赖注入[/b]：底层场景加载与日志均通过注入接口解耦，杜绝反向依赖 App。



#region Private Members
var _asset_system: BaseAssetSystem
var _logger: BaseFrameworkLogger

var _stack: SceneStack
var _transition: SceneTransition
var _switching: bool = false
var _pending: Array[Dictionary] = []
#endregion

#region Lifecycle
func _init(asset_system: BaseAssetSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_asset_system = asset_system
	_logger = logger
	_transition = SceneTransition.new(self)
	_stack = SceneStack.new(self, _transition, _asset_system)


func initialize() -> Result:
	return Result.ok()


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


## 获取当前场景栈深度
func depth() -> int:
	return _stack.depth()


## 场景栈是否为空
func is_empty() -> bool:
	return _stack.is_empty()
#endregion

#region Public API - Scene Operations
## 替换栈顶场景 (Replace)
## 默认采用 Apple/字节 景深缩放交融（0.95x 弹性推近 + 旧场景 1.04x 散开淡出）
func replace(
	path: String,
	params: Dictionary = {},
	transition: int = SceneTransitionType.AUTO
) -> Result:
	return await _enqueue("replace", path, params, transition)


## 压栈新场景 (Push)
## 默认采用移动端原生视差侧滑（新场景右入，旧场景左移 25% 且附带 30% 遮罩）
func push(
	path: String,
	params: Dictionary = {},
	transition: int = SceneTransitionType.AUTO
) -> Result:
	return await _enqueue("push", path, params, transition)


## 出栈当前场景并返回上一级 (Pop)
## 默认采用与 Push 对称的逆向侧滑恢复
func pop(
	params: Dictionary = {},
	transition: int = SceneTransitionType.AUTO
) -> Result:
	return await _enqueue("pop", "", params, transition)


## 绑定初始场景（在启动引导期将主树现有活动节点收拢为受栈管制的场景根）
func bind(path: String, scene: BaseScene, params: Dictionary = {}) -> Result:
	return await _stack.bind(path, scene, params)
#endregion

#region Request Queue & Execution
func _enqueue(
	op: String,
	path: String,
	params: Dictionary,
	transition: int
) -> Result:
	var request := {
		"op": op,
		"path": path,
		"params": params,
		"transition": transition,
		"done": false,
		"result": null,
	}
	_pending.append(request)
	if not _switching:
		await _process_queue()
	else:
		await _wait_for_request(request)
	return request["result"] as Result


func _process_queue() -> void:
	_switching = true

	while not _pending.is_empty():
		var req: Dictionary = _pending.pop_front()

		var trans_type: int = req.transition
		var result: Result
		match req.op:
			"replace":
				result = await _stack.replace(req.path, req.params, trans_type)
			"push":
				result = await _stack.push(req.path, req.params, trans_type)
			"pop":
				result = await _stack.pop(req.params, trans_type)
			_:
				result = Result.err_code("Scene.UnknownOperation", "Unknown scene op: %s" % req.op)

		# 广播切场结果
		if result.is_err():
			_log_error("%s" % result.error)
			Bus.scene_change_failed.emit(req.path)
		else:
			var current_path := _stack.current_path()
			_log_info("Now at '%s'." % current_path)
			Bus.scene_changed.emit(current_path)
		req["result"] = result
		req["done"] = true

	_switching = false


func _wait_for_request(request: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		request["result"] = Result.err_code("Scene.NoTree", "SceneTree is unavailable.")
		request["done"] = true
		return
	while not request["done"]:
		await tree.process_frame
#endregion

#region Internal Logging Helpers
func _log_info(message: String) -> void:
	if _logger != null:
		_logger.info("SceneRouter", message)
	else:
		print("[SceneRouter] %s" % message)


func _log_error(message: String) -> void:
	if _logger != null:
		_logger.error("SceneRouter", message)
	else:
		push_error("[SceneRouter] %s" % message)
#endregion
