class_name SpineCameraRig3D
extends Node3D

## 2.5D 微俯视箱庭平滑跟随与打击微震屏相机组件。[br]
##
## [b]核心职责：[/b][br]
## 1. 以经典 [code]-32°[/code] 俯角平滑追踪主角 3D 走位（兼顾地面长阴影可见度与立牌正面透视）；[br]
## 2. 提供近战命中时的瞬时衰减微震屏冲量（[method add_trauma]）。

#region Exports
@export var camera_offset: Vector3 = Vector3(0.0, 5.25, 7.65)
@export var camera_pitch_deg: float = -31.0
@export var follow_damping: float = 7.5
#endregion

#region Private State & Node Refs
@onready var _camera: Camera3D = %MainCamera3D as Camera3D

var _trauma: float = 0.0
var _shake_time: float = 0.0
#endregion


#region Lifecycle
func _ready() -> void:
	if _camera != null:
		_camera.position = camera_offset
		_camera.rotation_degrees = Vector3(camera_pitch_deg, 0.0, 0.0)
		_camera.current = true
#endregion


#region Public API
## 平滑跟随目标世界坐标并更新微震屏偏移。
func tick_follow(delta: float, target_pos: Vector3) -> void:
	var focus := Vector3(
		clampf(target_pos.x * 0.55, -2.6, 2.6),
		target_pos.y * 0.22,
		clampf(target_pos.z * 0.45, -1.8, 2.2)
	)
	global_position = global_position.lerp(focus, 1.0 - exp(-follow_damping * delta))

	if _camera == null:
		return
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - delta * 2.8)
		_shake_time += delta * 42.0
		var mag: float = _trauma * _trauma * 0.14
		_camera.h_offset = sin(_shake_time * 1.3) * mag
		_camera.v_offset = cos(_shake_time * 1.7) * mag * 0.75
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


## 注入一次受控震屏强度（0.0 ~ 1.0）。
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
#endregion
