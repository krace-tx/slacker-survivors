class_name CozyCameraRig3D
extends Node3D

## 2.5D 三段式解耦相机支架组件（微死区 + 速度前瞻 + 阁楼安全边界 + 屏幕空间暖棕二次元钢笔线稿后处理）。

signal yaw_changed(yaw_deg: float)

const _ANIME_OUTLINE_SHADER_PATH: String = "res://src/test/cozy_studio/assets/shaders/shd_cozy_studio_anime_outline.gdshader"

const DEFAULT_YAW_DEG: float = 37.0
const DEFAULT_PITCH_DEG: float = -28.5
const FOCUS_HEIGHT: float = 1.18

const FOLLOW_BOOM_DIST: float = 13.6
const PANORAMA_BOOM_DIST: float = 16.8
const WIDE_BOOM_DIST: float = 4.95
const MIN_ZOOM_DIST: float = 9.2
const MAX_ZOOM_DIST: float = 18.4

const DEADZONE_RADIUS: float = 0.22
const LOOK_AHEAD_MAX: float = 0.45
const FOLLOW_SHARPNESS: float = 7.2
const LOOK_AHEAD_SHARPNESS: float = 4.8
const YAW_SHARPNESS: float = 10.5
const ZOOM_SHARPNESS: float = 8.0
const YAW_SPEED_DEG: float = 68.0

## 相机跟随焦点安全矩形，配合 4.15m 高挑阁楼墙面确保背景饱满不穿帮
const RIG_BOUNDS_MIN: Vector2 = Vector2(-1.65, -1.35)
const RIG_BOUNDS_MAX: Vector2 = Vector2(1.25, 1.35)

@onready var _yaw_pivot: Node3D = %YawPivot as Node3D
@onready var _pitch_pivot: Node3D = %PitchPivot as Node3D
@onready var _camera: Camera3D = %MainCamera as Camera3D
@onready var _outline_quad: MeshInstance3D = %AnimeInkOutlineQuad as MeshInstance3D

var _camera_mode: CozyStudioState.CameraMode = CozyStudioState.CameraMode.TELEPHOTO_25
var _follow_enabled: bool = true
var _target_yaw_deg: float = DEFAULT_YAW_DEG
var _current_yaw_deg: float = DEFAULT_YAW_DEG
var _user_zoom_offset: float = 0.0
var _current_boom_dist: float = FOLLOW_BOOM_DIST
var _deadzone_anchor: Vector2 = Vector2(-0.42, 0.68)
var _look_ahead_xz: Vector2 = Vector2.ZERO
var _outline_mat: ShaderMaterial = null


func _ready() -> void:
	_setup_anime_outline_quad()
	_apply_pivots_immediate()


func get_camera() -> Camera3D:
	return _camera


func get_yaw_deg() -> float:
	return _current_yaw_deg


func get_yaw_rad() -> float:
	return deg_to_rad(_current_yaw_deg)


## 获取当前立牌应匹配的接地后仰角（与 -28.5° 阁楼长焦俯角协调匹配）。
func get_standee_tilt_deg() -> float:
	return -16.0 if _camera_mode == CozyStudioState.CameraMode.WIDE_70_COMPARE else -20.0


func set_stage_environment(env: Environment) -> void:
	if _camera != null and env != null:
		_camera.environment = env


## 开关 3D 场地专属暖棕钢笔线稿后处理（自动免疫 2D 立牌角色）。
func set_anime_outline_enabled(enabled: bool) -> void:
	if _outline_quad != null:
		_outline_quad.visible = enabled


func _setup_anime_outline_quad() -> void:
	if _outline_quad == null:
		return
	var shd: Shader = load(_ANIME_OUTLINE_SHADER_PATH) as Shader
	if shd == null:
		return
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = shd
	_outline_mat.render_priority = -2

	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	_outline_quad.mesh = qm
	_outline_quad.extra_cull_margin = 16384.0
	_outline_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_quad.material_override = _outline_mat


func set_follow_enabled(enabled: bool, snap_target: Vector3, immediate: bool = false) -> void:
	_follow_enabled = enabled
	if enabled:
		_deadzone_anchor = Vector2(snap_target.x, snap_target.z)
	if immediate:
		var focus: Vector3 = _compute_desired_focus()
		position = focus
		_current_boom_dist = _compute_desired_boom_dist()
		_apply_pivots_immediate()


func set_camera_mode(mode: CozyStudioState.CameraMode, immediate: bool = false) -> void:
	_camera_mode = mode
	if _camera == null:
		return
	match _camera_mode:
		CozyStudioState.CameraMode.TELEPHOTO_25:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 24.5
		CozyStudioState.CameraMode.ORTHO_DIORAMA:
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = 5.95 if _follow_enabled else 7.25
		CozyStudioState.CameraMode.WIDE_70_COMPARE:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 68.0
	if immediate:
		_current_boom_dist = _compute_desired_boom_dist()
		_apply_pivots_immediate()


func adjust_zoom(wheel_delta: float) -> void:
	_user_zoom_offset = clampf(_user_zoom_offset + wheel_delta, -3.6, 3.8)


