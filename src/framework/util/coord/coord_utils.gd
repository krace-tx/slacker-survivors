class_name CoordUtils
extends RefCounted

## 坐标与空间数学计算工具类。
##
## 提供高性能的距离判定、网格坐标转换以及方向角度转换。
## 纯无状态工具函数，不依赖任何场景树节点或外部单例。

#region Constants & Enums
# 坐标系计算中极小误差容忍值（按需使用）
const EPSILON: float = 0.00001
#endregion

#region Public API
## 高性能距离检查：判断两个坐标是否在指定半径内。[br]
## 内部使用距离平方进行比较，避免了原生 [method Vector2.distance_to] 极其昂贵的开平方根运算。[br]
## 适合在 _process 帧循环中给大量敌人做范围判定。
static func is_within_radius(pos_a: Vector2, pos_b: Vector2, radius: float) -> bool:
	# 拦截非法半径
	if radius <= 0.0:
		return false
	var dist_sq := pos_a.distance_squared_to(pos_b)  # 只算 dx*dx + dy*dy，不开根号
	return dist_sq <= (radius * radius)              # 半径也预先平方	


## 将世界坐标严格吸附到指定的网格大小（常用于建造系统或战棋游戏）。[br]
## [param world_pos] 当前实际坐标；[param grid_size] 网格的宽高尺寸。[br]
## 如果 [param grid_size] 包含 0，将安全地返回原坐标以防止除零崩溃。
static func snap_to_grid(world_pos: Vector2, grid_size: Vector2) -> Vector2:
	# 防御除零错误
	if grid_size.x == 0 or grid_size.y == 0:
		return world_pos
	return (world_pos / grid_size).floor() * grid_size


## 将世界坐标转换为整型的网格索引（Tile Index）。[br]
## 比如在一个 64x64 的网格系统中，坐标 (100, 100) 会返回网格索引 (1, 1)。[br]
## 如果 [param grid_size] 包含 0，安全返回 (0, 0)。
static func world_to_grid_index(world_pos: Vector2, grid_size: Vector2) -> Vector2i:
	# 防御除零错误
	if grid_size.x == 0 or grid_size.y == 0:
		return Vector2i.ZERO
	return Vector2i((world_pos / grid_size).floor())


## 将二维方向向量转换为角度（度数）。[br]
## Godot 底层全部使用弧度（Radian），此方法标准化了转为人类可读角度（Degree）的流程。[br]
## 0 度为正右（X轴正向），顺时针增加。
static func dir_to_degrees(direction: Vector2) -> float:
	# 消除零向量调用 angle() 带来的不可预知结果
	if direction.is_zero_approx():
		return 0.0
	return rad_to_deg(direction.angle())


## 根据角度（度数）生成标准化的方向向量。
static func degrees_to_dir(degrees: float) -> Vector2:
	var radians := deg_to_rad(degrees)
	return Vector2(cos(radians), sin(radians)).normalized()
	
## 安全获取 Control（UI节点）在实际缩放、轴心点（pivot）、旋转及所有父级变换影响下，
## 某个归一化偏移点的真实全局坐标。默认返回视觉中心点（Center）。[br]
## [param node] 必须是 Control 节点；[param normalized_offset] 偏移系数，
## Vector2(0.5, 0.5) 为中心，Vector2(0, 0) 为左上角。[br]
## 返回 [Result]：成功时 [member Result.value] 为真实的全局 [Vector2] 坐标；失败时返回错误。
static func get_real_global_vertex(node: Control, normalized_offset: Vector2 = Vector2(0.5, 0.5)) -> Result:
	# 卫语句：拦截空指针 / 已销毁节点
	if not is_instance_valid(node):
		return Result.err("Vertex failed: node is invalid.")

	# size 是「未缩放」的局部尺寸，归一化偏移乘以它得到局部像素坐标。
	var local_point := node.size * normalized_offset
	return Result.ok(node.get_global_transform() * local_point)


## 获取 Control（UI节点）缩放、pivot、旋转及所有父级变换之后，真正渲染出来的矩形的
## 4 个全局角点。返回顺序为顺时针：左上、右上、右下、左下。[br]
## [param node] 必须是 Control 节点。[br]
## 返回 [Result]：成功时 [member Result.value] 为含 4 个全局 [Vector2] 的
## [PackedVector2Array]；失败（节点无效）时返回错误。[br]
## 注意：Control **没有** [code]to_global()[/code]（那是 Node2D/Node3D 的方法），
## 必须用 [method CanvasItem.get_global_transform] 乘局部点来做变换。
static func get_real_global_corners(node: Control) -> Result:
	# 卫语句：拦截空指针 / 已销毁节点
	if not is_instance_valid(node):
		return Result.err("Corners failed: node is invalid.")

	# 局部空间里四角固定为：(0,0) 左上、(w,0) 右上、(w,h) 右下、(0,h) 左下。
	# size 不随 scale 变化，缩放/pivot/旋转/父级变换全部由下面的矩阵一次性吃进去。
	var s := node.size
	var xform := node.get_global_transform()
	var corners := PackedVector2Array()
	corners.append(xform * Vector2(0.0, 0.0))    # 左上
	corners.append(xform * Vector2(s.x, 0.0))    # 右上
	corners.append(xform * Vector2(s.x, s.y))    # 右下
	corners.append(xform * Vector2(0.0, s.y))    # 左下
	return Result.ok(corners)
#endregion
