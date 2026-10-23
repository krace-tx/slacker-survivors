class_name SoulsCameraRig3D
extends Node3D

## 3D 魂系第三人称平滑跟随与目标锁定（Lock-On）相机组件（位于 src/test/souls_arena/view/component/camera/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. [b]平滑跟随（Follow）[/b]：以阻尼插值（`lerp`）追踪玩家 3D 空间坐标，消除生硬抖动；[br]
## 2. [b]魂系目标锁定（Target Lock-On）[/b]：开启锁定时自动计算「玩家 -> Boss」视线矢量，将相机置于玩家右后方过肩视角并动态缩放视距，同时在 Boss 胸口渲染 3D 锁定准星；[br]
## 3. [b]相机坐标系 3D 移动投影[/b]：提供 [method compute_world_move_dir]，将玩家 `WASD` 输入转换为相对于当前相机朝向的 3D 地面方向向量（支持锁定状态下的环绕侧步走位 Circle-Strafe）。


#region 节点引用与私有状态

@onready var _camera: Camera3D = %Camera3D as Camera3D
@onready var _lock_reticle: Label3D = %LockReticle3D as Label3D

var _follow_actor: Node3D = null
var _lock_target: Node3D = null
var _is_locked_on: bool = true

var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-18.0)
var _current_focus_pos: Vector3 = Vector3.ZERO
var _reticle_pulse: float = 0.0
var _zoom_offset: float = 0.0
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _shake_clock: float = 0.0
var _fov_punch: float = 0.0
const _BASE_FOV: float = 56.0

#endregion


#region 绑定与锁定控制接口

func setup_targets(player_actor: Node3D, boss_actor: Node3D, locked_on: bool = true) -> void:
	_follow_actor = player_actor
	_lock_target = boss_actor
	_is_locked_on = locked_on
	if _follow_actor != null:
		_current_focus_pos = _follow_actor.global_position
		global_position = _current_focus_pos


func set_locked_on(locked: bool) -> void:
	_is_locked_on = locked
	if _lock_reticle != null:
		_lock_reticle.visible = _is_locked_on and (_lock_target != null)


func is_locked_on() -> bool:
	return _is_locked_on


func rotate_free_yaw(delta_yaw_rad: float) -> void:
	if not _is_locked_on:
		_yaw = wrapf(_yaw + delta_yaw_rad, -PI, PI)


func adjust_zoom(delta_zoom: float) -> void:
	_zoom_offset = clampf(_zoom_offset + delta_zoom, -1.8, 3.2)


## 触发 3D 镜头打击震屏与视野冲击缩放（弹反、处决、重击、霸体碰撞时调用）。
func trigger_impact_shake(intensity: float = 0.18, duration: float = 0.22, fov_kick: float = -3.2) -> void:
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_timer = maxf(_shake_timer, duration)
	_fov_punch = clampf(_fov_punch + fov_kick, -6.5, 5.5)


## 将平面输入 `input_xz` (`A/D` 为 X，`W/S` 为 Y) 投影为相对于当前相机水平朝向的 3D 地面单位向量。
func compute_world_move_dir(input_xz: Vector2) -> Vector3:
	if input_xz.length_squared() <= 0.0001:
		return Vector3.ZERO

	var cam_basis: Basis = _camera.global_transform.basis if _camera != null else global_transform.basis
	var cam_forward: Vector3 = -cam_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	var cam_right: Vector3 = cam_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var move_vec: Vector3 = (cam_right * input_xz.x) + (cam_forward * (-input_xz.y))
	if move_vec.length_squared() > 0.0001:
		return move_vec.normalized()
	return Vector3.ZERO

#endregion


#region 每帧平滑追踪与锁定构图

func tick_camera(delta: float) -> void:
	if _follow_actor == null or _camera == null:
		return

	var player_pos: Vector3 = _follow_actor.global_position
	_current_focus_pos = _current_focus_pos.lerp(player_pos, clampf(delta * 10.0, 0.0, 1.0))

	if _is_locked_on and _lock_target != null:
		var boss_pos: Vector3 = _lock_target.global_position
		var to_boss: Vector3 = boss_pos - player_pos
		to_boss.y = 0.0
		var dist: float = to_boss.length()
		if dist > 0.25:
			var target_yaw: float = atan2(-to_boss.x, -to_boss.z)
			_yaw = lerp_angle(_yaw, target_yaw, clampf(delta * 7.5, 0.0, 1.0))

		# 过肩锁定构图：相机位于玩家后方偏右，随双方距离动态拉远
		var cam_dist: float = clampf(5.4 + dist * 0.36 + _zoom_offset, 4.8, 12.0)
		var cam_height: float = clampf(3.0 + dist * 0.12 + _zoom_offset * 0.25, 2.7, 5.2)
		var back_dir: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
		var right_dir: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))

		var desired_cam_pos: Vector3 = (
			_current_focus_pos
			+ back_dir * cam_dist
			+ right_dir * 0.85
			+ Vector3(0.0, cam_height, 0.0)
		)
		_camera.global_position = _camera.global_position.lerp(desired_cam_pos, clampf(delta * 9.0, 0.0, 1.0))

		var look_at_point: Vector3 = _current_focus_pos.lerp(boss_pos, 0.52) + Vector3(0.0, 1.35, 0.0)
		_camera.look_at(look_at_point, Vector3.UP)

		# 更新 Boss 胸口锁定准星位置与呼吸脉冲
		if _lock_reticle != null:
			_lock_reticle.visible = true
			_lock_reticle.global_position = boss_pos + Vector3(0.0, 1.45, 0.0)
			_reticle_pulse += delta * 6.0
			var pulse_scale: float = 1.0 + sin(_reticle_pulse) * 0.10
			_lock_reticle.scale = Vector3.ONE * pulse_scale
	else:
		# 自由跟随模式：使用左右方向键可旋转视角
		if Input.is_physical_key_pressed(KEY_LEFT):
			_yaw += 1.8 * delta
		if Input.is_physical_key_pressed(KEY_RIGHT):
			_yaw -= 1.8 * delta

		var cam_dist_free: float = clampf(6.8 + _zoom_offset, 4.8, 11.5)
		var cam_height_free: float = clampf(3.4 + _zoom_offset * 0.25, 2.6, 5.0)
		var back_dir_free: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
		var desired_pos_free: Vector3 = (
			_current_focus_pos
			+ back_dir_free * cam_dist_free
			+ Vector3(0.0, cam_height_free, 0.0)
		)
		_camera.global_position = _camera.global_position.lerp(desired_pos_free, clampf(delta * 9.0, 0.0, 1.0))
		_camera.look_at(_current_focus_pos + Vector3(0.0, 1.25, 0.0), Vector3.UP)

		if _lock_reticle != null:
			_lock_reticle.visible = false

	# 叠加打击震屏偏移与动态 FOV 脉冲恢复
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		_shake_clock += delta * 58.0
		var decay: float = clampf(_shake_timer / 0.24, 0.0, 1.0)
		var offset_x: float = sin(_shake_clock * 1.3) * _shake_intensity * decay
		var offset_y: float = cos(_shake_clock * 1.9) * _shake_intensity * decay * 0.85
		_camera.h_offset = offset_x
		_camera.v_offset = offset_y
		if _shake_timer <= 0.0:
			_shake_intensity = 0.0
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0

	_fov_punch = lerpf(_fov_punch, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_camera.fov = _BASE_FOV + _fov_punch

#endregion
