class_name CozyStudioService
extends RefCounted

## 2.5D 温馨工作室空间边界夹取、3D 家具邻近探测评分与入座槽位契约服务。

const PLAYER_SPAWN: Vector3 = Vector3(-0.42, 0.0, 0.68)
const PARTNER_SPAWN: Vector3 = Vector3(1.25, 0.0, -1.02)
const CAMERA_LOOK_TARGET: Vector3 = Vector3(-0.24, 1.22, -0.18)
const MOVE_SPEED: float = 2.65

## 室内可行走安全矩形与高精家具碰撞盒（X_min, Z_min, Width, Depth）
const WALK_MIN: Vector2 = Vector2(-3.45, -2.95)
const WALK_MAX: Vector2 = Vector2(3.45, 3.25)

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


## 基于「距离权重 + 角色前向朝向点积权重」评选最优可交互 3D 家具目标。
func find_best_interact_spot(
	player_pos: Vector3,
	player_facing: Vector3
) -> CozyStudioState.InteractSpotId:
	var candidates: Array[CozyStudioState.InteractSpotId] = [
		CozyStudioState.InteractSpotId.COFFEE_BAR,
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR,
		CozyStudioState.InteractSpotId.LOUNGE_SOFA,
		CozyStudioState.InteractSpotId.SLEEPING_CAT,
	]
	var flat_pos := Vector2(player_pos.x, player_pos.z)
	var flat_fwd := Vector2(player_facing.x, player_facing.z)
	if flat_fwd.length_squared() > 0.0001:
		flat_fwd = flat_fwd.normalized()

	var best_spot: CozyStudioState.InteractSpotId = CozyStudioState.InteractSpotId.NONE
	var best_score: float = -1.0

	for spot: CozyStudioState.InteractSpotId in candidates:
		var sense_center: Vector2 = _get_spot_sense_xz(spot)
		var sense_radius: float = _get_spot_sense_radius(spot)
		var delta: Vector2 = sense_center - flat_pos
		var dist: float = delta.length()
		if dist > sense_radius:
			continue

		var dist_score: float = 1.0 - (dist / sense_radius)
		var align_score: float = 0.5
		if dist > 0.02 and flat_fwd.length_squared() > 0.0001:
			align_score = clampf(flat_fwd.dot(delta / dist) * 0.5 + 0.5, 0.0, 1.0)
		var total_score: float = dist_score * 0.76 + align_score * 0.24
		if total_score > best_score:
			best_score = total_score
			best_spot = spot

	return best_spot


func _get_spot_sense_xz(spot: CozyStudioState.InteractSpotId) -> Vector2:
	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			return Vector2(3.32, -2.14)
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
			return Vector2(-2.46, -1.96)
		CozyStudioState.InteractSpotId.LOUNGE_SOFA:
			return Vector2(2.14, 0.56)
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			return Vector2(-2.92, 1.05)
	return Vector2.ZERO


func _get_spot_sense_radius(spot: CozyStudioState.InteractSpotId) -> float:
	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			return 1.55
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
			return 1.52
		CozyStudioState.InteractSpotId.LOUNGE_SOFA:
			return 1.58
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			return 1.48
	return 0.0


## 获取交互点在 3D 世界中悬浮 SVG 胶囊提示的锚点坐标。
func get_spot_prompt_world_pos(
	spot: CozyStudioState.InteractSpotId,
	is_seated_here: bool = false
) -> Vector3:
	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			return Vector3(3.44, 1.54, -2.42)
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
			return Vector3(-2.64, 1.66 if is_seated_here else 1.24, -2.32)
		CozyStudioState.InteractSpotId.LOUNGE_SOFA:
			return Vector3(2.74, 1.66 if is_seated_here else 1.04, 1.05)
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			return Vector3(-3.04, 0.56, 1.20)
	return Vector3.ZERO


## 获取交互胶囊显示的中文动作文案。
func get_spot_prompt_text(
	spot: CozyStudioState.InteractSpotId,
	is_seated_here: bool = false
) -> String:
	if is_seated_here:
		return "起身走动 (长按Q/E转视角)"
	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			return "冲泡拿铁"
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
			return "入座画画摸鱼"
		CozyStudioState.InteractSpotId.LOUNGE_SOFA:
			return "窝进沙发休息"
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			return "撸撸橘猫"
	return ""


## 获取交互点是否为可入座槽位。
func is_seat_spot(spot: CozyStudioState.InteractSpotId) -> bool:
	return (
		spot == CozyStudioState.InteractSpotId.WORKSTATION_CHAIR
		or spot == CozyStudioState.InteractSpotId.LOUNGE_SOFA
	)


## 获取 3D 座椅/沙发坐垫吸附坐标（配合 4x9 坐姿帧表，使臀部正好贴合 3D 坐垫表面且小腿自然垂落）。
func get_spot_seat_world_pos(spot: CozyStudioState.InteractSpotId) -> Vector3:
	match spot:
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
			return Vector3(-2.64, 0.11, -2.34)
		CozyStudioState.InteractSpotId.LOUNGE_SOFA:
			return Vector3(2.74, 0.06, 1.05)
	return Vector3.ZERO


## 获取角色落座或触发点位时的标准 3D 世界水平朝向。
func get_spot_interact_facing(spot: CozyStudioState.InteractSpotId) -> Vector3:
	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			return Vector3(0.18, 0.0, -0.98).normalized()
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
			# 精确对齐转椅靠背法线 -> 朝向桌上数位屏与右显示器
			return Vector3(0.588, 0.0, -0.809).normalized()
		CozyStudioState.InteractSpotId.LOUNGE_SOFA:
			# 倚靠奶油绿簇绒靠枕 -> 朝向中央编织圆地毯与法式暖阳高窗
			return Vector3(-0.96, 0.0, 0.28).normalized()
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			return Vector3(-0.92, 0.0, 0.38).normalized()
	return Vector3(0.0, 0.0, 1.0)


## 获取从座椅/沙发抛物线跳回地板的安全落点坐标。
func get_spot_dismount_pos(
	spot: CozyStudioState.InteractSpotId,
	fallback_pos: Vector3
) -> Vector3:
	var candidate: Vector3 = fallback_pos
	if _overlaps_furniture(Vector2(candidate.x, candidate.z)):
		match spot:
			CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
				candidate = Vector3(-2.28, 0.0, -1.36)
			CozyStudioState.InteractSpotId.LOUNGE_SOFA:
				candidate = Vector3(1.26, 0.0, 0.52)
	return Vector3(
		clampf(candidate.x, WALK_MIN.x, WALK_MAX.x),
		0.0,
		clampf(candidate.z, WALK_MIN.y, WALK_MAX.y)
	)


## 获取特效气泡（爱心/咖啡香）冒出的 3D 锚点坐标。
func get_spot_bubble_origin(spot: CozyStudioState.InteractSpotId) -> Vector3:
	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			return Vector3(3.52, 1.78, -2.56)
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			return Vector3(-3.14, 0.90, 1.00)
	return Vector3.ZERO


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
