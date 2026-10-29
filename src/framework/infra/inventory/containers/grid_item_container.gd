class_name GridItemContainer
extends BaseItemContainer

## 二维空间矩阵网格容器（2D Spatial Matrix & Footprint Grid Container）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/containers/[/code][br]
## [b]适用游戏品类：[/b]暗黑破坏神 / 塔科夫式异形尺寸物资箱、生化危机手提箱、《背包乱斗》式空间邻接构筑肉鸽背包。[br]
## [b]核心数据结构与算法设计：[/b][br]
## 1. [b]格点索引与实例本体物理分离[/b]：
##    一维紧凑连续内存 [code]_cells: PackedInt32Array[/code]（大小 [code]width * height[/code]）仅存储占据该格的物品 [code]uid[/code]（[code]0[/code] 为空闲），
##    物品实例与左上角包围盒分别单点存于 [member _items] 与 [member _rects]——从根源杜绝 `2×3` 大尺寸物品跨多格的数据同步灾难；[br]
## 2. [b]克隆缓冲连续排布预判[/b]：
##    [method get_addable_count] 在轻量复制的 `PackedInt32Array` 上真实模拟多件大体积物品的连续落位与自动 90 度旋转，
##    彻底消除「两面 `2×3` 大盾同时相中同一块空区导致误判能装下」的经典排布漏洞；[br]
## 3. [b]O(周长) 邻接拓扑扫描[/b]：
##    [method get_adjacent_uids] 直接沿物品包围盒四条外缘采集相邻实例，无需全图扫描即可高效驱动邻接光环与合成判定。[br]
##
## [codeblocks]
## [gdscript]
## var grid := GridItemContainer.new(&"tactical_rig", 6, 4, resolver)
## grid.place_at(ItemStack.create(&"sword_iron", 1), Vector2i(0, 0), false)
## var sword_uid: int = grid.get_cell_uid(0, 0)
## var neighbors: Array[int] = grid.get_adjacent_uids(sword_uid, false) # 正交四邻域相连物品 UID
## [/gdscript]
## [/codeblocks]


#region Properties & Internal Spatial Buffers

## 网格横向列数（恒满足 [code]_width >= 1[/code]）。
var _width: int = 8

## 网格纵向行数（恒满足 [code]_height >= 1[/code]）。
var _height: int = 6

## 行优先一维紧凑占用格点表：下标 [code]y * _width + x[/code] 对应占据该格的实例 [code]uid[/code]，[code]0[/code] 代表空闲。
var _cells: PackedInt32Array = PackedInt32Array()

## 已放置实例主表（int uid -> ItemStack）。
var _items: Dictionary = {}

## 已放置实例空间包围盒缓存表（int uid -> Rect2i(anchor_pos, effective_size)）。
var _rects: Dictionary = {}

## 实例确定性入库顺序表（保证遍历、按 ID 消耗及存档快照顺序稳定）。
var _order: Array[int] = []

## 网格横向总列数（只读）。
var width: int:
	get:
		return _width

## 网格纵向总行数（只读）。
var height: int:
	get:
		return _height

#endregion


#region Lifecycle

## 构造二维空间网格容器。[br]
## [param p_container_id] 容器业务标识（默认 [code]&"bag_grid"[/code]）。[br]
## [param p_width] 网格横向列数（自动钳制为 [code]>= 1[/code]）。[br]
## [param p_height] 网格纵向行数（自动钳制为 [code]>= 1[/code]）。[br]
## [param p_spec_resolver] 物品静态规格反查回调（提供 [member ItemSpec.grid_size] 与 [member ItemSpec.rotatable]）。[br]
## [param p_rule] 可选容器准入与移除规则。[br]
## [param p_strict_spec] 是否开启严格规格缺失校验。
func _init(
	p_container_id: StringName = &"bag_grid",
	p_width: int = 8,
	p_height: int = 6,
	p_spec_resolver: Callable = Callable(),
	p_rule: ContainerRule = null,
	p_strict_spec: bool = false
) -> void:
	super._init(p_container_id, p_spec_resolver, p_rule, p_strict_spec)
	_width = maxi(1, p_width)
	_height = maxi(1, p_height)
	_cells.resize(_width * _height)
	_cells.fill(0)

#endregion


#region Spatial Grid Queries

