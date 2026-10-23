class_name FrameworkRuntime
extends RefCounted

## Framework 唯一组合根（Composition Root）与生命周期状态机。[br]
##
## [b]核心职责：[/b][br]
## 1. 委托 [RuntimeManifest] 校验模块依赖有向无环图（DAG）、启动拓扑顺序与实例级契约一致性；[br]
## 2. 按拓扑顺序显式注入构造依赖（Constructor DI），并委托 [RuntimeServiceHost] 统一挂载、初始化与采集启动耗时；[br]
## 3. 维护严格受控的运行时状态机（[enum RuntimeState.Value]），支持信号驱动的并发停机等待；[br]
## 4. 在初始化失败或中途收到退出请求时自动逆序回滚，在退出时按逆序执行优雅关闭协议。

## 当运行时生命周期状态发生跃迁时触发
signal state_changed(new_state: RuntimeState.Value, old_state: RuntimeState.Value)

const _LOG_TAG: String = "Runtime"

#region Public Contract Constants
const MODULE_MANIFEST: Array[Dictionary] = RuntimeManifest.MODULES
#endregion

#region Runtime State
var _app: Node = null
var _logger: BaseFrameworkLogger = null
var _host: RuntimeServiceHost = RuntimeServiceHost.new()
var _state: RuntimeState.Value = RuntimeState.Value.UNINITIALIZED
var _task_scope: TaskScope = null
var _total_boot_ms: int = 0
#endregion


#region State & Diagnostics Queries
func get_state() -> RuntimeState.Value:
	return _state


func get_state_name() -> String:
	return RuntimeState.to_name(_state)


func is_initialized() -> bool:
	return _state == RuntimeState.Value.READY


func get_task_scope() -> TaskScope:
	if _task_scope == null or _task_scope.is_disposed():
		_task_scope = TaskScope.new(null, "FrameworkRuntime", false)
	return _task_scope


func get_diagnostics() -> Dictionary:
	return {
		"state": get_state_name(),
		"initialized": is_initialized(),
		"total_boot_ms": _total_boot_ms,
		"installed_count": _host.get_installed_count(),
		"total_modules": RuntimeManifest.total_steps(),
		"modules": _host.get_boot_metrics(),
		"task_scope": _task_scope.get_diagnostics() if _task_scope != null else {},
	}


## 校验模块依赖有向无环图（DAG）与启动拓扑顺序合法性。
static func validate_dependency_graph() -> Result:
	return RuntimeManifest.validate_dag()
#endregion


#region Lifecycle - Initialize / Rollback / Shutdown
## 按依赖顺序初始化全部 Framework 服务。[br]
## [param on_step] 阶段汇报回调：[code]Callable(step_index: int, total_steps: int, service_key: String)[/code]。
func initialize(app: Node, on_step: Callable = Callable()) -> Result:
	if not is_instance_valid(app):
		return Result.err_code("Core.InvalidOwner", "FrameworkRuntime requires a valid App node.")

	var total := RuntimeManifest.total_steps()
	if _state == RuntimeState.Value.READY:
		if on_step.is_valid():
			on_step.call(total, total, "ready")
		return Result.ok()
	if _state == RuntimeState.Value.INITIALIZING:
		return Result.err_code("Core.AlreadyInitializing", "FrameworkRuntime is currently initializing.")
	if RuntimeState.is_busy(_state):
		return Result.err_code("Core.BusyState", "Cannot initialize while in state %s." % get_state_name())

	var graph_res := validate_dependency_graph()
	if graph_res.is_err():
		_transition_to(RuntimeState.Value.INITIALIZATION_FAILED)
		return graph_res

	_transition_to(RuntimeState.Value.INITIALIZING)
	_total_boot_ms = 0
	var boot_start_msec := Time.get_ticks_msec()

	_app = app
	_logger = null
	_task_scope = TaskScope.new(_app, "FrameworkRuntime", false)
	_host.bind_app(_app, on_step)

	var result := await _assemble_modules_async()
	if result.is_err():
		return await _rollback_async(result)

	_total_boot_ms = Time.get_ticks_msec() - boot_start_msec
	_transition_to(RuntimeState.Value.READY)
	_log_info("Framework runtime ready (%d/%d modules in %d ms)." % [_host.get_installed_count(), total, _total_boot_ms])
	return Result.ok()


## 异步优雅关闭协议：逆序等待支持 `shutdown_async()` 的服务（如 Storage 落盘完成），再统一释放。[br]
## 若当前正在初始化或正在回滚/停机，会请求中止并挂起等待直至进入 [constant RuntimeState.Value.STOPPED]。
func shutdown_async() -> Result:
	if RuntimeState.is_stopped_or_uninitialized(_state):
		return Result.ok()

	if _state == RuntimeState.Value.INITIALIZING:
		_host.request_shutdown()
		await _wait_until_stopped()
		return Result.ok()

	if _state == RuntimeState.Value.ROLLING_BACK or _state == RuntimeState.Value.SHUTTING_DOWN:
		await _wait_until_stopped()
		return Result.ok()

	_transition_to(RuntimeState.Value.SHUTTING_DOWN)
	if _task_scope != null:
		_task_scope.dispose("FrameworkRuntime shutting down.")

	await _host.teardown_async()
	_logger = null
	_app = null
	_transition_to(RuntimeState.Value.STOPPED)
	return Result.ok()


