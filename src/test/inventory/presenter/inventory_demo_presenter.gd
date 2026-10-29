class_name InventoryDemoPresenter
extends RefCounted

## 背包交互测试演练场中介协调器（`src/test/inventory/presenter/`）。[br]
##
## [b]设计职责：[/b][br]
## 订阅 [InventoryPlaygroundView] 的交互意图与全部 [BaseItemContainer] 的增量变更通知，
## 驱动 [InventoryDemoService] 执行事务并在操作被规则拦截时弹出极简轻提示。


#region State

var _view: InventoryPlaygroundView = null
var _service: InventoryDemoService = null
var _bound: bool = false

#endregion


#region Lifecycle

## 构造 Presenter 实例。
func _init(p_view: InventoryPlaygroundView, p_service: InventoryDemoService = null) -> void:
	_view = p_view
	_service = p_service if p_service != null else InventoryDemoService.new()


## 获取关联的领域测试服务实例。
func get_service() -> InventoryDemoService:
	return _service


## 绑定信号、执行 10 项底层契约自检并装载初始演示数据。
func bind() -> int:
	if _bound or _view == null or _service == null:
		return 0
	_bound = true

	var passed: int = _service.run_kernel_self_check()
	_service.reset_demo()
	_view.initialize_bindings(_service)

	for c: BaseItemContainer in _service.get_all_containers():
		if not c.changed.is_connected(_on_container_changed):
			c.changed.connect(_on_container_changed)

	_view.supply_requested.connect(_on_supply_requested)
	_view.craft_requested.connect(_on_craft_requested)
	_view.reset_requested.connect(_on_reset_requested)
	_view.split_requested.connect(_on_split_requested)
	_view.sort_requested.connect(_on_sort_requested)
	_view.rotate_requested.connect(_on_rotate_requested)
	_view.item_selected.connect(_on_item_selected)
	_view.quick_transfer_requested.connect(_on_quick_transfer_requested)
	_view.slot_drop_requested.connect(_on_slot_drop_requested)
	_view.grid_drop_requested.connect(_on_grid_drop_requested)

	_view.open()
	_view.render_all(_service)
	return passed


## 对称解绑全部容器与视图信号（防止悬挂引用泄漏）。
func unbind() -> void:
	if not _bound:
		return
	_bound = false

	if _service != null:
		for c: BaseItemContainer in _service.get_all_containers():
			if c.changed.is_connected(_on_container_changed):
				c.changed.disconnect(_on_container_changed)

	if _view != null and is_instance_valid(_view):
		if _view.supply_requested.is_connected(_on_supply_requested):
			_view.supply_requested.disconnect(_on_supply_requested)
		if _view.craft_requested.is_connected(_on_craft_requested):
			_view.craft_requested.disconnect(_on_craft_requested)
		if _view.reset_requested.is_connected(_on_reset_requested):
			_view.reset_requested.disconnect(_on_reset_requested)
		if _view.split_requested.is_connected(_on_split_requested):
			_view.split_requested.disconnect(_on_split_requested)
		if _view.sort_requested.is_connected(_on_sort_requested):
			_view.sort_requested.disconnect(_on_sort_requested)
		if _view.rotate_requested.is_connected(_on_rotate_requested):
			_view.rotate_requested.disconnect(_on_rotate_requested)
		if _view.item_selected.is_connected(_on_item_selected):
			_view.item_selected.disconnect(_on_item_selected)
		if _view.quick_transfer_requested.is_connected(_on_quick_transfer_requested):
			_view.quick_transfer_requested.disconnect(_on_quick_transfer_requested)
		if _view.slot_drop_requested.is_connected(_on_slot_drop_requested):
			_view.slot_drop_requested.disconnect(_on_slot_drop_requested)
		if _view.grid_drop_requested.is_connected(_on_grid_drop_requested):
			_view.grid_drop_requested.disconnect(_on_grid_drop_requested)

#endregion


#region Event Handlers

func _on_container_changed(_diff: InventoryDiff) -> void:
	if _view != null:
		_view.render_all(_service)


func _on_supply_requested() -> void:
	var res: Result = _service.grant_supply()
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.2)
	else:
		ToastManager.show("补给已入库", 1.0)


func _on_craft_requested() -> void:
	var res: Result = _service.craft_rune_sword()
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.3)
	else:
		_view.render_all(_service)
		ToastManager.show("锻造 · 符文长剑", 1.2)


func _on_reset_requested() -> void:
	_service.reset_demo()
	_view.render_all(_service)
	ToastManager.show("已重置", 0.9)


func _on_split_requested() -> void:
	var res: Result = _service.split_selected()
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.2)


func _on_sort_requested() -> void:
	var res: Result = _service.sort_bag()
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.2)


func _on_rotate_requested() -> void:
	if _service.state.selected_container_id != &"grid" or _service.state.selected_uid <= 0:
		return
	var res: Result = _service.rotate_grid_item(_service.state.selected_uid)
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.2)


func _on_item_selected(container_id: StringName, slot_index: int, uid: int) -> void:
	if uid <= 0:
		_service.state.clear_selection()
	else:
		_service.state.set_selection(container_id, slot_index, uid)
	_view.render_all(_service)


func _on_quick_transfer_requested(container_id: StringName, slot_index: int, uid: int) -> void:
	var res: Result = _service.quick_transfer(container_id, slot_index, uid)
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.2)
	else:
		_view.render_all(_service)


func _on_slot_drop_requested(drag_data: Dictionary, dst_id: StringName, dst_index: int) -> void:
	var res: Result = _service.drop_on_slot(drag_data, dst_id, dst_index)
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.2)
	else:
		_view.render_all(_service)


func _on_grid_drop_requested(drag_data: Dictionary, target_pos: Vector2i, is_rotated: bool) -> void:
	var res: Result = _service.drop_on_grid(drag_data, target_pos, is_rotated)
	if res.is_err():
		ToastManager.show(InventoryDemoService.format_error_brief(res), 1.2)
	else:
		_view.render_all(_service)

#endregion
