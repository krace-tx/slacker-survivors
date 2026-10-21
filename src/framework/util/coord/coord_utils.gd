class_name CoordUtils
extends RefCounted

## 工业级坐标变换、空间几何判定与跨画布投影工具类。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]零超越函数（Zero-Transcendental）高频几何判定[/b]：距离、圆环与扇形锥（Cone）判定全程在平方域或向量点积域完成，
##    杜绝在帧循环索敌中高频调用昂贵的 [code]sqrt[/code] / [code]acos[/code]；角度转向量直达 C++ 原生 [method Vector2.from_angle]；[br]
## 2. [b]完备双向网格拓扑（Bi-Directional Grid Topology）[/b]：统一支持原点偏移（Origin）与归一化锚点（Anchor），
##    打通 [code]World <-> Grid[/code] 双向映射、中心/角点吸附及曼哈顿/切比雪夫网格距离；[br]
## 3. [b]多空间矩阵链穿透（Multi-Space Transform Chain）[/b]：严格区分画布内变换（[method CanvasItem.get_global_transform]）
##    与视口屏幕变换（[method CanvasItem.get_global_transform_with_canvas]），提供 [code]World2D / World3D <-> Screen <-> UI Control[/code]
##    跨层投影桥接（含 3D 相机背面剔除防镜像闪烁保护）。


#region Constants & Error Codes

const EPSILON: float = 0.00001 ## 浮点几何除零与退化判定阈值。

const ERR_INVALID_NODE: String = "Coord.InvalidNode"
const ERR_INVALID_CAMERA: String = "Coord.InvalidCamera"
const ERR_BEHIND_CAMERA: String = "Coord.BehindCamera"

#endregion


#region Core Operator 1: Spatial Distance & Sector Predicates (Zero-Sqrt)

## 高性能 2D 距离检查：判断两个坐标是否在指定半径内（闭区间）。[br]
## 内部使用距离平方进行比较，避免原生 [method Vector2.distance_to] 的开平方根运算。
static func is_within_radius(pos_a: Vector2, pos_b: Vector2, radius: float) -> bool:
	if radius < 0.0:
		return false
	return pos_a.distance_squared_to(pos_b) <= (radius * radius)


## 高性能 3D 球体距离检查：判断两个 3D 坐标是否在指定半径内（闭区间）。
static func is_within_radius_3d(pos_a: Vector3, pos_b: Vector3, radius: float) -> bool:
	if radius < 0.0:
		return false
	return pos_a.distance_squared_to(pos_b) <= (radius * radius)


## 高性能 2D 圆环区域检查：判断目标点是否落在 [code][inner_radius, outer_radius][/code] 环形区间内。
static func is_within_ring(
	pos: Vector2,
	center: Vector2,
	inner_radius: float,
	outer_radius: float
) -> bool:
	if outer_radius < 0.0 or outer_radius < inner_radius:
		return false
	var dist_sq := pos.distance_squared_to(center)
	var min_r := maxf(0.0, inner_radius)
	return dist_sq >= (min_r * min_r) and dist_sq <= (outer_radius * outer_radius)


## 高性能 2D 扇形锥（Sector / Cone）命中判定（专为近战挥砍、散射索敌、视野锥设计）。[br]
## 先做 O(1) 距离平方剔除，再通过点积余弦定理判定夹角，避免对每个目标调用 [code]acos[/code] 或 [code]angle_to[/code]。[br]
## [param origin] 扇形顶点（释放者坐标）。[br]
## [param forward_dir] 扇形中轴朝向向量（无需预先归一化）。[br]
## [param target_pos] 待检测的目标坐标。[br]
## [param radius] 扇形半径。[br]
## [param half_angle_deg] 扇形半角（度数，范围 [code]0 ~ 180[/code]；例如 90 度扇形传 [code]45.0[/code]）。
static func is_within_cone(
	origin: Vector2,
	forward_dir: Vector2,
	target_pos: Vector2,
	radius: float,
	half_angle_deg: float
) -> bool:
	if radius < 0.0 or half_angle_deg <= 0.0:
		return false

	var to_target := target_pos - origin
	var dist_sq := to_target.length_squared()
	if dist_sq > (radius * radius):
		return false
	if dist_sq <= EPSILON:
		return true # 目标与原点重合视为命中
	if half_angle_deg >= 180.0:
		return true

	var fwd_len_sq := forward_dir.length_squared()
	if fwd_len_sq <= EPSILON:
		return false

	var cos_half := cos(deg_to_rad(half_angle_deg))
	var dot := forward_dir.dot(to_target)

	# 钝角半角（> 90 度，cos_half < 0）与锐角半角分治，完全消除对 to_target 的 sqrt 开方
	if cos_half >= 0.0:
		if dot < 0.0:
			return false
		return (dot * dot) >= (fwd_len_sq * dist_sq * cos_half * cos_half)
	else:
		if dot >= 0.0:
			return true
		return (dot * dot) <= (fwd_len_sq * dist_sq * cos_half * cos_half)