## 同步逆序释放服务，并清空 App 门面，支持节点树退出或测试环境快速重置。
func dispose() -> void:
	if RuntimeState.is_stopped_or_uninitialized(_state):
		return
	if _state == RuntimeState.Value.INITIALIZING:
		_host.request_shutdown()

	_transition_to(RuntimeState.Value.SHUTTING_DOWN)
	if _task_scope != null:
		_task_scope.dispose("FrameworkRuntime disposed.")

	_host.teardown_sync()
	_logger = null
	_app = null
	_transition_to(RuntimeState.Value.STOPPED)
#endregion


#region Explicit Dependency Wiring
func _assemble_modules_async() -> Result:
	# 1. 基础支撑层：Env -> Logger -> Clock -> Asset
	var env := RuntimeEnvironment.new()
	var res := await _host.install(env)
	if res.is_err(): return res

	var logger := FrameworkLogger.new(env)
	res = await _host.install(logger)
	if res.is_err(): return res
	_logger = logger

	var clock := ClockSystem.new()
	res = await _host.install(clock)
	if res.is_err(): return res

	var asset := AssetSystem.new()
	res = await _host.install(asset)
	if res.is_err(): return res

	# 2. 输入与触觉层：Input -> Haptic
	var input := InputSystem.new(logger)
	res = await _host.install(input)
	if res.is_err(): return res

	var haptic := HapticFeedback.new(input)
	res = await _host.install(haptic)
	if res.is_err(): return res

	# 3. 通讯、鉴权、存储与本地化：Network -> Auth -> Storage -> Locale
	var net := NetworkClient.new(logger, env)
	res = await _host.install(net)
	if res.is_err(): return res

	var auth := AuthSystem.new(env, logger, clock, net)
	res = await _host.install(auth)
	if res.is_err(): return res

	var storage := StorageSystem.new(logger, net)
	res = await _host.install(storage)
	if res.is_err(): return res

	var locale := LocalizationSystem.new()
	res = await _host.install(locale)
	if res.is_err(): return res

	# 4. 表现与视听管线：Scene -> Display -> Cursor -> Audio -> Video
	var scene := SceneRouter.new(asset, logger)
	res = await _host.install(scene)
	if res.is_err(): return res

	var display := DisplaySystem.new(logger)
	res = await _host.install(display)
	if res.is_err(): return res

	var cursor := CursorSystem.new(display, input, logger)
	res = await _host.install(cursor)
	if res.is_err(): return res

	var audio := AudioSystem.new(asset, logger)
	res = await _host.install(audio)
	if res.is_err(): return res

	var video := VideoPlayer.new(audio, logger)
	res = await _host.install(video)
	if res.is_err(): return res

	if _host.get_installed_count() != RuntimeManifest.total_steps():
		return Result.err_code(
			"Core.IncompleteAssembly",
			"Installed %d/%d modules." % [_host.get_installed_count(), RuntimeManifest.total_steps()]
		)
	return Result.ok()


func _rollback_async(failure: Result) -> Result:
	_transition_to(RuntimeState.Value.INITIALIZATION_FAILED)
	_log_error("Framework runtime initialization aborted (%s), rolling back..." % failure.error_message())
	_transition_to(RuntimeState.Value.ROLLING_BACK)
	if _task_scope != null:
		_task_scope.dispose("FrameworkRuntime rollback.")
	await _host.teardown_async()
	_logger = null
	_app = null
	_transition_to(RuntimeState.Value.STOPPED)
	return failure
#endregion


#region State Transition & Logging Helpers
func _transition_to(next_state: RuntimeState.Value) -> void:
	if _state == next_state:
		return
	var prev_state := _state
	if not RuntimeState.can_transition(prev_state, next_state):
		_log_warn(
			"Unexpected state transition %s -> %s." % [
				RuntimeState.to_name(prev_state), RuntimeState.to_name(next_state)
			]
		)
	_state = next_state
	state_changed.emit(next_state, prev_state)


func _wait_until_stopped() -> void:
	while not RuntimeState.is_stopped_or_uninitialized(_state):
		await state_changed


func _log_info(message: String) -> void:
	if _logger != null:
		_logger.info(_LOG_TAG, message)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, _LOG_TAG, message)


func _log_warn(message: String) -> void:
	if _logger != null:
		_logger.warn(_LOG_TAG, message)
	else:
		FrameworkLogger.print_raw(LogLevel.WARN, _LOG_TAG, message)


func _log_error(message: String) -> void:
	if _logger != null:
		_logger.error(_LOG_TAG, message)
	else:
		FrameworkLogger.print_raw(LogLevel.ERROR, _LOG_TAG, message)
#endregion
