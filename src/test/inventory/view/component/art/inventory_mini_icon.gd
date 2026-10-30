class_name InventoryMiniIcon
extends Control

## 轻量内嵌矢量图标控件（`src/test/inventory/view/component/art/`）。[br]
##
## [b]设计职责：[/b]支持在 `.tscn` 场景树中直接摆放并通过导出属性配置图标类型与配色。


#region Exports

## 矢量图标枚举值（`< 0` 时留空不绘）。
@export var icon_kind: int = -1:
	set(value):
		icon_kind = value
		queue_redraw()

## 图标主色调。
@export var accent_color: Color = Color(0.75, 0.82, 0.92, 1.0):
	set(value):
		accent_color = value
		queue_redraw()

## 是否以 90 度旋转姿态绘制。
@export var is_rotated: bool = false:
	set(value):
		is_rotated = value
		queue_redraw()

## 绘制不透明度。
@export var icon_alpha: float = 1.0:
	set(value):
		icon_alpha = value
		queue_redraw()

#endregion


#region Public API

## 批量更新图标状态并触发单次重绘。
func set_icon_state(
	p_kind: int,
	p_accent: Color,
	p_rotated: bool = false,
	p_alpha: float = 1.0
) -> void:
	icon_kind = p_kind
	accent_color = p_accent
	is_rotated = p_rotated
	icon_alpha = p_alpha
	queue_redraw()

#endregion


#region Drawing

func _draw() -> void:
	if icon_kind < 0 or size.x <= 2.0 or size.y <= 2.0:
		return
	InventoryIconPainter.draw_icon(
		self,
		Rect2(Vector2.ZERO, size),
		icon_kind,
		accent_color,
		is_rotated,
		icon_alpha
	)

#endregion
