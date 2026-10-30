@tool
class_name OtomeDialogueCard
extends PanelContainer

## 乙女向暖奶油半透明浪漫对话卡组件（含角色铭牌、地点花签、柔和逐字显现正文与双分支心动选项）。[br]
##
## 纯被动视图组件：仅消费上层传入的状态快照并向外发射 [signal choice_selected]。

#region Signals
## 当玩家点击双分支心动回复选项时发出（`0` 为选项 A，`1` 为选项 B）。
signal choice_selected(choice_index: int)
#endregion

#region Node Refs & Private State
@onready var _speaker_name_label: Label = %SpeakerNameLabel as Label
@onready var _spot_tag_badge: PanelContainer = %SpotTagBadge as PanelContainer
@onready var _spot_tag_label: Label = %SpotTagLabel as Label
@onready var _dialogue_body_label: Label = %DialogueBodyLabel as Label
@onready var _choices_row: HBoxContainer = %ChoicesRow as HBoxContainer
@onready var _choice_a_button: Button = %ChoiceAButton as Button
@onready var _choice_b_button: Button = %ChoiceBButton as Button

var _last_body_text: String = ""
var _type_tween: Tween = null
#endregion


#region Lifecycle
func _ready() -> void:
	if not Engine.is_editor_hint() or not has_theme_stylebox_override("panel"):
		_apply_card_styles()
	if _choice_a_button != null:
		_choice_a_button.focus_mode = Control.FOCUS_NONE
		_choice_a_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not Engine.is_editor_hint():
			_choice_a_button.pressed.connect(_on_choice_a_pressed)
	if _choice_b_button != null:
		_choice_b_button.focus_mode = Control.FOCUS_NONE
		_choice_b_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not Engine.is_editor_hint():
			_choice_b_button.pressed.connect(_on_choice_b_pressed)
#endregion


#region Public Render API
## 刷新对话卡角色名、热点标签、台词正文及双分支互动选项按钮。
func render_dialogue(
	speaker: String,
	spot_tag: String,
	body_text: String,
	choices_on: bool,
	choice_a: String,
	choice_b: String
) -> void:
	if _speaker_name_label != null:
		_speaker_name_label.text = "✦ %s" % speaker
	if _spot_tag_label != null:
		_spot_tag_label.text = spot_tag

	if _dialogue_body_label != null and _last_body_text != body_text:
		_last_body_text = body_text
		_dialogue_body_label.text = body_text
		if not Engine.is_editor_hint() and is_inside_tree():
			if _type_tween != null and _type_tween.is_valid():
				_type_tween.kill()
			_dialogue_body_label.visible_ratio = 0.15
			_type_tween = create_tween()
			_type_tween.tween_property(_dialogue_body_label, "visible_ratio", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			_dialogue_body_label.visible_ratio = 1.0

	if _choices_row != null:
		_choices_row.visible = choices_on
	if _choice_a_button != null and not choice_a.is_empty():
		_choice_a_button.text = "♡  %s" % choice_a
	if _choice_b_button != null and not choice_b.is_empty():
		_choice_b_button.text = "✦  %s" % choice_b
#endregion


#region Internal Styling & Callbacks
func _apply_card_styles() -> void:
	var card_box := StyleBoxFlat.new()
	card_box.bg_color = Color(1.0, 0.992, 0.978, 0.93)
	card_box.border_color = Color("#D9A796")
	card_box.set_border_width_all(2)
	card_box.set_corner_radius_all(18)
	card_box.content_margin_left = 22.0
	card_box.content_margin_right = 22.0
	card_box.content_margin_top = 14.0
	card_box.content_margin_bottom = 14.0
	card_box.shadow_color = Color(0.30, 0.18, 0.16, 0.14)
	card_box.shadow_size = 10
	card_box.shadow_offset = Vector2(0.0, 4.0)
	add_theme_stylebox_override("panel", card_box)

	if _spot_tag_badge != null:
		var badge_box := StyleBoxFlat.new()
		badge_box.bg_color = Color(0.96, 0.88, 0.85, 0.95)
		badge_box.border_color = Color("#D9A796")
		badge_box.set_border_width_all(1)
		badge_box.set_corner_radius_all(11)
		badge_box.content_margin_left = 10.0
		badge_box.content_margin_right = 10.0
		badge_box.content_margin_top = 2.0
		badge_box.content_margin_bottom = 2.0
		_spot_tag_badge.add_theme_stylebox_override("panel", badge_box)

	if _speaker_name_label != null:
		_speaker_name_label.add_theme_color_override("font_color", Color("#5A3935"))
		_speaker_name_label.add_theme_font_size_override("font_size", 17)
	if _spot_tag_label != null:
		_spot_tag_label.add_theme_color_override("font_color", Color("#7D524B"))
		_spot_tag_label.add_theme_font_size_override("font_size", 12)
	if _dialogue_body_label != null:
		_dialogue_body_label.add_theme_color_override("font_color", Color("#4A3A36"))
		_dialogue_body_label.add_theme_font_size_override("font_size", 15)

	_style_choice_button(_choice_a_button)
	_style_choice_button(_choice_b_button)


func _style_choice_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.995, 0.94, 0.93, 0.96)
	normal.border_color = Color("#DF8B96")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(15)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.99, 0.88, 0.87, 0.99)
	hover.border_color = Color("#D46A7E")
	hover.set_border_width_all(2)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color("#5C3338"))
	btn.add_theme_color_override("font_hover_color", Color("#4A2429"))
	btn.add_theme_color_override("font_pressed_color", Color("#4A2429"))
	btn.add_theme_font_size_override("font_size", 13)


func _on_choice_a_pressed() -> void:
	choice_selected.emit(0)


func _on_choice_b_pressed() -> void:
	choice_selected.emit(1)
#endregion