#endregion


#region Core Operator 2: Bi-Directional Grid Topology

## 将世界坐标转换为整型网格坐标（Tile Coordinate）。[br]
## [param world_pos] 世界坐标。[br]
## [param grid_size] 单个网格的宽高尺寸（必须大于 [constant EPSILON]）。[br]
## [param origin] 网格系统的世界原点偏移（默认 [constant Vector2.ZERO]）。
static func world_to_grid(
	world_pos: Vector2,
	grid_size: Vector2,
	origin: Vector2 = Vector2.ZERO
) -> Vector2i:
	if absf(grid_size.x) <= EPSILON or absf(grid_size.y) <= EPSILON:
		return Vector2i.ZERO
	return Vector2i(((world_pos - origin) / grid_size).floor())


## 将整型网格坐标还原为世界坐标。[br]
## [param grid_coord] 网格索引 [code](col, row)[/code]。[br]
## [param grid_size] 单个网格的宽高尺寸。[br]
## [param anchor] 格内归一化锚点：默认 [code]Vector2(0.5, 0.5)[/code] 返回格子中心点；传 [code]Vector2.ZERO[/code] 返回左上角。[br]
## [param origin] 网格系统的世界原点偏移。
static func grid_to_world(
	grid_coord: Vector2i,
	grid_size: Vector2,
	anchor: Vector2 = Vector2(0.5, 0.5),
	origin: Vector2 = Vector2.ZERO
) -> Vector2:
	return origin + (Vector2(grid_coord) + anchor) * grid_size


## 将世界坐标严格吸附到指定的网格（默认吸附至格子左上角，传 [code]anchor = Vector2(0.5, 0.5)[/code] 吸附至格子中心）。[br]
## 如果 [param grid_size] 包含接近 0 的分量，安全返回原坐标以防止除零崩溃。
static func snap_to_grid(
	world_pos: Vector2,
	grid_size: Vector2,
	anchor: Vector2 = Vector2.ZERO,
	origin: Vector2 = Vector2.ZERO
) -> Vector2:
	if absf(grid_size.x) <= EPSILON or absf(grid_size.y) <= EPSILON:
		return world_pos
	var cell := ((world_pos - origin) / grid_size).floor()
	return origin + (cell + anchor) * grid_size


## 计算两个网格坐标之间的曼哈顿距离（Manhattan Distance，适用于四方向正交移动步数）。
static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 计算两个网格坐标之间的切比雪夫距离（Chebyshev Distance，适用于八方向对角移动步数）。
static func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

#endregion


#region Core Operator 3: Angular & Orientation Math

## 将二维方向向量转换为角度（度数，0 度为 X 轴正右，顺时针增加）。
static func dir_to_degrees(direction: Vector2) -> float:
	if direction.length_squared() <= EPSILON:
		return 0.0
	return rad_to_deg(direction.angle())


## 根据角度（度数）生成单位方向向量（底层直调 [method Vector2.from_angle]，无冗余开方）。
static func degrees_to_dir(degrees: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(degrees))


## 计算从 [param from_deg] 到 [param to_deg] 的最短有符号角度差（范围 [code][-180.0, 180.0][/code]）。
static func angle_diff_degrees(from_deg: float, to_deg: float) -> float:
	return rad_to_deg(angle_difference(deg_to_rad(from_deg), deg_to_rad(to_deg)))


## 以最大步长 [param max_delta_deg] 从当前角度平滑转向目标角度（无过冲，自动走最短劣弧并归一化至 [code][0.0, 360.0)[/code]）。
static func rotate_toward_degrees(current_deg: float, target_deg: float, max_delta_deg: float) -> float:
	var rotated := rad_to_deg(rotate_toward(deg_to_rad(current_deg), deg_to_rad(target_deg), deg_to_rad(max_delta_deg)))
	return fposmod(rotated, 360.0)

