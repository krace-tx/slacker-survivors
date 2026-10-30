class_name CozyStudioView
extends BaseView

## 2.5D 温馨工作室顶层 UI 视图根协调器（继承 `BaseView`）。

signal follow_camera_toggled
signal camera_mode_cycled
signal lighting_mood_toggled
signal glue_layer_toggled
signal reset_requested

@onready var _hud_bar: CozyStudioHudBar = %HudBar as CozyStudioHudBar


func _ready() -> void:
	super._ready()
	if _hud_bar != null:
		_hud_bar.follow_camera_toggled.connect(func() -> void: follow_camera_toggled.emit())
		_hud_bar.camera_mode_cycled.connect(func() -> void: camera_mode_cycled.emit())
		_hud_bar.lighting_mood_toggled.connect(func() -> void: lighting_mood_toggled.emit())
		_hud_bar.glue_layer_toggled.connect(func() -> void: glue_layer_toggled.emit())
		_hud_bar.reset_requested.connect(func() -> void: reset_requested.emit())


func render_hud(
	follow_enabled: bool,
	cam_text: String,
	light_text: String,
	glue_enabled: bool,
	facing_view_label: String = "正视图 (Front)"
) -> void:
	if _hud_bar != null:
		_hud_bar.update_status(follow_enabled, cam_text, light_text, glue_enabled, facing_view_label)
