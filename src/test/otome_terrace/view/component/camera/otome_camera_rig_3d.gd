@tool
class_name OtomeCameraRig3D
extends Node3D

## 乙女向户外庭院双模态平滑摄影机（漫游俯视 `-26°` ⇄ 甜蜜互动半身特写 `-13°`）。[br]
##
## [b]核心特性：[/b][br]
## 1. 漫游态提供开阔通透的晴风湖畔全景（支持 `Q/R` 或右键拖拽微旋视角与滚轮远近缩放）；[br]
## 2. 进入热点互动或点击镜头按钮时，丝滑推镜对焦男主上半身与琥珀色眼眸，上方构图自动避让底部浪漫对话卡；[br]
## 3. 提供 3D 世界锚点到 2D 屏幕坐标投影与鼠标点击地面射线求解。

#region Exports
@export var roam_pitch_deg: float = -25.0
@export var roam_distance: float = 7.45
@export var roam_fov: float = 39.5

@export var closeup_pitch_deg: float = -16.5
@export var closeup_distance: float = 4.15
@export var closeup_fov: float = 34.0
#endregion

#region Node Refs & Private State
@onready var _camera: Camera3D = %MainCamera3D as Camera3D

var _is_closeup: bool = false
var _yaw_deg: float = 4.0
var _target_yaw_deg: float = 4.0
var _zoom_roam_dist: float = 6.75
var _cur_distance: float = 6.75
var _cur_pitch_deg: float = -25.5
var _cur_fov: float = 38.5
var _focus_world: Vector3 = Vector3(-0.35, 0.95, -0.25)
#endregion


#region Lifecycle
func _ready() -> void:
	_zoom_roam_dist = roam_distance
	_cur_distance = roam_distance
	_cur_pitch_deg = roam_pitch_deg
	_cur_fov = roam_fov
	_apply_rig_transform()
#endregion


#region Public Camera Control API
## 切换全景漫游与近景半身特写模式。
func set_closeup_mode(enabled: bool) -> void:
	_is_closeup = enabled
	if enabled:
		_target_yaw_deg = clampf(_target_yaw_deg, -10.0, 10.0)


## 微调庭院水平环绕角（`Q / R` 键或鼠标右键拖拽调用，限制在 `[-24°, +24°]` 舒适视域内）。
func nudge_yaw(delta_deg: float) -> void:
	var limit: float = 12.0 if _is_closeup else 24.0
	_target_yaw_deg = clampf(_target_yaw_deg + delta_deg, -limit, limit)


## 调整全景漫游视距（鼠标滚轮调用）。
func adjust_roam_zoom(delta_dist: float) -> void:
	if _is_closeup:
		return
	_zoom_roam_dist = clampf(_zoom_roam_dist + delta_dist, 4.8, 8.8)


## 每帧平滑跟随男主 3D 坐标与镜头状态。
func step_camera_follow(delta: float, actor_pos: Vector3) -> void:
	var desired_focus: Vector3 = (
		actor_pos + Vector3(0.72, 1.02, 0.18)
		if _is_closeup
		else Vector3(
			clampf(actor_pos.x * 0.62, -1.9, 1.9),
			0.88 + actor_pos.y * 0.5,
			clampf(actor_pos.z * 0.55 - 0.35, -1.8, 1.2)
		)
	)
	var desired_dist: float = closeup_distance if _is_closeup else _zoom_roam_dist
	var desired_pitch: float = closeup_pitch_deg if _is_closeup else roam_pitch_deg
	var desired_fov: float = closeup_fov if _is_closeup else roam_fov

	var smooth: float = 1.0 - exp(-6.8 * delta)
	_focus_world = _focus_world.lerp(desired_focus, smooth)
	_yaw_deg = lerpf(_yaw_deg, _target_yaw_deg, smooth)
	_cur_distance = lerpf(_cur_distance, desired_dist, smooth)
	_cur_pitch_deg = lerpf(_cur_pitch_deg, desired_pitch, smooth)
	_cur_fov = lerpf(_cur_fov, desired_fov, smooth)
	_apply_rig_transform()


## 将 3D 热点气泡锚点投影为当前视口 2D 坐标（在相机背后时返回负无穷标记）。
func project_world_to_screen(world_pos: Vector3) -> Vector2:
	if _camera == null or _camera.is_position_behind(world_pos):
		return Vector2(-9999.0, -9999.0)
	return _camera.unproject_position(world_pos)


## 从屏幕鼠标点击位置向露台水平面投射射线，返回落点 3D 坐标（无交点时返回 `Vector3.INF`）。
func raycast_ground_plane(screen_pos: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if ray_dir.y >= -0.02:
		return Vector3.INF

	var t_lawn: float = (0.02 - ray_origin.y) / ray_dir.y
	if t_lawn <= 0.0:
		return Vector3.INF
	var hit: Vector3 = ray_origin + ray_dir * t_lawn
	var ground_h: float = OtomeTerraceConfig.estimate_ground_height(hit)
	if ground_h > 0.05:
		var t_deck: float = (ground_h - ray_origin.y) / ray_dir.y
		if t_deck > 0.0:
			hit = ray_origin + ray_dir * t_deck
	hit.x = clampf(hit.x, OtomeTerraceConfig.TERRACE_MIN_X, OtomeTerraceConfig.TERRACE_MAX_X)
	hit.z = clampf(hit.z, OtomeTerraceConfig.TERRACE_MIN_Z, OtomeTerraceConfig.TERRACE_MAX_Z)
	hit.y = OtomeTerraceConfig.estimate_ground_height(hit)
	return hit
#endregion


#region Internal Helpers
func _apply_rig_transform() -> void:
	global_position = _focus_world
	rotation_degrees = Vector3(_cur_pitch_deg, _yaw_deg, 0.0)
	if _camera != null:
		_camera.position = Vector3(0.0, 0.0, _cur_distance)
		_camera.rotation_degrees = Vector3.ZERO
		_camera.fov = _cur_fov
#endregion
