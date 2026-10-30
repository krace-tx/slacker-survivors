@tool
class_name OtomeHotspotBubble
extends Button

## 乙女向户外庭院 3D 锚点悬浮交互气泡按钮（暖奶油磨砂底 `#FFFDF9` + 玫瑰金细描边 `#D9A796`）。[br]
##
## 跟随 3D 世界热点锚点实时投影至屏幕坐标；当主角走近热点触发半径内时自动切换为心动绯粉高亮描边。

#region Signals
## 当玩家点击该悬浮热点气泡时发出。
signal hotspot_clicked(hotspot_id: int)
#endregion

#region Exports & Private State
@export var hotspot_id: int = 0

var _is_nearby: bool = false
#endregion


#region Lifecycle
func _ready() -> void:
	custom_minimum_size = Vector2(168.0, 36.0)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not Engine.is_editor_hint() or not has_theme_stylebox_override("normal"):
		_apply_bubble_styles(_is_nearby)
	if not Engine.is_editor_hint():
		pressed.connect(_on_pressed)
#endregion


#region Public Render API
## 更新气泡文本与邻近高亮态。
func set_bubble_display(label_text: String, is_nearby: bool) -> void:
	if text != label_text:
		text = label_text
	if _is_nearby != is_nearby:
		_is_nearby = is_nearby
		_apply_bubble_styles(_is_nearby)
#endregion


#region Internal Styling & Callbacks
func _apply_bubble_styles(highlight: bool) -> void:
	var bg_col: Color = Color(1.0, 0.945, 0.935, 0.96) if highlight else Color(1.0, 0.992, 0.976, 0.92)
	var border_col: Color = Color("#DF7E8E") if highlight else Color("#D9A796")
	var hover_bg: Color = Color(1.0, 0.92, 0.91, 0.98)
	var border_w: int = 2 if highlight else 1

	var normal_box: StyleBoxFlat = _make_pill_box(bg_col, border_col, border_w)
	var hover_box: StyleBoxFlat = _make_pill_box(hover_bg, Color("#DF7E8E"), 2)

	add_theme_stylebox_override("normal", normal_box)
	add_theme_stylebox_override("hover", hover_box)
	add_theme_stylebox_override("pressed", hover_box)
	add_theme_color_override("font_color", Color("#5C3538") if highlight else Color("#4A3A36"))
	add_theme_color_override("font_hover_color", Color("#5C3538"))
	add_theme_color_override("font_pressed_color", Color("#5C3538"))
	add_theme_font_size_override("font_size", 14)


func _make_pill_box(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(18)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	box.shadow_color = Color(0.36, 0.22, 0.20, 0.14)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0.0, 2.0)
	return box


func _on_pressed() -> void:
	hotspot_clicked.emit(hotspot_id)
#endregion
