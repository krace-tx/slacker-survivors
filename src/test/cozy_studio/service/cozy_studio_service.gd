class_name CozyStudioService
extends RefCounted

## 2.5D 温馨工作室空间边界夹取与相机/光照预设参数服务（适配 8.80m × 7.80m × 4.15m 高挑阁楼画室）。

const PLAYER_SPAWN: Vector3 = Vector3(-0.42, 0.0, 0.68)
const PARTNER_SPAWN: Vector3 = Vector3(1.25, 0.0, -1.02)
const CAMERA_LOOK_TARGET: Vector3 = Vector3(-0.24, 1.22, -0.18)
const MOVE_SPEED: float = 2.65

## 室内可行走安全矩形与高精家具碰撞盒（X_min, Z_min, Width, Depth）
const WALK_MIN: Vector2 = Vector2(-3.45, -2.95)
const WALK_MAX: Vector2 = Vector2(2.85, 3.25)

const FURNITURE_AABBS: Array[Rect2] = [
	Rect2(-4.20, -3.76, 3.05, 2.08), # 左后 L 型双屏手绘屏工位与人体工学转椅
	Rect2(-0.76, -3.86, 1.98, 0.96), # 后墙 3.18m 双跨拱顶高书柜与黄铜滑梯
	Rect2(1.70, -2.96, 2.32, 0.78),  # 右后鼠尾草绿意式咖啡吧台
	Rect2(1.84, -0.44, 1.88, 2.98),  # 右前奶油绿簇绒 L 贵妃沙发
	Rect2(1.22, 0.94, 0.80, 1.28),   # 椭圆原木茶几
	Rect2(-3.52, 0.62, 0.88, 0.88),  # 窗边针织蒲团与酣睡橘猫
]


## 计算夹取家具障碍后的合法角色地面坐标。
func resolve_walk_position(from_pos: Vector3, next_pos: Vector3) -> Vector3:
	var candidate := Vector2(
		clampf(next_pos.x, WALK_MIN.x, WALK_MAX.x),
		clampf(next_pos.z, WALK_MIN.y, WALK_MAX.y)
	)
	if not _overlaps_furniture(candidate):
		return Vector3(candidate.x, 0.0, candidate.y)

	# 分轴滑动，保证贴着桌沿/沙发边缘顺滑移动不卡死
	var slide_x := Vector2(candidate.x, from_pos.z)
	if not _overlaps_furniture(slide_x):
		return Vector3(slide_x.x, 0.0, slide_x.y)

	var slide_z := Vector2(from_pos.x, candidate.y)
	if not _overlaps_furniture(slide_z):
		return Vector3(slide_z.x, 0.0, slide_z.y)

	return Vector3(from_pos.x, 0.0, from_pos.z)


func _overlaps_furniture(pt: Vector2) -> bool:
	var radius: float = 0.24
	for box: Rect2 in FURNITURE_AABBS:
		var expanded := box.grow(radius)
		if expanded.has_point(pt):
			return true
	return false


## 获取相机预设的标题描述。
func get_camera_mode_label(mode: CozyStudioState.CameraMode) -> String:
	match mode:
		CozyStudioState.CameraMode.TELEPHOTO_25:
			return "视角: 24.5° 长焦透视"
		CozyStudioState.CameraMode.ORTHO_DIORAMA:
			return "视角: 正交等轴箱庭"
		CozyStudioState.CameraMode.WIDE_70_COMPARE:
			return "视角: 68° 广角对比"
	return "视角: 默认"


## 获取光照氛围的标题描述。
func get_lighting_mood_label(mood: CozyStudioState.LightingMood) -> String:
	match mood:
		CozyStudioState.LightingMood.AFTERNOON_SUN:
			return "光影: 午后暖阳"
		CozyStudioState.LightingMood.COZY_EVENING:
			return "光影: 傍晚台灯"
	return "光影: 默认"
