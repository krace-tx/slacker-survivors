class_name RuntimeServiceHost
extends RefCounted

## FrameworkRuntime 服务装配宿主与逆序销毁器。
##
## 负责具体服务（RefCounted 与 Node 形态）的安装、场景树挂载、initialize() 调用、
## 启动耗时指标采集，以及回滚/关闭时的逆序优雅停机与 App 属性清理。

#region Internal State
var _app: Node = null
var _owned_services: Array = []
var _boot_metrics: Dictionary = {}
var _shutdown_requested: bool = false
#endregion


#region Setup & State
func bind_app(app: Node) -> void:
	_app = app
	_owned_services.clear()
	_boot_metrics.clear()
	_shutdown_requested = false
	clear_app_services()


func request_shutdown() -> void:
	_shutdown_requested = true


func is_shutdown_requested() -> bool:
	return _shutdown_requested


func get_boot_metrics() -> Dictionary:
	return _boot_metrics.duplicate(true)
#endregion


#region Service Installation
## 安装 RefCounted 纯逻辑服务并绑定到 App 门面属性。
func install_ref(
	key: String,
	service: RefCounted,
	step_idx: int,
	total_steps: int,
	on_step: Callable = Callable()
) -> Result:
	if _shutdown_requested:
		return Result.err_code("Core.ShutdownRequested", "Shutdown requested during initialization before '%s'." % key)
	var step_start := Time.get_ticks_msec()
	_owned_services.append(service)
	var result: Result = await service.initialize() if service.has_method("initialize") else Result.ok()
	var cost_ms := Time.get_ticks_msec() - step_start
	if result.is_err():
		_boot_metrics[key] = {"status": "failed", "duration_ms": cost_ms, "error": result.error_message()}
		return Result.err_code("Core.SubsystemInitFailed", "%s: %s" % [key, result.error_message()])
	_boot_metrics[key] = {"status": "ready", "duration_ms": cost_ms}
	_app.set(key, service)
	_notify_step(step_idx, total_steps, key, on_step)
	return Result.ok()


## 挂载 Node 形态服务到 App 节点下，执行 initialize() 并绑定到 App 门面属性。
func install_node(
	key: String,
	service: Node,
	node_name: String,
	step_idx: int,
	total_steps: int,
	on_step: Callable = Callable()
) -> Result:
	if _shutdown_requested:
		return Result.err_code("Core.ShutdownRequested", "Shutdown requested during initialization before '%s'." % key)
	var step_start := Time.get_ticks_msec()
	var mount_result := NodeUtils.mount(service, _app, node_name)
	if mount_result.is_err():
		var fail_ms := Time.get_ticks_msec() - step_start
		_boot_metrics[key] = {"status": "mount_failed", "duration_ms": fail_ms, "error": mount_result.error_message()}
		return Result.err_code("Core.SubsystemMountFailed", "%s: %s" % [key, mount_result.error_message()])
	_owned_services.append(service)
	var result: Result = await service.initialize() if service.has_method("initialize") else Result.ok()
	var cost_ms := Time.get_ticks_msec() - step_start
	if result.is_err():
		_boot_metrics[key] = {"status": "failed", "duration_ms": cost_ms, "error": result.error_message()}
		return Result.err_code("Core.SubsystemInitFailed", "%s: %s" % [key, result.error_message()])
	_boot_metrics[key] = {"status": "ready", "duration_ms": cost_ms}
	_app.set(key, service)
	_notify_step(step_idx, total_steps, key, on_step)
	return Result.ok()
#endregion


#region Reverse-Order Teardown
## 异步逆序停止并释放所有已安装服务（等待 shutdown_async 完成后再调用 dispose 与 queue_free）。
func teardown_async() -> void:
	for i in range(_owned_services.size() - 1, -1, -1):
		var service = _owned_services[i]
		if service == null or not is_instance_valid(service):
			continue
		if service.has_method("shutdown_async"):
			await service.shutdown_async()
		if service.has_method("dispose"):
			service.dispose()
		if service is Node and is_instance_valid(service) and (service as Node).is_inside_tree():
			(service as Node).queue_free()
	_owned_services.clear()
	clear_app_services()
	_app = null


## 同步逆序释放所有已安装服务。
func teardown_sync() -> void:
	for i in range(_owned_services.size() - 1, -1, -1):
		var service = _owned_services[i]
		if service == null or not is_instance_valid(service):
			continue
		if service.has_method("dispose"):
			service.dispose()
		if service is Node and is_instance_valid(service) and (service as Node).is_inside_tree():
			(service as Node).queue_free()
	_owned_services.clear()
	clear_app_services()
	_app = null


## 清空 App 聚合根上的全部模块门面引用。
func clear_app_services() -> void:
	if not is_instance_valid(_app):
		return
	for entry: Dictionary in RuntimeManifest.MODULES:
		var key := String(entry["id"])
		_app.set(key, null)
#endregion


#region Helpers
func _notify_step(step_idx: int, total_steps: int, key: String, callback: Callable) -> void:
	if callback.is_valid():
		callback.call(step_idx, total_steps, key)
#endregion
