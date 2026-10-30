class_name InventoryEquipPanel
extends PanelContainer

## 左栏三槽规则装备与选中物品聚焦展台面板预制体脚本（`src/test/inventory/view/component/equip/`）。[br]
##
## [b]设计职责：[/b]绑定 `inventory_equip_panel.tscn` 内嵌的 3 个 [InventorySlotCard] 实例与展台节点，转发交互信号并渲染物品详情。


#region Signals

## 左键点击选中某个装备槽。
signal slot_selected(container_id: StringName, slot_index: int, uid: int)

## 右键请求一键卸下某个装备槽。
signal slot_quick_triggered(container_id: StringName, slot_index: int, uid: int)

## 拖拽松手落入某个装备槽。
signal slot_dropped(drag_data: Dictionary, dst_id: StringName, dst_index: int)

#endregion


#region Node References

@onready var _weapon_slot: InventorySlotCard = %WeaponSlot as InventorySlotCard
@onready var _shield_slot: InventorySlotCard = %ShieldSlot as InventorySlotCard
@onready var _ring_slot: InventorySlotCard = %RingSlot as InventorySlotCard

@onready var _empty_label: Label = %EmptyLabel as Label
@onready var _content_box: VBoxContainer = %ContentBox as VBoxContainer
@onready var _icon_frame: PanelContainer = %IconFrame as PanelContainer
@onready var _focus_icon: InventoryMiniIcon = %FocusIcon as InventoryMiniIcon
@onready var _name_label: Label = %NameLabel as Label
@onready var _sub_label: Label = %SubLabel as Label
@onready var _stat_label: Label = %StatLabel as Label
@onready var _meta_left_label: Label = %MetaLeftLabel as Label
@onready var _meta_right_label: Label = %MetaRightLabel as Label

var _runtime_frame_style: StyleBoxFlat = null

#endregion


#region Lifecycle & Public API

func _ready() -> void:
	for card: InventorySlotCard in [_weapon_slot, _shield_slot, _ring_slot]:
		if card != null:
			card.slot_selected.connect(func(cid: StringName, idx: int, uid: int) -> void:
				slot_selected.emit(cid, idx, uid)
			)
			card.slot_quick_triggered.connect(func(cid: StringName, idx: int, uid: int) -> void:
				slot_quick_triggered.emit(cid, idx, uid)
			)
			card.slot_dropped.connect(func(data: Dictionary, dst_id: StringName, dst_idx: int) -> void:
				slot_dropped.emit(data, dst_id, dst_idx)
			)

	if _icon_frame != null:
		var base_style: StyleBoxFlat = _icon_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if base_style != null:
			_runtime_frame_style = base_style.duplicate() as StyleBoxFlat
			_icon_frame.add_theme_stylebox_override("panel", _runtime_frame_style)


## 注入拖拽准入预判闭包至全部 3 个装备槽实例。
func bind_validator(validator: Callable) -> void:
	if _weapon_slot != null:
		_weapon_slot.bind_validator(validator)
	if _shield_slot != null:
		_shield_slot.bind_validator(validator)
	if _ring_slot != null:
		_ring_slot.bind_validator(validator)


## 刷新三栏装备槽状态与下方选中物品聚焦展台。
func render_panel(service: InventoryDemoService, selected_stack: ItemStack) -> void:
	if service == null:
		return
	var sel_cid: StringName = service.state.selected_container_id
	var sel_uid: int = service.state.selected_uid

	_bind_equip_card(_weapon_slot, service, service.equip_weapon, sel_cid, sel_uid)
	_bind_equip_card(_shield_slot, service, service.equip_shield, sel_cid, sel_uid)
	_bind_equip_card(_ring_slot, service, service.equip_ring, sel_cid, sel_uid)
	_render_focus(service, selected_stack)

#endregion


#region Internal Helpers

func _bind_equip_card(
	card: InventorySlotCard,
	service: InventoryDemoService,
	container: SlotItemContainer,
	sel_cid: StringName,
	sel_uid: int
) -> void:
	if card == null or container == null:
		return
	var st: ItemStack = container.get_slot(0)
	var vis: InventoryItemVisualConfig = (
		service.get_visual_config(st.item_id) if st != null else null
	)
	var is_sel: bool = sel_cid == container.container_id and st != null and st.uid == sel_uid
	card.bind_state(st, vis, is_sel)


func _render_focus(service: InventoryDemoService, stack: ItemStack) -> void:
	if _empty_label == null or _content_box == null:
		return
	if stack == null:
		_empty_label.visible = true
		_content_box.visible = false
		return

	var vis: InventoryItemVisualConfig = service.get_visual_config(stack.item_id)
	if vis == null:
		_empty_label.visible = true
		_content_box.visible = false
		return

	_empty_label.visible = false
	_content_box.visible = true

	if _focus_icon != null:
		_focus_icon.set_icon_state(vis.icon_kind, vis.accent_color, false, 1.0)
	if _runtime_frame_style != null:
		_runtime_frame_style.border_color = Color(
			vis.accent_color.r,
			vis.accent_color.g,
			vis.accent_color.b,
			0.55
		)

	if _name_label != null:
		_name_label.text = vis.display_name
	if _sub_label != null:
		_sub_label.text = "%s · %s" % [
			InventoryItemVisualConfig.get_rarity_label(vis.rarity),
			vis.category_label
		]
		_sub_label.add_theme_color_override("font_color", vis.accent_color)
	if _stat_label != null:
		_stat_label.text = vis.format_stat_line(stack)

	if _meta_left_label != null:
		var spec: ItemSpec = vis.spec
		if spec != null:
			var eff: Vector2i = spec.get_effective_size(stack.rotated)
			if spec.is_stackable():
				_meta_left_label.text = "堆叠 %d / %d" % [stack.count, spec.max_stack]
			else:
				_meta_left_label.text = "尺寸 %d×%d" % [eff.x, eff.y]
		else:
			_meta_left_label.text = ""

	if _meta_right_label != null:
		_meta_right_label.text = "#%d" % stack.uid

#endregion