#endregion


#region Core Operator 4: Control Geometry & Global AABB

## 安全获取 [Control] 节点在实际缩放、轴心点（pivot）、旋转及所有父级变换影响下，
## 某个归一化偏移点的真实全局坐标。默认返回视觉中心点 [code]Vector2(0.5, 0.5)[/code]。[br]
## [param node] 目标 [Control] 节点。[br]
## [param normalized_offset] 归一化偏移系数，[code](0.5, 0.5)[/code] 为中心，[code](0, 0)[/code] 为左上角。[br]
## [param include_canvas] 若为 [code]true[/code]，使用 [method CanvasItem.get_global_transform_with_canvas] 返回视口屏幕坐标。[br]
## 返回 [Result]：成功时 [member Result.value] 为 [Vector2]；失败时返回 [constant ERR_INVALID_NODE]。
static func get_global_vertex(
	node: Control,
	normalized_offset: Vector2 = Vector2(0.5, 0.5),
	include_canvas: bool = false
) -> Result:
	if not is_instance_valid(node):
		return _err_invalid_node("get_global_vertex")

	var xform := node.get_global_transform_with_canvas() if include_canvas else node.get_global_transform()
	return Result.ok(xform * (node.size * normalized_offset))


## 获取 [Control] 节点在缩放、pivot、旋转及所有父级变换之后，真正渲染矩形的 4 个全局角点。[br]
## 返回顺序为顺时针：左上、右上、右下、左下。[br]
## 成功时 [member Result.value] 为含 4 个 [Vector2] 的 [PackedVector2Array]。
static func get_global_corners(node: Control, include_canvas: bool = false) -> Result:
	if not is_instance_valid(node):
		return _err_invalid_node("get_global_corners")

	var s := node.size
	var xform := node.get_global_transform_with_canvas() if include_canvas else node.get_global_transform()
	var corners := PackedVector2Array()
	corners.resize(4)
	corners[0] = xform * Vector2(0.0, 0.0) # 左上
	corners[1] = xform * Vector2(s.x, 0.0) # 右上
	corners[2] = xform * Vector2(s.x, s.y) # 右下
	corners[3] = xform * Vector2(0.0, s.y) # 左下
	return Result.ok(corners)


## 计算 [Control] 节点经过缩放、旋转、Pivot 偏移及父级变换后的真实全局轴对齐包围盒（AABB [Rect2]）。[br]
## 成功时 [member Result.value] 为 [Rect2]。
static func get_global_rect(node: Control, include_canvas: bool = false) -> Result:
	var corners_res := get_global_corners(node, include_canvas)
	if corners_res.is_err():
		return corners_res

	var corners: PackedVector2Array = corners_res.value
	var min_pt := corners[0]
	var max_pt := corners[0]
	for i in range(1, 4):
		var pt := corners[i]
		min_pt.x = minf(min_pt.x, pt.x)
		min_pt.y = minf(min_pt.y, pt.y)
		max_pt.x = maxf(max_pt.x, pt.x)
		max_pt.y = maxf(max_pt.y, pt.y)

	return Result.ok(Rect2(min_pt, max_pt - min_pt))


## 在外层容器矩形 [param outer_rect] 内，计算保持目标宽高比 [param target_aspect]（宽 / 高）的最大居中内接矩形（Letterbox / Pillarbox 纯几何算子）。[br]
## 用于防止固定比例的 UI 面板或战术棋盘在超宽屏或方屏上发生拉伸畸变。
static func fit_rect_aspect(outer_rect: Rect2, target_aspect: float) -> Rect2:
	if outer_rect.size.x <= EPSILON or outer_rect.size.y <= EPSILON or target_aspect <= EPSILON:
		return outer_rect

	var current_aspect := outer_rect.size.x / outer_rect.size.y
	if is_equal_approx(current_aspect, target_aspect):
		return outer_rect

	if current_aspect > target_aspect:
		var fitted_w := outer_rect.size.y * target_aspect
		var offset_x := (outer_rect.size.x - fitted_w) * 0.5
		return Rect2(Vector2(outer_rect.position.x + offset_x, outer_rect.position.y), Vector2(fitted_w, outer_rect.size.y))
	else:
		var fitted_h := outer_rect.size.x / target_aspect
		var offset_y := (outer_rect.size.y - fitted_h) * 0.5
		return Rect2(Vector2(outer_rect.position.x, outer_rect.position.y + offset_y), Vector2(outer_rect.size.x, fitted_h))

