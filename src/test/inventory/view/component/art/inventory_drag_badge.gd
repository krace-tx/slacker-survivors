class_name InventoryDragBadge
extends Control

## 原生拖拽跟随半透明悬浮卡片预制体脚本（`src/test/inventory/view/component/art/`）。[br]
##
## [b]设计职责：[/b]绑定 `inventory_drag_badge.tscn` 声明式子节点，在拖拽启动时对齐鼠标热点并展示物品图标与数量。


#region Node References

@onready var _card_panel: PanelContainer = %CardPanel as PanelContainer
@onready var _icon_view: InventoryMiniIcon = %IconView as InventoryMiniIcon
@onready var _count_label: Label = %CountLabel as Label

var _pending_visual: InventoryItemVisualConfig = null
var _pending_count: int = 1
var _pending_box_size: Vector2 = Vector2(76.0, 76.0)
var _pending_rotated: bool = false

#endregion


#region Lifecycle & Binding

func _ready() -> void:
	_apply_visual_state()


## 配置悬浮预览尺寸、稀有度边框色、旋转姿态与堆叠数量。
func setup_badge(
	p_visual: InventoryItemVisualConfig,
	p_count: int = 1,
	p_box_size: Vector2 = Vector2(76.0, 76.0),
	p_rotated: bool = false
) -> void:
	_pending_visual = p_visual
	_pending_count = p_count
	_pending_box_size = p_box_size
	_pending_rotated = p_rotated
	if is_node_ready():
		_apply_visual_state()


func _apply_visual_state() -> void:
	if _card_panel == null or _pending_visual == null:
		return
	_card_panel.size = _pending_box_size
	_card_panel.custom_minimum_size = _pending_box_size
	_card_panel.position = -_pending_box_size * 0.5

	var base_box: StyleBoxFlat = _card_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if base_box != null:
		var custom_box: StyleBoxFlat = base_box.duplicate() as StyleBoxFlat
		custom_box.border_color = _pending_visual.accent_color
		_card_panel.add_theme_stylebox_override("panel", custom_box)

	if _icon_view != null:
		_icon_view.set_icon_state(
			_pending_visual.icon_kind,
			_pending_visual.accent_color,
			_pending_rotated,
			0.96
		)

	if _count_label != null:
		_count_label.visible = _pending_count > 1
		_count_label.text = str(_pending_count)

#endregion