## 检查单个网格坐标 [code](x, y)[/code] 是否位于合法边界 [code][0, width) × [0, height)[/code] 内。
func is_valid_cell(x: int, y: int) -> bool:
	return x >= 0 and x < _width and y >= 0 and y < _height


## 检查矩形区域 [param rect] 宽高是否为正且完整包含于网格边界之内。
func is_rect_in_bounds(rect: Rect2i) -> bool:
	return (
		rect.size.x > 0
		and rect.size.y > 0
		and rect.position.x >= 0
		and rect.position.y >= 0
		and rect.position.x + rect.size.x <= _width
		and rect.position.y + rect.size.y <= _height
	)


## O(1) 查询格点 [code](x, y)[/code] 上的占用实例 [code]uid[/code]（空闲或坐标越界时统一返回 [code]0[/code]）。
func get_cell_uid(x: int, y: int) -> int:
	if not is_valid_cell(x, y):
		return 0
	return _cells[y * _width + x]


## 查询格点 [code](x, y)[/code] 处放置物品堆的深拷贝副本（空闲或越界返回 [code]null[/code]）。
func get_item_at(x: int, y: int) -> ItemStack:
	var uid: int = get_cell_uid(x, y)
	return get_item_by_uid(uid) if uid > 0 else null


## O(1) 查询指定实例 [param uid] 当前占据的网格矩形区域（含左上角锚点与旋转后实际宽高；未命中返回空 [Rect2i]）。
func get_item_rect(uid: int) -> Rect2i:
	if not _rects.has(uid):
		return Rect2i()
	var rect_val: Variant = _rects.get(uid, Rect2i())
	return rect_val as Rect2i if rect_val is Rect2i else Rect2i()


## 统计当前网格中未被任何物品覆盖的空闲单格总数。
func get_free_cell_count() -> int:
	var free_cnt: int = 0
	for i: int in _cells.size():
		if _cells[i] == 0:
			free_cnt += 1
	return free_cnt


## 检查目标矩形区域 [param rect] 在边界内且完全无其它物品阻挡。[br]
## [param ignore_uid] 移动或原地旋转已有物品时传入自身 UID，防止将自身旧占地误判为碰撞阻挡。
func is_region_free(rect: Rect2i, ignore_uid: int = 0) -> bool:
	if not is_rect_in_bounds(rect):
		return false
	return _is_region_free_on_buffer(_cells, rect, ignore_uid)


## 扫描并返回目标矩形区域 [param rect] 内覆盖到的全部不重复阻挡物 [code]uid[/code] 列表（自动排除 [param ignore_uid]）。[br]
## 典型用途：拖拽悬停高亮检测，或判定落点是否恰好仅覆盖 1 件可互换/可合并的目标物品。
func get_occupying_uids(rect: Rect2i, ignore_uid: int = 0) -> Array[int]:
	var found: Array[int] = []
	var clamped_x0: int = maxi(0, rect.position.x)
	var clamped_y0: int = maxi(0, rect.position.y)
	var clamped_x1: int = mini(_width, rect.position.x + rect.size.x)
	var clamped_y1: int = mini(_height, rect.position.y + rect.size.y)
	for y: int in range(clamped_y0, clamped_y1):
		var row_offset: int = y * _width
		for x: int in range(clamped_x0, clamped_x1):
			var occ: int = _cells[row_offset + x]
			if occ > 0 and occ != ignore_uid and not found.has(occ):
				found.append(occ)
	return found


## 按从上到下、从左到右顺序为 [param stack] 搜索首个可容纳的左上角坐标与旋转姿态。[br]
## [param allow_auto_rotate] 当前朝向无空位且物品允许旋转时，是否自动尝试 90 度旋转后再扫描一轮。[br]
## [param ignore_uid] 搜索时忽略的自身实例 UID。[br]
## 返回字典格式：[code]{ "found": bool, "pos": Vector2i, "rotated": bool }[/code]。
func find_first_fit(stack: ItemStack, allow_auto_rotate: bool = true, ignore_uid: int = 0) -> Dictionary:
	var spec: ItemSpec = resolve_spec(stack.item_id) if stack != null else null
	if spec == null:
		return {"found": false, "pos": Vector2i(-1, -1), "rotated": false}
	return _find_fit_on_buffer(_cells, spec, stack.rotated, allow_auto_rotate, ignore_uid)


