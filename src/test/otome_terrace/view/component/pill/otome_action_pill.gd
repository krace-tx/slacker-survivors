@tool
class_name OtomeActionPill
extends Button

## 乙女向暖奶油玫瑰金胶囊快捷按钮组件（用于换装、神态、温柔招呼、天光与镜头切换）。[br]
##
## 支持普通态（奶油白底 + 玫瑰金细描边）与激活强调态（樱花粉渐变底 + 玫瑰深粉描边）。

#region Exports
@export var is_accented: bool = false:
	set(value):
		is_accented = value
		if is_node_ready():
			_apply_pill_styles(is_accented)
#endregion


#region Lifecycle
func _ready() -> void:
	if custom_minimum_size.x < 80.0 or custom_minimum_size.y < 32.0:
		custom_minimum_size = Vector2(132.0, 38.0)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not Engine.is_editor_hint() or not has_theme_stylebox_override("normal"):
		_apply_pill_styles(is_accented)
#endregion


#region Public Render API
## 刷新胶囊按钮文案与强调高亮态。
func set_pill_display(label_text: String, accented: bool = false) -> void:
	if text != label_text:
		text = label_text
	if is_accented != accented:
		is_accented = accented
		_apply_pill_styles(is_accented)
#endregion


#region Internal Styling
func _apply_pill_styles(accented: bool) -> void:
	var bg_normal: Color = Color(0.99, 0.92, 0.91, 0.96) if accented else Color(1.0, 0.992, 0.976, 0.93)
	var border_normal: Color = Color("#DF7E8E") if accented else Color("#D9A796")
	var bg_hover: Color = Color(0.99, 0.89, 0.88, 0.98) if accented else Color(0.995, 0.955, 0.935, 0.97)
	var border_w: int = 2 if accented else 1

	var normal_box: StyleBoxFlat = _make_style(bg_normal, border_normal, border_w)
	var hover_box: StyleBoxFlat = _make_style(bg_hover, Color("#DF7E8E"), 2)

	add_theme_stylebox_override("normal", normal_box)
	add_theme_stylebox_override("hover", hover_box)
	add_theme_stylebox_override("pressed", hover_box)
	add_theme_color_override("font_color", Color("#613339") if accented else Color("#4A3A36"))
	add_theme_color_override("font_hover_color", Color("#613339"))
	add_theme_color_override("font_pressed_color", Color("#613339"))
	add_theme_font_size_override("font_size", 13)


func _make_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(19)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	box.shadow_color = Color(0.32, 0.20, 0.18, 0.10)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0.0, 2.0)
	return box
#endregion
