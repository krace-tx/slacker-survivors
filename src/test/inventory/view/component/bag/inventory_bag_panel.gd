class_name InventoryBagPanel
extends PanelContainer

## 中栏 16 格角色主背包面板预制体脚本（`src/test/inventory/view/component/bag/`）。[br]
##
## [b]设计职责：[/b]绑定 `inventory_bag_panel.tscn` 中预摆放的 `4×4` 共 16 个 [InventorySlotCard] 实例以及拆半/整理按钮。


#region Signals

## 点击「拆半」按钮。
signal split_requested

## 点击「整理」按钮。
signal sort_requested

## 左键选中背包槽位。
signal slot_selected(container_id: StringName, slot_index: int, uid: int)

## 右键触发背包槽位快捷穿脱或转出。
signal slot_quick_triggered(container_id: StringName, slot_index: int, uid: int)

## 拖拽松手落入背包槽位。
signal slot_dropped(drag_data: Dictionary, dst_id: StringName, dst_index: int)

#endregion


#region Node References

@onready var _count_label: Label = %CountLabel as Label
@onready var _split_btn: Button = %SplitButton as Button
@onready var _sort_btn: Button = %SortButton as Button
@onready var _slot_grid: GridContainer = %SlotGrid as GridContainer

var _slot_cards: Array[InventorySlotCard] = []

#endregion


#region Lifecycle & Public API

func _ready() -> void:
	if _split_btn != null:
		_split_btn.pressed.connect(func() -> void: split_requested.emit())
	if _sort_btn != null:
		_sort_btn.pressed.connect(func() -> void: sort_requested.emit())

	_slot_cards.clear()
	if _slot_grid != null:
		var children: Array[Node] = _slot_grid.get_children()
		for i: int in children.size():
			var card: InventorySlotCard = children[i] as InventorySlotCard
			if card == null:
				continue
			card.container_id = &"bag"
			card.slot_index = i
			card.slot_selected.connect(func(cid: StringName, idx: int, uid: int) -> void:
				slot_selected.emit(cid, idx, uid)
			)
			card.slot_quick_triggered.connect(func(cid: StringName, idx: int, uid: int) -> void:
				slot_quick_triggered.emit(cid, idx, uid)
			)
			card.slot_dropped.connect(func(data: Dictionary, dst_id: StringName, dst_idx: int) -> void:
				slot_dropped.emit(data, dst_id, dst_idx)
			)
			_slot_cards.append(card)


## 注入拖拽准入校验闭包至全部 16 个背包槽位实例。
func bind_validator(validator: Callable) -> void:
	for i: int in _slot_cards.size():
		_slot_cards[i].bind_validator(validator, &"bag", i)


## 刷新背包已占槽位数、按钮禁用态与全部 16 个槽位卡片。
func render_panel(service: InventoryDemoService) -> void:
	if service == null:
		return
	var sel_cid: StringName = service.state.selected_container_id
	var sel_uid: int = service.state.selected_uid

	for i: int in _slot_cards.size():
		var st: ItemStack = service.bag.get_slot(i)
		var vis: InventoryItemVisualConfig = (
			service.get_visual_config(st.item_id) if st != null else null
		)
		var is_sel: bool = sel_cid == &"bag" and st != null and st.uid == sel_uid
		_slot_cards[i].bind_state(st, vis, is_sel)

	if _count_label != null:
		_count_label.text = "%d / %d" % [
			service.bag.get_occupied_slot_count(),
			service.bag.capacity
		]
	if _split_btn != null:
		_split_btn.disabled = not service.can_split_selected()

#endregion
