class_name InventorySlotCard
extends PanelContainer

## 声明式单格物品槽预制体脚本（`src/test/inventory/view/component/slot/`）。[br]
##
## [b]设计职责：[/b][br]
## 绑定 `inventory_slot_card.tscn` 预设节点与 `StyleBoxFlat` 子资源，零运行时动态建树，
## 承载主背包槽位与装备栏专用槽位的展示、悬停微光、左键选中、右键快移与原生拖拽。


#region Signals

## 左键点击选中该槽位时发射。
signal slot_selected(container_id: StringName, slot_index: int, uid: int)

## 右键请求快捷穿脱或跨容器搬运时发射。
signal slot_quick_triggered(container_id: StringName, slot_index: int, uid: int)

## 拖拽物品松手落入该槽位时发射。
signal slot_dropped(drag_data: Dictionary, dst_id: StringName, dst_index: int)

#endregion


#region Exports

@export_group("Slot Identity")
## 所属容器业务 ID（可在父级 `.tscn` 实例上直接覆写）。
@export var container_id: StringName = &""

## 在所属槽位容器内的下标。
@export var slot_index: int = 0

## 空槽状态下显示的几何底纹枚举（`-1` 表示无底纹）。
@export var empty_watermark_kind: int = -1

## 槽位角色短签（如 `"主手"`、`"副手"`、`"饰品"`）。
@export var role_caption: String = ""

@export_group("Declarative Styles & Prefabs")
## 空槽默认面板样式。
@export var style_empty: StyleBoxFlat = null

## 非空占用默认面板样式。
@export var style_occupied: StyleBoxFlat = null

## 鼠标悬停面板样式。
@export var style_hover: StyleBoxFlat = null

## 选中焦点面板样式。
@export var style_selected: StyleBoxFlat = null

## 拖拽准入合法悬停样式。
@export var style_valid: StyleBoxFlat = null

## 拖拽规则拒绝悬停样式。
@export var style_reject: StyleBoxFlat = null

## 拖拽跟随预览徽章预制体（`inventory_drag_badge.tscn`）。
@export var drag_badge_scene: PackedScene = null

#endregion


#region Internal State & Node References

enum _DragHover {
	NONE = 0,
	VALID = 1,
	REJECTED = 2,
}

@onready var _rarity_tint: Panel = %RarityTint as Panel
@onready var _top_accent_bar: ColorRect = %TopAccentBar as ColorRect
@onready var _icon_view: InventoryMiniIcon = %IconView as InventoryMiniIcon
@onready var _meta_dot: Panel = %MetaDot as Panel
@onready var _role_label: Label = %RoleLabel as Label
@onready var _count_label: Label = %CountLabel as Label

## 拖拽准入预校验回调（签名：`func(drag_data: Dictionary, dst_id: StringName, dst_index: int) -> bool`）。
var drop_validator: Callable = Callable()

var _stack: ItemStack = null
var _visual: InventoryItemVisualConfig = null
var _is_selected: bool = false
var _is_hovered: bool = false
var _drag_hover: int = _DragHover.NONE

#endregion


#region Lifecycle & Public API

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_nodes()


## 注入拖拽准入校验闭包（可选覆写容器标识与下标）。
func bind_validator(
	p_validator: Callable,
	p_container_id: StringName = &"",
	p_slot_index: int = -1
) -> void:
	drop_validator = p_validator
	if not p_container_id.is_empty():
		container_id = p_container_id
	if p_slot_index >= 0:
		slot_index = p_slot_index


## 刷新当前槽位承载的物品实例与选中高亮态。
func bind_state(
	p_stack: ItemStack,
	p_visual: InventoryItemVisualConfig,
	p_selected: bool
) -> void:
	_stack = p_stack
	_visual = p_visual
	_is_selected = p_selected
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if _stack != null else Control.CURSOR_ARROW
	)
	if is_node_ready():
		_refresh_nodes()

#endregion


