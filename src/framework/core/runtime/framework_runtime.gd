class_name FrameworkRuntime
extends RefCounted

## Framework 唯一组合根（Composition Root）与生命周期状态机。
##
## Runtime 负责四件事：
## 1. 委托 [RuntimeManifest] 校验模块依赖有向无环图（DAG）与拓扑初始化顺序；
## 2. 按依赖顺序创建服务、显式注入依赖，并委托 [RuntimeServiceHost] 挂载与采集启动耗时；
## 3. 维护运行时状态机（[enum RuntimeState.Value]）；
## 4. 在初始化失败时自动逆序回滚，在退出时按逆序执行优雅关闭协议。

#region Public Contract Constants
const MODULE_MANIFEST: Array[Dictionary] = RuntimeManifest.MODULES
#endregion

#region Runtime State
var _app: Node = null
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
		"modules": _host.get_boot_metrics(),
		"task_scope": _task_scope.get_diagnostics() if _task_scope != null else {},
	}


## 校验模块依赖有向无环图（DAG）与启动拓扑顺序合法性。
static func validate_dependency_graph() -> Result:
	return RuntimeManifest.validate_dag()
#endregion


#region Lifecycle - Initialize / Rollback / Shutdown
## 按依赖顺序初始化全部 Framework 服务。
## [param on_step] 阶段汇报回调: Callable(step_index: int, total_steps: int, service_key: String)
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
	if _state == RuntimeState.Value.SHUTTING_DOWN or _state == RuntimeState.Value.ROLLING_BACK:
		return Result.err_code("Core.BusyState", "Cannot initialize while in state %s." % get_state_name())

	var graph_res := validate_dependency_graph()
	if graph_res.is_err():
		_state = RuntimeState.Value.INITIALIZATION_FAILED
		return graph_res

	_state = RuntimeState.Value.INITIALIZING
	_total_boot_ms = 0
	var boot_start_msec := Time.get_ticks_msec()

	_app = app
	_task_scope = TaskScope.new(_app, "FrameworkRuntime", false)
	_host.bind_app(_app)

	var result := await _assemble_modules_async(total, on_step)
	if result.is_err():
		return await _rollback_async(result)

	_total_boot_ms = Time.get_ticks_msec() - boot_start_msec
	_state = RuntimeState.Value.READY
	_log_info("Framework runtime ready in %d ms." % _total_boot_ms)
	return Result.ok()


## 异步优雅关闭协议：逆序等待支持 `shutdown_async()` 的服务（如 Storage 落盘完成），再统一释放。
func shutdown_async() -> Result:
	if _state == RuntimeState.Value.STOPPED or _state == RuntimeState.Value.UNINITIALIZED:
		return Result.ok()
	if _state == RuntimeState.Value.SHUTTING_DOWN or _state == RuntimeState.Value.ROLLING_BACK:
		return Result.ok()
	if _state == RuntimeState.Value.INITIALIZING:
		_host.request_shutdown()
		return Result.ok()

	_state = RuntimeState.Value.SHUTTING_DOWN
	if _task_scope != null:
		_task_scope.dispose("FrameworkRuntime shutting down.")

	await _host.teardown_async()
	_app = null
	_state = RuntimeState.Value.STOPPED
	return Result.ok()


## 同步逆序释放服务，并清空 App 门面，支持重启或测试环境重复初始化。
func dispose() -> void:
	if _state == RuntimeState.Value.STOPPED or _state == RuntimeState.Value.UNINITIALIZED:
		return
	if _state == RuntimeState.Value.INITIALIZING:
		_host.request_shutdown()

	_state = RuntimeState.Value.SHUTTING_DOWN
	if _task_scope != null:
		_task_scope.dispose("FrameworkRuntime disposed.")

	_host.teardown_sync()
	_app = null
	_state = RuntimeState.Value.STOPPED
#endregion


#region Explicit Dependency Wiring
func _assemble_modules_async(total: int, on_step: Callable) -> Result:
	# 1. Env -> 2. Logger -> 3. Clock -> 4. Asset
	var env := RuntimeEnvironment.new()
	var res := await _host.install_ref("env", env, 1, total, on_step)
	if res.is_err(): return res

	var logger := FrameworkLogger.new(env)
	res = await _host.install_ref("logger", logger, 2, total, on_step)
	if res.is_err(): return res

	var clock := ClockSystem.new()
	res = await _host.install_ref("clock", clock, 3, total, on_step)
	if res.is_err(): return res

	var asset := AssetSystem.new()
	res = await _host.install_ref("asset", asset, 4, total, on_step)
	if res.is_err(): return res

	# 5. Input -> 6. Haptic
	var input := InputSystem.new(logger)
	res = await _host.install_node("input", input, "InputSystem", 5, total, on_step)
	if res.is_err(): return res

	var haptic := HapticFeedback.new(input)
	res = await _host.install_ref("haptic", haptic, 6, total, on_step)
	if res.is_err(): return res

	# 7. Network -> 8. Auth -> 9. Storage -> 10. Locale
	var net := NetworkClient.new(logger, env)
	res = await _host.install_node("net", net, "NetworkClient", 7, total, on_step)
	if res.is_err(): return res

	var auth := AuthSystem.new(env, logger, clock, net)
	res = await _host.install_ref("auth", auth, 8, total, on_step)
	if res.is_err(): return res

	var storage := StorageSystem.new(logger, net)
	res = await _host.install_ref("storage", storage, 9, total, on_step)
	if res.is_err(): return res

	var locale := LocalizationSystem.new()
	res = await _host.install_ref("locale", locale, 10, total, on_step)
	if res.is_err(): return res

	# 11. Scene -> 12. Display -> 13. Audio -> 14. Video
	var scene := SceneRouter.new(asset, logger)
	res = await _host.install_node("scene", scene, "SceneRouter", 11, total, on_step)
	if res.is_err(): return res

	var display := DisplaySystem.new(logger)
	res = await _host.install_node("display", display, "DisplaySystem", 12, total, on_step)
	if res.is_err(): return res

	var audio := AudioSystem.new(asset, logger)
	res = await _host.install_node("audio", audio, "AudioSystem", 13, total, on_step)
	if res.is_err(): return res

	var video := VideoPlayer.new(audio, logger)
	res = await _host.install_node("video", video, "VideoPlayer", 14, total, on_step)
	if res.is_err(): return res

	return Result.ok()


func _rollback_async(failure: Result) -> Result:
	_state = RuntimeState.Value.INITIALIZATION_FAILED
	_log_error("Framework runtime initialization failed (%s), rolling back..." % failure.error_message())
	_state = RuntimeState.Value.ROLLING_BACK
	if _task_scope != null:
		_task_scope.dispose("FrameworkRuntime rollback.")
	await _host.teardown_async()
	_app = null
	_state = RuntimeState.Value.STOPPED
	return failure


func _log_info(message: String) -> void:
	var logger = _app.get("logger") if is_instance_valid(_app) else null
	if logger is BaseFrameworkLogger:
		logger.info("Runtime", message)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, "Runtime", message)


func _log_error(message: String) -> void:
	var logger = _app.get("logger") if is_instance_valid(_app) else null
	if logger is BaseFrameworkLogger:
		logger.error("Runtime", message)
	else:
		FrameworkLogger.print_raw(LogLevel.ERROR, "Runtime", message)
#endregion
