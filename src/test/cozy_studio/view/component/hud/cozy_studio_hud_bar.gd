class_name CozyStudioHudBar
extends Control

## 2.5D 温馨画室无边框悬浮 SVG 手账风 HUD 组件（纯表现层，零全屏底栏遮挡，上行发射过去分词信号）。

signal follow_camera_toggled
signal camera_mode_cycled
signal lighting_mood_toggled
signal glue_layer_toggled
signal reset_requested

const _SBX_NORMAL_PATH: String = "res://src/test/cozy_studio/assets/themes/sbx_cozy_studio_pill_normal.tres"
const _SBX_ACTIVE_PATH: String = "res://src/test/cozy_studio/assets/themes/sbx_cozy_studio_pill_active.tres"
const _ICO_SUN_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ico_cozy_studio_sun.svg"
const _ICO_MOON_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ico_cozy_studio_moon.svg"

const _COL_INK_CREAM: Color = Color("#4E3121")
const _COL_INK_SAGE: Color = Color("#2C4628")

@onready var _facing_badge_label: Label = %FacingBadgeLabel as Label
@onready var _follow_btn: Button = %FollowToggleBtn as Button
@onready var _camera_btn: Button = %CameraModeBtn as Button
@onready var _light_btn: Button = %LightMoodBtn as Button
@onready var _glue_btn: Button = %GlueToggleBtn as Button
@onready var _reset_btn: Button = %ResetBtn as Button
@onready var _hint_label: Label = %HintLabel as Label

var _sbx_normal: StyleBox = null
var _sbx_active: StyleBox = null
var _ico_sun: Texture2D = null
var _ico_moon: Texture2D = null


func _ready() -> void:
	_sbx_normal = load(_SBX_NORMAL_PATH) as StyleBox
	_sbx_active = load(_SBX_ACTIVE_PATH) as StyleBox
	_ico_sun = load(_ICO_SUN_PATH) as Texture2D
	_ico_moon = load(_ICO_MOON_PATH) as Texture2D

	if _follow_btn != null:
		_follow_btn.pressed.connect(func() -> void: follow_camera_toggled.emit())
	if _camera_btn != null:
		_camera_btn.pressed.connect(func() -> void: camera_mode_cycled.emit())
	if _light_btn != null:
		_light_btn.pressed.connect(func() -> void: lighting_mood_toggled.emit())
	if _glue_btn != null:
		_glue_btn.pressed.connect(func() -> void: glue_layer_toggled.emit())
	if _reset_btn != null:
		_reset_btn.pressed.connect(func() -> void: reset_requested.emit())


func update_status(
	follow_enabled: bool,
	cam_text: String,
	light_text: String,
	glue_enabled: bool,
	facing_view_label: String = "正视图 (Front)"
) -> void:
	if _facing_badge_label != null:
		_facing_badge_label.text = "立绘 · %s" % facing_view_label

	if _follow_btn != null:
		_follow_btn.text = "%s [F]" % ("镜头跟随" if follow_enabled else "全景固定")
		_apply_pill_toggle_visual(_follow_btn, follow_enabled)

	if _camera_btn != null:
		var clean_cam: String = cam_text.replace("视角: ", "").replace("透视", "").replace("等轴", "")
		_camera_btn.text = "%s [1-3]" % clean_cam

	if _light_btn != null:
		var is_evening: bool = light_text.contains("傍晚") or light_text.contains("暮")
		var clean_light: String = "暮色台灯" if is_evening else "午后暖阳"
		_light_btn.text = "%s [L]" % clean_light
		if is_evening and _ico_moon != null:
			_light_btn.icon = _ico_moon
		elif not is_evening and _ico_sun != null:
			_light_btn.icon = _ico_sun

	if _glue_btn != null:
		_glue_btn.text = "%s [G]" % ("赛璐璐线稿" if glue_enabled else "原始3D对比")
		_apply_pill_toggle_visual(_glue_btn, glue_enabled)

	if _hint_label != null:
		_hint_label.text = "WASD 3视图走动  ·  点按 E 互动(冲拿铁/入座摸鱼/撸猫)  ·  长按 Q/E 旋转镜头  ·  滚轮特写"


func _apply_pill_toggle_visual(btn: Button, is_active: bool) -> void:
	var target_sbx: StyleBox = _sbx_active if is_active else _sbx_normal
	if target_sbx != null:
		btn.add_theme_stylebox_override("normal", target_sbx)
	var ink_col: Color = _COL_INK_SAGE if is_active else _COL_INK_CREAM
	btn.add_theme_color_override("font_color", ink_col)
	btn.add_theme_color_override("font_focus_color", ink_col)
