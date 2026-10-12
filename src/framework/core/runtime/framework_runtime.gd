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
func initialize(app: Node) -> Result:
	if not is_instance_valid(app):
		return Result.err_code("Core.InvalidOwner", "FrameworkRuntime requires a valid App node.")
	if _initialized:
		return Result.ok()

	_app = app
	_clear_app_services()

	# 基础服务：没有其它 Framework 依赖。
	var env := RuntimeEnvironment.new()
	var result := await _install_ref("env", env)
	if result.is_err():
		return _rollback(result)

	var log := FrameworkLogger.new(env)
	result = await _install_ref("log", log)
	if result.is_err():
		return _rollback(result)

	var time := TimeSystem.new()
	result = await _install_ref("time", time)
	if result.is_err():
		return _rollback(result)

	var asset := AssetSystem.new()
	result = await _install_ref("asset", asset)
	if result.is_err():
		return _rollback(result)

	var haptic := HapticFeedback.new()
	result = await _install_ref("haptic", haptic)
	if result.is_err():
		return _rollback(result)

	# 节点服务：先挂载，再初始化，确保 _ready 已完成。
	var net := NetworkClient.new()
	result = await _install_node("network", net, "NetworkClient")
	if result.is_err():
		return _rollback(result)

	var storage := StorageSystem.new(log, net)
	result = await _install_ref("storage", storage)
	if result.is_err():
		return _rollback(result)

	var locale := LocalizationSystem.new()
	result = await _install_ref("locale", locale)
	if result.is_err():
		return _rollback(result)

	var scene := SceneRouter.new(asset, log)
	result = await _install_node("scene", scene, "SceneRouter")
	if result.is_err():
		return _rollback(result)

	var ui := UISystem.new(asset, log)
	result = await _install_node("ui", ui, "UISystem")
	if result.is_err():
		return _rollback(result)

	var audio := AudioSystem.new(asset, log)
	result = await _install_node("audio", audio, "AudioSystem")
	if result.is_err():
		return _rollback(result)

	var video := VideoPlayer.new(audio, log)
	result = await _install_node("video", video, "VideoPlayer")
	if result.is_err():
		return _rollback(result)

	_initialized = true
	_log_info("Framework runtime ready.")
	return Result.ok()


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
	if key == "net":
		_app.set("network", service)
	return Result.ok()


func _rollback(failure: Result) -> Result:
	_log_error("Framework runtime failed: %s" % failure.error_message())
	dispose()
	return failure


func _clear_app_services() -> void:
	if not is_instance_valid(_app):
		return
	for key in ["env", "log", "network", "storage", "time", "locale", "asset", "scene", "ui", "audio", "haptic", "video"]:
		_app.set(key, null)


func _log_info(message: String) -> void:
	var log = _app.get("log") if is_instance_valid(_app) else null
	if log is BaseFrameworkLogger:
		log.info("Runtime", message)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, "Runtime", message)


func _log_error(message: String) -> void:
	var log = _app.get("log") if is_instance_valid(_app) else null
	if log is BaseFrameworkLogger:
		log.error("Runtime", message)
	else:
		FrameworkLogger.print_raw(LogLevel.ERROR, "Runtime", message)
