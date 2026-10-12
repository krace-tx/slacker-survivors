class_name FrameworkRuntime
extends RefCounted

## Framework 唯一组合根。
##
## Runtime 只负责三件事：按依赖顺序创建服务、把服务挂到 App、在失败时回滚。
## 业务代码不参与装配，也不需要知道具体实现类；App 只暴露已经完成初始化的门面。

var _app: Node
var _owned_services: Array = []
var _initialized := false


## 按依赖顺序初始化全部 Framework 服务。
## 依赖关系固定在这里，服务实现本身不反向读取 App。
## [param on_step] 阶段汇报回调: Callable(step_index: int, total_steps: int, service_key: String)
func initialize(app: Node, on_step: Callable = Callable()) -> Result:
	if not is_instance_valid(app):
		return Result.err_code("Core.InvalidOwner", "FrameworkRuntime requires a valid App node.")
	if _initialized:
		if on_step.is_valid():
			on_step.call(12, 12, "ready")
		return Result.ok()

	_app = app
	_clear_app_services()

	const TOTAL_STEPS: int = 12

	# 基础服务：没有其它 Framework 依赖。
	var env := RuntimeEnvironment.new()
	var result := await _install_ref("env", env)
	if result.is_err():
		return _rollback(result)
	_notify_step(1, TOTAL_STEPS, "env", on_step)

	var logger := FrameworkLogger.new(env)
	result = await _install_ref("logger", logger)
	if result.is_err():
		return _rollback(result)
	_notify_step(2, TOTAL_STEPS, "logger", on_step)

	var time := TimeSystem.new()
	result = await _install_ref("time", time)
	if result.is_err():
		return _rollback(result)
	_notify_step(3, TOTAL_STEPS, "time", on_step)

	var asset := AssetSystem.new()
	result = await _install_ref("asset", asset)
	if result.is_err():
		return _rollback(result)
	_notify_step(4, TOTAL_STEPS, "asset", on_step)

	var haptic := HapticFeedback.new()
	result = await _install_ref("haptic", haptic)
	if result.is_err():
		return _rollback(result)
	_notify_step(5, TOTAL_STEPS, "haptic", on_step)

	# 节点服务：先挂载，再初始化，确保 _ready 已完成。
	var net := NetworkClient.new()
	result = await _install_node("net", net, "NetworkClient")
	if result.is_err():
		return _rollback(result)
	_notify_step(6, TOTAL_STEPS, "net", on_step)

	var storage := StorageSystem.new(logger, net)
	result = await _install_ref("storage", storage)
	if result.is_err():
		return _rollback(result)
	_notify_step(7, TOTAL_STEPS, "storage", on_step)

	var locale := LocalizationSystem.new()
	result = await _install_ref("locale", locale)
	if result.is_err():
		return _rollback(result)
	_notify_step(8, TOTAL_STEPS, "locale", on_step)

	var scene := SceneRouter.new(asset, logger)
	result = await _install_node("scene", scene, "SceneRouter")
	if result.is_err():
		return _rollback(result)
	_notify_step(9, TOTAL_STEPS, "scene", on_step)

	var ui := UISystem.new(asset, logger)
	result = await _install_node("ui", ui, "UISystem")
	if result.is_err():
		return _rollback(result)
	_notify_step(10, TOTAL_STEPS, "ui", on_step)

	var audio := AudioSystem.new(asset, logger)
	result = await _install_node("audio", audio, "AudioSystem")
	if result.is_err():
		return _rollback(result)
	_notify_step(11, TOTAL_STEPS, "audio", on_step)

	var video := VideoPlayer.new(audio, logger)
	result = await _install_node("video", video, "VideoPlayer")
	if result.is_err():
		return _rollback(result)
	_notify_step(12, TOTAL_STEPS, "video", on_step)

	_initialized = true
	_log_info("Framework runtime ready.")
	return Result.ok()


func _notify_step(step_idx: int, total_steps: int, key: String, callback: Callable) -> void:
	if callback.is_valid():
		callback.call(step_idx, total_steps, key)


## 逆序释放子系统，并清空 App 门面，支持重启或测试环境重复初始化。
func dispose() -> void:
	for i in range(_owned_services.size() - 1, -1, -1):
		var service = _owned_services[i]
		if service == null or not is_instance_valid(service):
			continue
		if service.has_method("dispose"):
			service.dispose()
	_owned_services.clear()
	_clear_app_services()
	_initialized = false
	_app = null


func is_initialized() -> bool:
	return _initialized


func _install_ref(key: String, service: RefCounted) -> Result:
	_owned_services.append(service)
	var result: Result = await service.initialize() if service.has_method("initialize") else Result.ok()
	if result.is_err():
		return Result.err_code("Core.SubsystemInitFailed", "%s: %s" % [key, result.error_message()])
	_app.set(key, service)
	return Result.ok()


func _install_node(key: String, service: Node, node_name: String) -> Result:
	var mount_result := NodeUtils.mount(service, _app, node_name)
	if mount_result.is_err():
		return Result.err_code("Core.SubsystemMountFailed", "%s: %s" % [key, mount_result.error_message()])
	_owned_services.append(service)
	var result: Result = await service.initialize() if service.has_method("initialize") else Result.ok()
	if result.is_err():
		return Result.err_code("Core.SubsystemInitFailed", "%s: %s" % [key, result.error_message()])
	_app.set(key, service)
	return Result.ok()


func _rollback(failure: Result) -> Result:
	_log_error("Framework runtime failed: %s" % failure.error_message())
	dispose()
	return failure


func _clear_app_services() -> void:
	if not is_instance_valid(_app):
		return
	for key in ["env", "logger", "net", "storage", "time", "locale", "asset", "scene", "ui", "audio", "haptic", "video"]:
		_app.set(key, null)


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