## O(周长) 沿 [param uid] 占地外框扫描所有紧邻的其它物品 [code]uid[/code] 去重列表。[br]
## [param uid] 中心物品唯一实例 ID。[br]
## [param include_diagonals] 为 [code]false[/code]（默认）仅扫描上下左右正交邻边；为 [code]true[/code] 时额外纳入四个对角顶点邻居。
func get_adjacent_uids(uid: int, include_diagonals: bool = false) -> Array[int]:
	var neighbors: Array[int] = []
	if not _rects.has(uid):
		return neighbors
	var rect: Rect2i = get_item_rect(uid)
	var x0: int = rect.position.x
	var y0: int = rect.position.y
	var x1: int = x0 + rect.size.x - 1
	var y1: int = y0 + rect.size.y - 1

	# 扫描上下两条水平外框边
	for x: int in range(x0, x1 + 1):
		_collect_neighbor_cell(x, y0 - 1, uid, neighbors)
		_collect_neighbor_cell(x, y1 + 1, uid, neighbors)
	# 扫描左右两条垂直外框边
	for y: int in range(y0, y1 + 1):
		_collect_neighbor_cell(x0 - 1, y, uid, neighbors)
		_collect_neighbor_cell(x1 + 1, y, uid, neighbors)

	# 按需追加四角对角邻格
	if include_diagonals:
		_collect_neighbor_cell(x0 - 1, y0 - 1, uid, neighbors)
		_collect_neighbor_cell(x1 + 1, y0 - 1, uid, neighbors)
		_collect_neighbor_cell(x0 - 1, y1 + 1, uid, neighbors)
		_collect_neighbor_cell(x1 + 1, y1 + 1, uid, neighbors)

	return neighbors

#endregion


#region BaseItemContainer Queries

## 汇总网格内所有同名 [param item_id] 实例的数量总和。
func get_total_count(item_id: StringName) -> int:
	if item_id.is_empty():
		return 0
	var total: int = 0
	for uid: int in _order:
		var st: ItemStack = _items.get(uid, null) as ItemStack
		if st != null and st.item_id == item_id:
			total += st.count
	return total


## O(1) 按唯一实例 [param uid] 返回物品堆深拷贝副本；未命中返回 [code]null[/code]。
func get_item_by_uid(uid: int) -> ItemStack:
	if uid <= 0 or not _items.has(uid):
		return null
	var st: ItemStack = _items.get(uid, null) as ItemStack
	return st.clone_stack() if st != null else null


## 按入库顺序导出网格中所有已放置物品堆的深拷贝数组。
func get_all_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for uid: int in _order:
		var st: ItemStack = _items.get(uid, null) as ItemStack
		if st != null:
			result.append(st.clone_stack())
	return result


## 判断网格中是否未放置任何物品。
func is_empty() -> bool:
	return _order.is_empty()


## 通过「同类堆余量累加 + 克隆一维格点缓冲连续矩形装填模拟」精确计算可放入的最大数量。
func get_addable_count(stack: ItemStack) -> int:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return 0
	var spec: ItemSpec = val_res.value as ItemSpec
	var merge_pred: Callable = _get_merge_predicate()
	var addable: int = 0

	if spec.is_stackable():
		for uid: int in _order:
			var cur: ItemStack = _items.get(uid, null) as ItemStack
			if cur != null and cur.can_merge_with(stack, spec.max_stack, merge_pred):
				addable += maxi(0, spec.max_stack - cur.count)
		if addable >= stack.count:
			return stack.count

	# 复制连续整数缓冲模拟多件连续占地，确保多件大尺寸物品的空间校验 100% 精确
	var sim_cells: PackedInt32Array = _cells.duplicate()
	var sim_temp_uid: int = -1
	while addable < stack.count:
		var fit: Dictionary = _find_fit_on_buffer(sim_cells, spec, stack.rotated, true, 0)
		if not bool(fit.get("found", false)):
			break
		var fit_pos: Vector2i = fit.get("pos", Vector2i.ZERO) as Vector2i
		var fit_rot: bool = bool(fit.get("rotated", false))
		var eff_size: Vector2i = spec.get_effective_size(fit_rot)
		_paint_buffer(sim_cells, Rect2i(fit_pos, eff_size), sim_temp_uid)
		sim_temp_uid -= 1
		addable += spec.max_stack

	return mini(stack.count, addable)


