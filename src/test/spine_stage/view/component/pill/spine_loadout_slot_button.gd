class_name SpineLoadoutSlotButton
extends Button

## 2.5D 舞台底部装备栏可复用胶囊槽位按钮组件（Slate Dark 主题，支持激活态描边高亮）。[br]
##
## [b]核心职责：[/b][br]
## 1. 展示快捷键角标与武器/套装名称；[br]
## 2. 根据激活态与主题强调色切换 [StyleBoxFlat] 圆角胶囊边框与底色；[br]
## 3. 点击时上行发射 [signal slot_selected] 携带 [member slot_index]。

#region Signals
## 当玩家点击该槽位按钮时发射，携带槽位下标。
signal slot_selected(index: int)
#endregion

#region Exports & State
@export var slot_index: int = 0

var _normal_style: StyleBoxFlat = null
var _hover_style: StyleBoxFlat = null
var _pressed_style: StyleBoxFlat = null
#endregion


#region Lifecycle
func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ensure_styles()
	pressed.connect(_on_button_pressed)
#endregion


#region Public API
## 刷新槽位文案、强调色与选中高亮状态。
func set_slot_display(hotkey_label: String, item_title: String, accent_color: Color, is_active: bool) -> void:
	_ensure_styles()
	if hotkey_label.is_empty():
		text = item_title
	else:
		text = "[%s] %s" % [hotkey_label, item_title]

	if is_active:
		_normal_style.bg_color = Color(accent_color.r * 0.24, accent_color.g * 0.26, accent_color.b * 0.32, 0.94)
		_normal_style.border_color = accent_color
		_normal_style.set_border_width_all(2)
		_hover_style.bg_color = Color(accent_color.r * 0.30, accent_color.g * 0.32, accent_color.b * 0.38, 0.96)
		_hover_style.border_color = accent_color.lightened(0.18)
		_hover_style.set_border_width_all(2)
		add_theme_color_override("font_color", Color("#F8FAFC"))
		add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	else:
		_normal_style.bg_color = Color(0.09, 0.13, 0.20, 0.84)
		_normal_style.border_color = Color("#334155")
		_normal_style.set_border_width_all(1)
		_hover_style.bg_color = Color(0.15, 0.20, 0.30, 0.92)
		_hover_style.border_color = accent_color.darkened(0.15)
		_hover_style.set_border_width_all(1)
		add_theme_color_override("font_color", Color("#CBD5E1"))
		add_theme_color_override("font_hover_color", Color("#F8FAFC"))

	_pressed_style.bg_color = Color(accent_color.r * 0.34, accent_color.g * 0.36, accent_color.b * 0.44, 0.98)
	_pressed_style.border_color = accent_color
	_pressed_style.set_border_width_all(2)
#endregion


#region Internal Helpers
func _ensure_styles() -> void:
	if _normal_style != null:
		return
	_normal_style = _make_capsule_style(Color(0.09, 0.13, 0.20, 0.84), Color("#334155"), 1)
	_hover_style = _make_capsule_style(Color(0.15, 0.20, 0.30, 0.92), Color("#475569"), 1)
	_pressed_style = _make_capsule_style(Color(0.19, 0.26, 0.38, 0.96), Color("#38BDF8"), 2)

	add_theme_stylebox_override("normal", _normal_style)
	add_theme_stylebox_override("hover", _hover_style)
	add_theme_stylebox_override("pressed", _pressed_style)
	add_theme_font_size_override("font_size", 13)


func _make_capsule_style(bg: Color, border: Color, border_px: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_px)
	box.set_corner_radius_all(8)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box


func _on_button_pressed() -> void:
	slot_selected.emit(slot_index)
#endregion
