class_name StorageDemoPresenter
extends RefCounted

## 存档加密演练场 Presenter 协调器（`src/test/storage/presenter/`）。

var _view: StoragePlaygroundView = null
var _service: StorageDemoService = null


func _init(view: StoragePlaygroundView) -> void:
	_view = view
	_service = StorageDemoService.new()


func get_service() -> StorageDemoService:
	return _service


func bind_and_run_async() -> int:
	_service.initialize_from_env()
	if _view != null:
		_view.rerun_suite_requested.connect(_on_rerun_suite)
		_view.toggle_encryption_requested.connect(_on_toggle_encryption)
		_view.toggle_bind_device_requested.connect(_on_toggle_bind_device)
		_view.toggle_fallback_requested.connect(_on_toggle_fallback)
		_view.write_save_requested.connect(_on_write_save)
		_view.write_config_requested.connect(_on_write_config)
		_view.read_verify_requested.connect(_on_read_verify)
		_view.tamper_primary_requested.connect(_on_tamper_primary)
		_view.foreign_device_requested.connect(_on_foreign_device)
		_view.cross_slot_requested.connect(_on_cross_slot)
		_view.render_all(_service.state)

	var passed: int = await _service.run_automated_suite_async()
	_refresh_view()
	return passed


func unbind() -> void:
	_view = null


func _refresh_view() -> void:
	if _view != null and _service != null:
		_view.render_all(_service.state)


func _on_rerun_suite() -> void:
	await _service.run_automated_suite_async()
	_refresh_view()


func _on_toggle_encryption() -> void:
	await _service.toggle_encryption_async()
	_refresh_view()


func _on_toggle_bind_device() -> void:
	await _service.toggle_bind_device_async()
	_refresh_view()


func _on_toggle_fallback() -> void:
	_service.toggle_plaintext_fallback()
	_refresh_view()


func _on_write_save() -> void:
	await _service.write_save_reward_async()
	_refresh_view()


func _on_write_config() -> void:
	await _service.write_config_toggle_async()
	_refresh_view()


func _on_read_verify() -> void:
	await _service.read_and_verify_async()
	_refresh_view()


func _on_tamper_primary() -> void:
	await _service.simulate_single_byte_tamper_async()
	_refresh_view()


func _on_foreign_device() -> void:
	await _service.simulate_foreign_device_save_async()
	_refresh_view()


func _on_cross_slot() -> void:
	await _service.simulate_cross_slot_replay_async()
	_refresh_view()