func reset_rig(spawn_pos: Vector3) -> void:
	_target_yaw_deg = DEFAULT_YAW_DEG
	_current_yaw_deg = DEFAULT_YAW_DEG
	_user_zoom_offset = 0.0
	_look_ahead_xz = Vector2.ZERO
	_deadzone_anchor = Vector2(spawn_pos.x, spawn_pos.z)
	position = _compute_desired_focus()
	_current_boom_dist = _compute_desired_boom_dist()
	_apply_pivots_immediate()
	yaw_changed.emit(_current_yaw_deg)


## 每帧推进四步阻尼跟随与水平环绕，并在偏航角变化时向外广播以保持全场 2D 角色视平面平行。
func tick_rig(delta: float, player_pos: Vector3, world_velocity: Vector3, yaw_input: float) -> void:
	if absf(yaw_input) > 0.01:
		_target_yaw_deg = wrapf(_target_yaw_deg + yaw_input * YAW_SPEED_DEG * delta, -180.0, 180.0)

	var prev_yaw: float = _current_yaw_deg
	var yaw_weight: float = 1.0 - exp(-YAW_SHARPNESS * delta)
	var yaw_diff: float = wrapf(_target_yaw_deg - _current_yaw_deg, -180.0, 180.0)
	_current_yaw_deg = wrapf(_current_yaw_deg + yaw_diff * yaw_weight, -180.0, 180.0)

	if _follow_enabled:
		# Step 1: 圆形软死区（原地小幅走动不晃镜头）
		var player_xz := Vector2(player_pos.x, player_pos.z)
		var offset_from_anchor: Vector2 = player_xz - _deadzone_anchor
		var dist: float = offset_from_anchor.length()
		if dist > DEADZONE_RADIUS:
			_deadzone_anchor += offset_from_anchor.normalized() * (dist - DEADZONE_RADIUS)

		# Step 2: 移动方向前瞻偏移（Look-Ahead）
		var vel_xz := Vector2(world_velocity.x, world_velocity.z)
		var target_ahead: Vector2 = (
			vel_xz.normalized() * LOOK_AHEAD_MAX
			if vel_xz.length() > 0.15
			else Vector2.ZERO
		)
		_look_ahead_xz = _look_ahead_xz.lerp(target_ahead, 1.0 - exp(-LOOK_AHEAD_SHARPNESS * delta))
	else:
		_look_ahead_xz = _look_ahead_xz.lerp(Vector2.ZERO, 1.0 - exp(-LOOK_AHEAD_SHARPNESS * delta))

	# Step 3 & 4: 房间软边界夹取 + 帧率无关指数平滑
	var desired_focus: Vector3 = _compute_desired_focus()
	position = position.lerp(desired_focus, 1.0 - exp(-FOLLOW_SHARPNESS * delta))

	var desired_boom: float = _compute_desired_boom_dist()
	_current_boom_dist = lerpf(_current_boom_dist, desired_boom, 1.0 - exp(-ZOOM_SHARPNESS * delta))
	if _camera != null and _camera_mode == CozyStudioState.CameraMode.ORTHO_DIORAMA:
		var target_ortho: float = clampf((5.95 if _follow_enabled else 7.25) + _user_zoom_offset * 0.35, 4.2, 8.8)
		_camera.size = lerpf(_camera.size, target_ortho, 1.0 - exp(-ZOOM_SHARPNESS * delta))

	_apply_pivots_immediate()

	if absf(wrapf(_current_yaw_deg - prev_yaw, -180.0, 180.0)) > 0.005:
		yaw_changed.emit(_current_yaw_deg)


func _compute_desired_focus() -> Vector3:
	if not _follow_enabled:
		return Vector3(CozyStudioService.CAMERA_LOOK_TARGET.x, 0.0, CozyStudioService.CAMERA_LOOK_TARGET.z)
	var raw_xz: Vector2 = _deadzone_anchor + _look_ahead_xz
	return Vector3(
		clampf(raw_xz.x, RIG_BOUNDS_MIN.x, RIG_BOUNDS_MAX.x),
		0.0,
		clampf(raw_xz.y, RIG_BOUNDS_MIN.y, RIG_BOUNDS_MAX.y)
	)


func _compute_desired_boom_dist() -> float:
	var base_dist: float = FOLLOW_BOOM_DIST if _follow_enabled else PANORAMA_BOOM_DIST
	if _camera_mode == CozyStudioState.CameraMode.WIDE_70_COMPARE:
		base_dist = WIDE_BOOM_DIST if _follow_enabled else 5.45
	return clampf(base_dist + _user_zoom_offset, MIN_ZOOM_DIST if _camera_mode != CozyStudioState.CameraMode.WIDE_70_COMPARE else 3.4, MAX_ZOOM_DIST)


func _apply_pivots_immediate() -> void:
	if _yaw_pivot != null:
		_yaw_pivot.position = Vector3(0.0, FOCUS_HEIGHT, 0.0)
		_yaw_pivot.rotation_degrees = Vector3(0.0, _current_yaw_deg, 0.0)
	if _pitch_pivot != null:
		_pitch_pivot.position = Vector3.ZERO
		_pitch_pivot.rotation_degrees = Vector3(DEFAULT_PITCH_DEG, 0.0, 0.0)
	if _camera != null:
		_camera.position = Vector3(0.0, 0.0, _current_boom_dist)
		_camera.rotation_degrees = Vector3.ZERO