## 预演校验整堆 [param stack] 是否能在当前网格中完整合并与排布放下。
func can_add(stack: ItemStack) -> Result:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return val_res
	if get_addable_count(stack) < stack.count:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"GridItemContainer '%s' cannot pack %d of '%s'." % [
				String(container_id), stack.count, String(stack.item_id)
			]
		)
	return Result.ok(true)

#endregion


#region BaseItemContainer Mutations

## 自动寻位放入整堆 [param stack]（先合入网格内已有同类未满堆，剩余部分自动搜索空位并按需旋转 90 度装填）。
func add(stack: ItemStack) -> Result:
	var can_res: Result = can_add(stack)
	if can_res.is_err():
		return can_res

	var spec: ItemSpec = resolve_spec(stack.item_id)
	var merge_pred: Callable = _get_merge_predicate()
	var remaining: int = stack.count
	var diff := InventoryDiff.new(container_id)

	# 阶段 1：优先填满已放置在网格上的同类可合并堆
	if spec.is_stackable():
		for uid: int in _order:
			if remaining <= 0:
				break
			var cur: ItemStack = _items.get(uid, null) as ItemStack
			if cur != null and cur.can_merge_with(stack, spec.max_stack, merge_pred):
				var room: int = spec.max_stack - cur.count
				if room > 0:
					var take: int = mini(room, remaining)
					cur.count += take
					remaining -= take
					diff.mark_uid(cur.uid)

	# 阶段 2：余量自动寻找空闲矩形区域（原朝向放不下时自动回退尝试 90 度旋转）
	var preserve_uid: bool = stack.uid > 0 and not _items.has(stack.uid)
	while remaining > 0:
		var fit: Dictionary = _find_fit_on_buffer(_cells, spec, stack.rotated, true, 0)
		if not bool(fit.get("found", false)):
			return Result.err_code(InventoryError.CAPACITY_FULL, "Grid packing unexpectedly exhausted.")
		var fit_pos: Vector2i = fit.get("pos", Vector2i.ZERO) as Vector2i
		var fit_rot: bool = bool(fit.get("rotated", false))
		var chunk: int = mini(remaining, spec.max_stack)

		var entry: ItemStack = stack.clone_stack()
		entry.count = chunk
		entry.rotated = fit_rot
		if preserve_uid:
			sync_uid_floor(entry.uid)
			preserve_uid = false
		else:
			entry.uid = allocate_uid()

		var rect := Rect2i(fit_pos, spec.get_effective_size(fit_rot))
		_commit_placement(entry, rect)
		diff.mark_uid(entry.uid)
		remaining -= chunk

	diff.record_added(stack.item_id, stack.count)
	notify_changed(diff)
	return Result.ok(diff)


## 按 [param item_id] 原子扣减 [param count] 个物品（优先消耗无扩展元数据的标准堆，扣空时同步擦除对应格点占用）。
func remove_by_id(item_id: StringName, count: int = 1) -> Result:
	if item_id.is_empty() or count <= 0:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid item_id or count.")
	var rm_res: Result = _validate_remove_allowed()
	if rm_res.is_err():
		return rm_res
	if not has_enough(item_id, count):
		return Result.err_code(
			InventoryError.INSUFFICIENT_ITEM,
			"Insufficient '%s': required %d, owned %d." % [String(item_id), count, get_total_count(item_id)]
		)

	var remaining: int = count
	var diff := InventoryDiff.new(container_id)

	for pass_idx: int in 2:
		var allow_meta: bool = pass_idx == 1
		var idx: int = 0
		while remaining > 0 and idx < _order.size():
			var uid: int = _order[idx]
			var st: ItemStack = _items.get(uid, null) as ItemStack
			if st == null or st.item_id != item_id or (not allow_meta and st.has_meta_payload()):
				idx += 1
				continue
			var take: int = mini(st.count, remaining)
			st.count -= take
			remaining -= take
			diff.mark_uid(uid)
			if st.count <= 0:
				_erase_placement(uid)
			else:
				idx += 1

	diff.record_removed(item_id, count)
	notify_changed(diff)
	return Result.ok(diff)


