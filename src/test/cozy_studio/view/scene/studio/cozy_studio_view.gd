class_name CozyStudioView
extends BaseView

## 2.5D 温馨工作室顶层 UI 视图根协调器（继承 `BaseView`，编排无框手账顶栏与 3D 投影交互气泡层）。

signal follow_camera_toggled
signal camera_mode_cycled
signal lighting_mood_toggled
signal glue_layer_toggled
signal reset_requested
signal interact_requested

@onready var _hud_bar: CozyStudioHudBar = %HudBar as CozyStudioHudBar
@onready var _interact_overlay: CozyInteractOverlay = %InteractOverlay as CozyInteractOverlay


func _ready() -> void:
	super._ready()
	if _hud_bar != null:
		_hud_bar.follow_camera_toggled.connect(func() -> void: follow_camera_toggled.emit())
		_hud_bar.camera_mode_cycled.connect(func() -> void: camera_mode_cycled.emit())
		_hud_bar.lighting_mood_toggled.connect(func() -> void: lighting_mood_toggled.emit())
		_hud_bar.glue_layer_toggled.connect(func() -> void: glue_layer_toggled.emit())
		_hud_bar.reset_requested.connect(func() -> void: reset_requested.emit())
	if _interact_overlay != null:
		_interact_overlay.interact_requested.connect(func() -> void: interact_requested.emit())


func render_hud(
	follow_enabled: bool,
	cam_text: String,
	light_text: String,
	glue_enabled: bool,
	facing_view_label: String = "正视图 (Front)"
) -> void:
	if _hud_bar != null:
		_hud_bar.update_status(follow_enabled, cam_text, light_text, glue_enabled, facing_view_label)


func update_interact_prompt(
	spot: CozyStudioState.InteractSpotId,
	world_pos: Vector3,
	action_text: String,
	is_seated_here: bool
) -> void:
	if _interact_overlay != null:
		_interact_overlay.set_prompt_state(spot, world_pos, action_text, is_seated_here)


func spawn_interact_bubbles(spot: CozyStudioState.InteractSpotId, world_origin: Vector3) -> void:
	if _interact_overlay != null:
		_interact_overlay.spawn_spot_bubbles(spot, world_origin)


func tick_view_overlay(delta: float, camera: Camera3D) -> void:
	if _interact_overlay != null:
		_interact_overlay.tick_overlay(delta, camera)
