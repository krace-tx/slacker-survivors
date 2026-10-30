class_name CozyStudioHudBar
extends PanelContainer

## 2.5D 温馨工作室顶部轻量操控与状态胶囊栏（纯表现组件，上行发射过去分词信号）。

signal follow_camera_toggled
signal camera_mode_cycled
signal lighting_mood_toggled
signal glue_layer_toggled
signal reset_requested

@onready var _follow_btn: Button = %FollowToggleBtn as Button
@onready var _camera_btn: Button = %CameraModeBtn as Button
@onready var _light_btn: Button = %LightMoodBtn as Button
@onready var _glue_btn: Button = %GlueToggleBtn as Button
@onready var _reset_btn: Button = %ResetBtn as Button
@onready var _hint_label: Label = %HintLabel as Label


func _ready() -> void:
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
	if _follow_btn != null:
		_follow_btn.text = "跟随: %s [F]" % ("开启" if follow_enabled else "全景固定")
	if _camera_btn != null:
		_camera_btn.text = "%s [1/2/3]" % cam_text
	if _light_btn != null:
		_light_btn.text = "%s [L]" % light_text
	if _glue_btn != null:
		_glue_btn.text = "二次元画风: %s [G]" % ("赛璐璐+线稿" if glue_enabled else "原始3D对比")
	if _hint_label != null:
		_hint_label.text = (
			"当前角色立绘: %s  |  WASD: 正/侧/背 3 视图序列帧走动  |  Q / E: 旋转镜头(自动切换相对 3 视图并保持同面)  |  滚轮: 推拉"
			% facing_view_label
		)