## 按唯一实例 [param uid] 扣减 [param count] 个物品（传 [code]-1[/code] 整件移出网格并释放占地）。
func remove_by_uid(uid: int, count: int = -1) -> Result:
	if uid <= 0 or count == 0 or count < -1:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid uid or count.")
	var rm_res: Result = _validate_remove_allowed()
	if rm_res.is_err():
		return rm_res
	if not _items.has(uid):
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Item uid %d not found in grid." % uid)

	var st: ItemStack = _items.get(uid, null) as ItemStack
	var actual: int = st.count if count == -1 else count
	if actual > st.count:
		return Result.err_code(
			InventoryError.INSUFFICIENT_ITEM,
			"Item uid %d has %d, cannot remove %d." % [uid, st.count, actual]
		)

	var diff := InventoryDiff.new(container_id)
	diff.record_removed(st.item_id, actual)
	diff.mark_uid(uid)

	st.count -= actual
	if st.count <= 0:
		_erase_placement(uid)

	notify_changed(diff)
	return Result.ok(diff)


## 清空整个网格的全部物品与格点索引，返回本次清空对应的 [InventoryDiff]。
func clear() -> InventoryDiff:
	var diff := InventoryDiff.new(container_id)
	for uid: int in _order:
		var st: ItemStack = _items.get(uid, null) as ItemStack
		if st != null:
			diff.record_removed(st.item_id, st.count)
			diff.mark_uid(uid)
	_cells.fill(0)
	_items.clear()
	_rects.clear()
	_order.clear()
	notify_changed(diff)
	return diff

#endregion


#region Grid-Specific Atomic Operations

## 将 [param stack] 定点放置到左上角网格坐标 [param pos] 及旋转朝向 [param is_rotated] 处。[br]
## - 若目标区域完全空闲：直接落位并写入格点表；[br]
## - 若目标区域仅覆盖唯一 1 件可合并同类且余量充足：直接合入目标堆；[br]
## - 越界返回 [constant InventoryError.OUT_OF_BOUNDS]，禁止旋转返回 [constant InventoryError.ROTATION_FORBIDDEN]，阻挡冲突返回 [constant InventoryError.COLLISION]。
func place_at(stack: ItemStack, pos: Vector2i, is_rotated: bool = false) -> Result:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return val_res

	var spec: ItemSpec = val_res.value as ItemSpec
	if is_rotated and not spec.rotatable:
		return Result.err_code(
			InventoryError.ROTATION_FORBIDDEN,
			"Item '%s' cannot be rotated." % String(stack.item_id)
		)
	if stack.count > spec.max_stack:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"Stack count (%d) exceeds max_stack (%d)." % [stack.count, spec.max_stack]
		)

	var rect := Rect2i(pos, spec.get_effective_size(is_rotated))
	if not is_rect_in_bounds(rect):
		return Result.err_code(InventoryError.OUT_OF_BOUNDS, "Placement rect %s out of grid bounds." % str(rect))

	var blockers: Array[int] = get_occupying_uids(rect)
	var diff := InventoryDiff.new(container_id)

	if blockers.is_empty():
		var entry: ItemStack = stack.clone_stack()
		entry.rotated = is_rotated
		if entry.uid > 0 and not _items.has(entry.uid):
			sync_uid_floor(entry.uid)
		else:
			entry.uid = allocate_uid()
		_commit_placement(entry, rect)
		diff.record_added(entry.item_id, entry.count)
		diff.mark_uid(entry.uid)
		notify_changed(diff)
		return Result.ok(diff)

	if blockers.size() == 1:
		var target_uid: int = blockers[0]
		var target_st: ItemStack = _items.get(target_uid, null) as ItemStack
		var merge_pred: Callable = _get_merge_predicate()
		if (
			target_st != null
			and target_st.can_merge_with(stack, spec.max_stack, merge_pred)
			and target_st.count + stack.count <= spec.max_stack
		):
			target_st.count += stack.count
			diff.record_added(stack.item_id, stack.count)
			diff.mark_uid(target_uid)
			notify_changed(diff)
			return Result.ok(diff)

	return Result.err_code(InventoryError.COLLISION, "Grid region %s is occupied." % str(rect))


