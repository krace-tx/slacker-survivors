class_name RuntimeServiceHost
extends RefCounted

## FrameworkRuntime 服务装配宿主与逆序销毁器。
##
## 负责具体服务（RefCounted 与 Node 形态）的拓扑契约核对、场景树挂载、`initialize()` 调用、
## 启动耗时指标采集，以及回滚/关闭时的逆序优雅停机与 App 属性清理。

#region Internal State
var _app: Node = null
var _on_step: Callable = Callable()
var _step_cursor: int = 0
var _total_steps: int = 0
var _owned_services: Array[Object] = []
var _owned_keys: Array[String] = []
var _boot_metrics: Dictionary = {}
var _shutdown_requested: bool = false
#endregion


#region Setup & State
func bind_app(app: Node, on_step: Callable = Callable()) -> void:
	_app = app
	_on_step = on_step
	_step_cursor = 0
	_total_steps = RuntimeManifest.total_steps()
	_owned_services.clear()
	_owned_keys.clear()
	_boot_metrics.clear()
	_shutdown_requested = false
	clear_app_services()


func request_shutdown() -> void:
	_shutdown_requested = true


func is_shutdown_requested() -> bool:
	return _shutdown_requested


func get_installed_count() -> int:
	return _owned_services.size()


func get_boot_metrics() -> Dictionary:
	return _boot_metrics.duplicate(true)
#endregion


#region Service Installation
## 按 [RuntimeManifest] 拓扑顺序自动核对契约、安装服务（自动识别 Node / RefCounted）并绑定到 App 门面。
func install(service: Object, custom_node_name: String = "") -> Result:
	var contract_res := RuntimeManifest.verify_step_contract(_step_cursor, service)
	if contract_res.is_err():
		return contract_res
	var entry: Dictionary = RuntimeManifest.get_entry(_step_cursor)
	var key := String(entry["id"])
	_step_cursor += 1
	return await _install_internal(key, service, _step_cursor, _total_steps, _on_step, custom_node_name)


## 安装 RefCounted 纯逻辑服务并绑定到 App 门面属性。
func install_ref(
	key: String,
	service: RefCounted,
	step_idx: int,
	total_steps: int,
	on_step: Callable = Callable()
) -> Result:
	return await _install_internal(key, service, step_idx, total_steps, on_step, "")


## 挂载 Node 形态服务到 App 节点下，执行 initialize() 并绑定到 App 门面属性。
func install_node(
	key: String,
	service: Node,
	node_name: String,
	step_idx: int,
	total_steps: int,
	on_step: Callable = Callable()
) -> Result:
	return await _install_internal(key, service, step_idx, total_steps, on_step, node_name)
#endregion


#region Reverse-Order Teardown
## 异步逆序停止并释放所有已安装服务（等待 shutdown_async 完成后再调用 dispose 与 queue_free）。
func teardown_async() -> void:
	for i in range(_owned_services.size() - 1, -1, -1):
		var service: Object = _owned_services[i]
		if service == null or not is_instance_valid(service):
			continue
		if service.has_method("shutdown_async"):
			await service.shutdown_async()
		_dispose_service_at(i)
	_finalize_teardown()


## 同步逆序释放所有已安装服务。
func teardown_sync() -> void:
	for i in range(_owned_services.size() - 1, -1, -1):
		_dispose_service_at(i)
	_finalize_teardown()


## 清空 App 聚合根上的全部模块门面引用。
func clear_app_services() -> void:
	if not is_instance_valid(_app):
		return
	for entry: Dictionary in RuntimeManifest.MODULES:
		var key := String(entry["id"])
		_app.set(key, null)
#endregion


#region Internal Helpers
func _install_internal(
	key: String,
	service: Object,
	step_idx: int,
	total_steps: int,
	on_step: Callable,
	custom_node_name: String
) -> Result:
	if _shutdown_requested:
		return Result.err_code("Core.ShutdownRequested", "Shutdown requested before installing '%s'." % key)

	var step_start := Time.get_ticks_msec()
	var is_node_service := service is Node
	if is_node_service:
		var resolved_name := _resolve_node_name(service as Node, key, custom_node_name)
		var mount_result := NodeUtils.mount(service as Node, _app, resolved_name)
		if mount_result.is_err():
			var fail_ms := Time.get_ticks_msec() - step_start
			_boot_metrics[key] = {
				"status": "mount_failed",
				"step": step_idx,
				"kind": "Node",
				"duration_ms": fail_ms,
				"error": mount_result.error_message(),
			}
			return Result.err_code("Core.SubsystemMountFailed", "%s: %s" % [key, mount_result.error_message()])

	_owned_services.append(service)
	_owned_keys.append(key)

	var result: Result = await service.initialize() if service.has_method("initialize") else Result.ok()
	var cost_ms := Time.get_ticks_msec() - step_start
	var kind_label := "Node" if is_node_service else "RefCounted"

	if result.is_err():
		_boot_metrics[key] = {
			"status": "failed",
			"step": step_idx,
			"kind": kind_label,
			"duration_ms": cost_ms,
			"error": result.error_message(),
		}
		return Result.err_code("Core.SubsystemInitFailed", "%s: %s" % [key, result.error_message()])

	if _shutdown_requested:
		_boot_metrics[key] = {
			"status": "aborted",
			"step": step_idx,
			"kind": kind_label,
			"duration_ms": cost_ms,
		}
		return Result.err_code("Core.ShutdownRequested", "Shutdown requested while initializing '%s'." % key)

	_boot_metrics[key] = {
		"status": "ready",
		"step": step_idx,
		"kind": kind_label,
		"duration_ms": cost_ms,
	}
	if is_instance_valid(_app):
		_app.set(key, service)
	_notify_step(step_idx, total_steps, key, on_step)
	return Result.ok()


func _dispose_service_at(index: int) -> void:
	var key: String = _owned_keys[index] if index >= 0 and index < _owned_keys.size() else ""
	if not key.is_empty() and is_instance_valid(_app):
		_app.set(key, null)

	var service: Object = _owned_services[index]
	if service == null or not is_instance_valid(service):
		return
	if service.has_method("dispose"):
		service.dispose()
	if service is Node and is_instance_valid(service) and (service as Node).is_inside_tree():
		(service as Node).queue_free()


func _finalize_teardown() -> void:
	_owned_services.clear()
	_owned_keys.clear()
	_step_cursor = 0
	clear_app_services()
	_on_step = Callable()
	_app = null


func _resolve_node_name(node: Node, fallback_key: String, custom_node_name: String) -> String:
	if not custom_node_name.is_empty():
		return custom_node_name
	var script: Script = node.get_script() as Script
	if script != null:
		var global_name := script.get_global_name()
		if not global_name.is_empty():
			return global_name
	return fallback_key.capitalize()


func _notify_step(step_idx: int, total_steps: int, key: String, callback: Callable) -> void:
	if callback.is_valid():
		callback.call(step_idx, total_steps, key)
#endregion