#endregion


#region Core Operator 5: Cross-Space Projection Bridge (World2D / World3D <-> Screen <-> UI)

## 将任意 2D 节点（[Node2D] 或 [Control]）的局部坐标转换为视口屏幕像素坐标（穿透 [Camera2D] 与 [CanvasLayer]）。
static func canvas_to_screen(item: CanvasItem, local_pos: Vector2 = Vector2.ZERO) -> Result:
	if not is_instance_valid(item):
		return _err_invalid_node("canvas_to_screen")
	return Result.ok(item.get_global_transform_with_canvas() * local_pos)


## 将视口屏幕像素坐标逆变换为目标 [CanvasItem] 的局部坐标（支持跨 [CanvasLayer] 对齐）。
static func screen_to_local(target_item: CanvasItem, screen_pos: Vector2) -> Result:
	if not is_instance_valid(target_item):
		return _err_invalid_node("screen_to_local")
	return Result.ok(target_item.get_global_transform_with_canvas().affine_inverse() * screen_pos)


## 将源 [CanvasItem]（如世界层中的怪物 [Node2D]）的局部位置，直接映射为另一 [CanvasItem]（如 HUD 层中的飘字容器 [Control]）所在画布的全局或局部坐标。[br]
## 典型用途：怪物头顶血条跟随、世界掉落金币飞向顶部 UI 栏、新手引导高亮框追踪场景物体。[br]
## [param source_item] 源节点（如世界中的敌人）。[br]
## [param target_space_item] 目标空间参照节点（如 UI 层容器）。[br]
## [param source_local_offset] 源节点局部偏移。[br]
## [param as_target_local] 为 [code]true[/code] 时返回相对于 [param target_space_item] 的局部坐标（可直接赋给子节点 [code]position[/code]）；
## 为 [code]false[/code] 时返回目标所属 [CanvasLayer] 的画布全局坐标（可直接赋给 [code]global_position[/code]）。
static func map_canvas_position(
	source_item: CanvasItem,
	target_space_item: CanvasItem,
	source_local_offset: Vector2 = Vector2.ZERO,
	as_target_local: bool = false
) -> Result:
	if not is_instance_valid(source_item) or not is_instance_valid(target_space_item):
		return _err_invalid_node("map_canvas_position")

	var screen_pos := source_item.get_global_transform_with_canvas() * source_local_offset
	if as_target_local:
		return Result.ok(target_space_item.get_global_transform_with_canvas().affine_inverse() * screen_pos)
	return Result.ok(target_space_item.get_canvas_transform().affine_inverse() * screen_pos)


## 将 3D 世界坐标通过 [Camera3D] 安全投影为 2D 视口屏幕坐标。[br]
## 若目标点位于相机近裁剪面后方（背对相机），返回 [constant ERR_BEHIND_CAMERA] 错误，杜绝 UI 标记在屏幕背面发生反向镜像闪烁。
static func world3d_to_screen(camera: Camera3D, world_pos_3d: Vector3) -> Result:
	if not is_instance_valid(camera):
		return Result.err_ex(
			ERR_INVALID_CAMERA,
			"CoordUtils.world3d_to_screen failed: Camera3D is invalid.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	if camera.is_position_behind(world_pos_3d):
		return Result.err_ex(
			ERR_BEHIND_CAMERA,
			"CoordUtils.world3d_to_screen rejected: target 3D position is behind the camera.",
			{"world_pos": world_pos_3d},
			false,
			null,
			FrameworkError.CATEGORY_STATE
		)

	return Result.ok(camera.unproject_position(world_pos_3d))

#endregion


#region Private Helpers

static func _err_invalid_node(method_name: String) -> Result:
	return Result.err_ex(
		ERR_INVALID_NODE,
		"CoordUtils.%s failed: target node is null or freed." % method_name,
		{},
		false,
		null,
		FrameworkError.CATEGORY_PARAM
	)

#endregion