## 移动网格内已放置实例 [param uid] 至新左上角锚点 [param target_pos] 与新朝向 [param target_rotated]（碰撞检测自动忽略自身原占地，支持拖入同类堆合并）。
func move_item(uid: int, target_pos: Vector2i, target_rotated: bool) -> Result:
	if not _items.has(uid):
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Item uid %d not found in grid." % uid)

	var st: ItemStack = _items.get(uid, null) as ItemStack
	var spec: ItemSpec = resolve_spec(st.item_id)
	if spec == null:
		return Result.err_code(InventoryError.SPEC_NOT_FOUND, "ItemSpec missing for '%s'." % String(st.item_id))
	if target_rotated and not spec.rotatable:
		return Result.err_code(InventoryError.ROTATION_FORBIDDEN, "Item '%s' cannot be rotated." % String(st.item_id))

	var old_rect: Rect2i = get_item_rect(uid)
	var new_rect := Rect2i(target_pos, spec.get_effective_size(target_rotated))
	if old_rect == new_rect and st.rotated == target_rotated:
		return Result.ok(InventoryDiff.new(container_id))
	if not is_rect_in_bounds(new_rect):
		return Result.err_code(InventoryError.OUT_OF_BOUNDS, "Target rect %s out of grid bounds." % str(new_rect))

	var blockers: Array[int] = get_occupying_uids(new_rect, uid)
	var diff := InventoryDiff.new(container_id)

	if blockers.is_empty():
		_paint_buffer(_cells, old_rect, 0)
		st.rotated = target_rotated
		_rects[uid] = new_rect
		_paint_buffer(_cells, new_rect, uid)
		diff.mark_uid(uid)
		notify_changed(diff)
		return Result.ok(diff)

	if blockers.size() == 1:
		var dst_uid: int = blockers[0]
		var dst_st: ItemStack = _items.get(dst_uid, null) as ItemStack
		var merge_pred: Callable = _get_merge_predicate()
		if dst_st != null and dst_st.can_merge_with(st, spec.max_stack, merge_pred) and dst_st.count < spec.max_stack:
			var transfer_cnt: int = mini(spec.max_stack - dst_st.count, st.count)
			dst_st.count += transfer_cnt
			st.count -= transfer_cnt
			if st.count <= 0:
				_erase_placement(uid)
			diff.mark_uid(uid)
			diff.mark_uid(dst_uid)
			notify_changed(diff)
			return Result.ok(diff)

	return Result.err_code(InventoryError.COLLISION, "Cannot move uid %d to %s due to collision." % [uid, str(new_rect)])


## 以当前左上角锚点为基准原地翻转 [param uid] 的 90 度旋转朝向。
func rotate_item(uid: int) -> Result:
	if not _items.has(uid):
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Item uid %d not found in grid." % uid)
	var st: ItemStack = _items.get(uid, null) as ItemStack
	var cur_rect: Rect2i = get_item_rect(uid)
	return move_item(uid, cur_rect.position, not st.rotated)

#endregion


#region Snapshot Persistence

## 导出网格宽高与全部已放置实例的锚点坐标、占地尺寸及序列化物品字典（不冗余导出大体积格点数组）。
func capture_snapshot() -> Dictionary:
	var placements_out: Array[Dictionary] = []
	for uid: int in _order:
		var st: ItemStack = _items.get(uid, null) as ItemStack
		var rect: Rect2i = get_item_rect(uid)
		if st != null:
			placements_out.append({
				"x": rect.position.x,
				"y": rect.position.y,
				"w": rect.size.x,
				"h": rect.size.y,
				"stack": st.to_dict(true),
			})
	return {
		"container_id": String(container_id),
		"width": _width,
		"height": _height,
		"placements": placements_out,
	}


## 从 [param snapshot] 重建网格尺寸、实例映射与一维格点占用表，并自动对齐全局 UID 水位线。
func restore_snapshot(snapshot: Dictionary) -> Result:
	_width = maxi(1, int(snapshot.get("width", _width)))
	_height = maxi(1, int(snapshot.get("height", _height)))
	_cells.resize(_width * _height)
	_cells.fill(0)
	_items.clear()
	_rects.clear()
	_order.clear()

	var raw_placements: Variant = snapshot.get("placements", [])
	if raw_placements is Array:
		var arr: Array = raw_placements as Array
		for elem: Variant in arr:
			if not (elem is Dictionary):
				continue
			var entry_dict: Dictionary = elem as Dictionary
			var raw_stack: Variant = entry_dict.get("stack", null)
			if not (raw_stack is Dictionary):
				continue
			var st := ItemStack.new(raw_stack as Dictionary)
			if not st.is_valid():
				continue
			_ensure_uid(st, true)
			var spec: ItemSpec = resolve_spec(st.item_id)
			var w: int = int(entry_dict.get("w", spec.get_effective_size(st.rotated).x if spec != null else 1))
			var h: int = int(entry_dict.get("h", spec.get_effective_size(st.rotated).y if spec != null else 1))
			var x: int = int(entry_dict.get("x", 0))
			var y: int = int(entry_dict.get("y", 0))
			var rect := Rect2i(x, y, maxi(1, w), maxi(1, h))
			if is_rect_in_bounds(rect) and _is_region_free_on_buffer(_cells, rect, 0):
				_commit_placement(st, rect)

	return Result.ok(true)