#region Input & Native Drag-and-Drop

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_hover != _DragHover.NONE:
		_drag_hover = _DragHover.NONE
		_refresh_stylebox()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_LEFT:
		var uid: int = _stack.uid if _stack != null else 0
		slot_selected.emit(container_id, slot_index, uid)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and _stack != null:
		slot_selected.emit(container_id, slot_index, _stack.uid)
		slot_quick_triggered.emit(container_id, slot_index, _stack.uid)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if _stack == null or _visual == null:
		return null
	slot_selected.emit(container_id, slot_index, _stack.uid)
	if drag_badge_scene != null:
		var preview: InventoryDragBadge = drag_badge_scene.instantiate() as InventoryDragBadge
		if preview != null:
			preview.setup_badge(_visual, _stack.count, Vector2(76.0, 76.0), false)
			set_drag_preview(preview)

	return {
		"inv_drag": true,
		"src_id": container_id,
		"slot_index": slot_index,
		"uid": _stack.uid,
		"item_id": _stack.item_id,
		"count": _stack.count,
		"rotated": _stack.rotated,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data as Dictionary
	if not bool(payload.get("inv_drag", false)):
		return false

	var allowed: bool = true
	if drop_validator.is_valid():
		allowed = bool(drop_validator.call(payload, container_id, slot_index))
	var next_state: int = _DragHover.VALID if allowed else _DragHover.REJECTED
	if _drag_hover != next_state:
		_drag_hover = next_state
		_refresh_stylebox()
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drag_hover = _DragHover.NONE
	_refresh_stylebox()
	if data is Dictionary:
		slot_dropped.emit(data as Dictionary, container_id, slot_index)

#endregion


#region Declarative Node State Sync

func _refresh_nodes() -> void:
	_refresh_stylebox()

	if _stack == null or _visual == null:
		if _rarity_tint != null:
			_rarity_tint.visible = false
		if _top_accent_bar != null:
			_top_accent_bar.visible = false
		if _meta_dot != null:
			_meta_dot.visible = false
		if _count_label != null:
			_count_label.visible = false

		if _icon_view != null:
			if empty_watermark_kind >= 0:
				_icon_view.visible = true
				_icon_view.set_icon_state(
					empty_watermark_kind,
					Color(0.45, 0.54, 0.68, 1.0),
					false,
					0.20
				)
			else:
				_icon_view.visible = false

		if _role_label != null:
			_role_label.visible = not role_caption.is_empty()
			_role_label.text = role_caption
			_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return

	var accent: Color = _visual.accent_color
	if _rarity_tint != null:
		_rarity_tint.visible = true
		_rarity_tint.modulate = Color(accent.r, accent.g, accent.b, 0.05)

	if _top_accent_bar != null:
		_top_accent_bar.visible = true
		_top_accent_bar.color = Color(accent.r, accent.g, accent.b, 0.90)

	if _icon_view != null:
		_icon_view.visible = true
		_icon_view.set_icon_state(_visual.icon_kind, accent, false, 1.0)

	if _meta_dot != null:
		var is_bound: bool = bool(_stack.meta.get("bound", false))
		var is_crafted: bool = bool(_stack.meta.get("crafted", false))
		_meta_dot.visible = is_bound or is_crafted
		if is_bound:
			_meta_dot.modulate = Color(0.98, 0.75, 0.20, 0.95)
		elif is_crafted:
			_meta_dot.modulate = Color(0.68, 0.55, 0.98, 0.95)

	if _count_label != null:
		_count_label.visible = _stack.count > 1
		if _stack.count > 1:
			_count_label.text = str(_stack.count)

	if _role_label != null:
		var show_role: bool = _stack.count <= 1 and not role_caption.is_empty()
		_role_label.visible = show_role
		if show_role:
			_role_label.text = role_caption
			_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _refresh_stylebox() -> void:
	var target_style: StyleBoxFlat = style_empty
	if _drag_hover == _DragHover.VALID and style_valid != null:
		target_style = style_valid
	elif _drag_hover == _DragHover.REJECTED and style_reject != null:
		target_style = style_reject
	elif _is_selected and style_selected != null:
		target_style = style_selected
	elif _is_hovered and style_hover != null:
		target_style = style_hover
	elif _stack != null and style_occupied != null:
		target_style = style_occupied

	if target_style != null:
		add_theme_stylebox_override("panel", target_style)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_refresh_stylebox()


func _on_mouse_exited() -> void:
	_is_hovered = false
	if _drag_hover != _DragHover.NONE:
		_drag_hover = _DragHover.NONE
	_refresh_stylebox()

#endregion
