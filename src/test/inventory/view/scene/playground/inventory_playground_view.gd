class_name InventoryPlaygroundView
extends BaseView

## 背包与通用容器交互演练场主视图（`src/test/inventory/view/scene/playground/`）。[br]
##
## [b]声明式组件编排契约：[/b][br]
## 零运行时代码拼装节点，完全通过 `@onready` 组合 `inventory_playground_scene.tscn` 中预挂载的四大 `.tscn` 预制体：
## [InventoryHeaderBar]、[InventoryEquipPanel]、[InventoryBagPanel] 与 [InventoryGridPanel]。


#region Signals

## 点击「补给」按钮。
signal supply_requested

## 点击「锻造」按钮。
signal craft_requested

## 点击「重置」按钮。
signal reset_requested

## 点击背包「拆半」按钮。
signal split_requested

## 点击背包「整理」按钮。
signal sort_requested

## 点击「旋转 [R]」按钮或按下键盘 `R`。
signal rotate_requested

## 左键选中任意槽位或网格物品。
signal item_selected(container_id: StringName, slot_index: int, uid: int)

## 右键触发快捷穿脱或跨容器搬运。
signal quick_transfer_requested(container_id: StringName, slot_index: int, uid: int)

## 拖拽松手落入目标一维槽位。
signal slot_drop_requested(drag_data: Dictionary, dst_id: StringName, dst_index: int)

## 拖拽松手落入目标二维网格锚点。
signal grid_drop_requested(drag_data: Dictionary, target_pos: Vector2i, is_rotated: bool)

#endregion


#region Declarative Sub-Component References

@onready var _header_bar: InventoryHeaderBar = %HeaderBar as InventoryHeaderBar
@onready var _equip_panel: InventoryEquipPanel = %EquipPanel as InventoryEquipPanel
@onready var _bag_panel: InventoryBagPanel = %BagPanel as InventoryBagPanel
@onready var _grid_panel: InventoryGridPanel = %GridPanel as InventoryGridPanel

#endregion


#region Lifecycle

func _ready() -> void:
	super._ready()
	_connect_subcomponents()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or ke.echo or ke.keycode != KEY_R:
		return

	var vp: Viewport = get_viewport()
	if vp != null and vp.gui_is_dragging():
		var drag_val: Variant = vp.gui_get_drag_data()
		if drag_val is Dictionary:
			var payload: Dictionary = drag_val as Dictionary
			if bool(payload.get("inv_drag", false)):
				payload["rotated"] = not bool(payload.get("rotated", false))
				if _grid_panel != null:
					_grid_panel.refresh_active_drag_preview(payload)
				vp.set_input_as_handled()
				return

	rotate_requested.emit()
	if vp != null:
		vp.set_input_as_handled()

#endregion


#region Public Binding & Rendering API

## 将底层容器的拖拽准入验证闭包一次性注入各声明式面板组件。
func initialize_bindings(service: InventoryDemoService) -> void:
	if service == null:
		return
	if _equip_panel != null:
		_equip_panel.bind_validator(service.can_drop_on_slot)
	if _bag_panel != null:
		_bag_panel.bind_validator(service.can_drop_on_slot)
	if _grid_panel != null:
		_grid_panel.setup_panel(service)


## 同步刷新四大子预制体面板状态。
func render_all(service: InventoryDemoService) -> void:
	if service == null:
		return
	var selected_stack: ItemStack = service.sync_and_get_selected_stack()

	if _header_bar != null:
		_header_bar.render_header(
			service.state.passed_cases,
			service.state.total_cases,
			service.wallet.get_total_count(&"gold"),
			service.wallet.get_total_count(&"gem"),
			service.can_craft_rune_sword()
		)
	if _equip_panel != null:
		_equip_panel.render_panel(service, selected_stack)
	if _bag_panel != null:
		_bag_panel.render_panel(service)
	if _grid_panel != null:
		_grid_panel.render_panel(service)

#endregion


#region Signal Forwarding

func _connect_subcomponents() -> void:
	if _header_bar != null:
		_header_bar.supply_requested.connect(func() -> void: supply_requested.emit())
		_header_bar.craft_requested.connect(func() -> void: craft_requested.emit())
		_header_bar.reset_requested.connect(func() -> void: reset_requested.emit())

	if _equip_panel != null:
		_equip_panel.slot_selected.connect(func(cid: StringName, idx: int, uid: int) -> void:
			item_selected.emit(cid, idx, uid)
		)
		_equip_panel.slot_quick_triggered.connect(func(cid: StringName, idx: int, uid: int) -> void:
			quick_transfer_requested.emit(cid, idx, uid)
		)
		_equip_panel.slot_dropped.connect(func(data: Dictionary, dst_id: StringName, dst_idx: int) -> void:
			slot_drop_requested.emit(data, dst_id, dst_idx)
		)

	if _bag_panel != null:
		_bag_panel.split_requested.connect(func() -> void: split_requested.emit())
		_bag_panel.sort_requested.connect(func() -> void: sort_requested.emit())
		_bag_panel.slot_selected.connect(func(cid: StringName, idx: int, uid: int) -> void:
			item_selected.emit(cid, idx, uid)
		)
		_bag_panel.slot_quick_triggered.connect(func(cid: StringName, idx: int, uid: int) -> void:
			quick_transfer_requested.emit(cid, idx, uid)
		)
		_bag_panel.slot_dropped.connect(func(data: Dictionary, dst_id: StringName, dst_idx: int) -> void:
			slot_drop_requested.emit(data, dst_id, dst_idx)
		)

	if _grid_panel != null:
		_grid_panel.rotate_requested.connect(func() -> void: rotate_requested.emit())
		_grid_panel.item_selected.connect(func(uid: int) -> void:
			item_selected.emit(&"grid", -1, uid)
		)
		_grid_panel.item_quick_triggered.connect(func(uid: int) -> void:
			quick_transfer_requested.emit(&"grid", -1, uid)
		)
		_grid_panel.grid_dropped.connect(func(data: Dictionary, pos: Vector2i, rot: bool) -> void:
			grid_drop_requested.emit(data, pos, rot)
		)

#endregion