#endregion


#region Internal Spatial Buffer Primitives

## 在给定一维缓冲 [param buffer] 上检测矩形 [param rect] 是否完全空闲（跳过 [param ignore_uid]）。
func _is_region_free_on_buffer(buffer: PackedInt32Array, rect: Rect2i, ignore_uid: int) -> bool:
	var x_end: int = rect.position.x + rect.size.x
	var y_end: int = rect.position.y + rect.size.y
	if rect.position.x < 0 or rect.position.y < 0 or x_end > _width or y_end > _height:
		return false
	for y: int in range(rect.position.y, y_end):
		var row_offset: int = y * _width
		for x: int in range(rect.position.x, x_end):
			var occ: int = buffer[row_offset + x]
			if occ != 0 and occ != ignore_uid:
				return false
	return true


## 将给定一维缓冲 [param buffer] 上矩形 [param rect] 覆盖的全部格点涂写为 [param fill_uid]（传 [code]0[/code] 即擦除）。
func _paint_buffer(buffer: PackedInt32Array, rect: Rect2i, fill_uid: int) -> void:
	var x_end: int = mini(_width, rect.position.x + rect.size.x)
	var y_end: int = mini(_height, rect.position.y + rect.size.y)
	for y: int in range(maxi(0, rect.position.y), y_end):
		var row_offset: int = y * _width
		for x: int in range(maxi(0, rect.position.x), x_end):
			buffer[row_offset + x] = fill_uid


## 在一维缓冲 [param buffer] 上搜索首个能容纳 [param spec] 的位置（优先保持 [param prefer_rotated]，允许时自动尝试正交旋转）。
func _find_fit_on_buffer(
	buffer: PackedInt32Array,
	spec: ItemSpec,
	prefer_rotated: bool,
	allow_auto_rotate: bool,
	ignore_uid: int
) -> Dictionary:
	var orientations: Array[bool] = []
	var initial_rot: bool = prefer_rotated and spec.rotatable
	orientations.append(initial_rot)
	# 正方形物品旋转前后占地一致，仅对长宽不等的异形物品追加第二朝向扫描
	if allow_auto_rotate and spec.rotatable and spec.grid_size.x != spec.grid_size.y:
		orientations.append(not initial_rot)

	for rot: bool in orientations:
		var eff: Vector2i = spec.get_effective_size(rot)
		if eff.x > _width or eff.y > _height:
			continue
		var max_x: int = _width - eff.x
		var max_y: int = _height - eff.y
		for y: int in range(0, max_y + 1):
			for x: int in range(0, max_x + 1):
				var candidate := Rect2i(x, y, eff.x, eff.y)
				if _is_region_free_on_buffer(buffer, candidate, ignore_uid):
					return {"found": true, "pos": Vector2i(x, y), "rotated": rot}

	return {"found": false, "pos": Vector2i(-1, -1), "rotated": false}


## 原子提交一件实例的入格登记与格点染色。
func _commit_placement(stack: ItemStack, rect: Rect2i) -> void:
	_items[stack.uid] = stack
	_rects[stack.uid] = rect
	if not _order.has(stack.uid):
		_order.append(stack.uid)
	_paint_buffer(_cells, rect, stack.uid)


## 原子擦除指定 [param uid] 的格点染色、包围盒与实例记录。
func _erase_placement(uid: int) -> void:
	if _rects.has(uid):
		var rect: Rect2i = get_item_rect(uid)
		_paint_buffer(_cells, rect, 0)
		_rects.erase(uid)
	_items.erase(uid)
	_order.erase(uid)


## 采集单格 [code](x, y)[/code] 上的异物邻居 UID 并去重追加至 [param out_list]。
func _collect_neighbor_cell(x: int, y: int, self_uid: int, out_list: Array[int]) -> void:
	if not is_valid_cell(x, y):
		return
	var other_uid: int = _cells[y * _width + x]
	if other_uid > 0 and other_uid != self_uid and not out_list.has(other_uid):
		out_list.append(other_uid)

#endregion
