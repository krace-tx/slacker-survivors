class_name SlotItemContainer
extends BaseItemContainer

## 定长一维槽位数组容器（Fixed-Capacity 1D Slot Array Container）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/containers/[/code][br]
## [b]适用游戏品类：[/b]传统 RPG 格子背包、生存建造快捷物品栏（Hotbar）、单格/多格角色装备栏、宝箱与商店货架。[br]
## [b]核心设计：[/b][br]
## 1. [b]位置记忆与空洞保留[/b]：底层维护定长 [code]Array[ItemStack][/code]，空槽以 [code]null[/code] 占位，尊重玩家手动摆放习惯；[br]
## 2. [b]全槽位实例可寻址[/b]：每个非空槽位均持有独立 [member ItemStack.uid]，同时支持按槽位下标 [code]index[/code] 与按 [code]uid[/code] 双向操作；[br]
## 3. [b]完备交互原语[/b]：内置定点放取（[method add_at] / [method remove_at]）、一站式拖拽松手（[method move_or_merge]）、
##    拆堆（[method split_at]）、碎片自动归并重排（[method sort]）与防吞物安全扩缩容（[method resize_capacity]）。[br]
##
## [codeblocks]
## [gdscript]
## var bag := SlotItemContainer.new(&"bag", 20, resolver)
## bag.add(ItemStack.create(&"potion_hp", 15)) # 自动分槽：槽 0 存满 10，槽 1 存 5
## bag.split_at(1, 2)                          # 从槽 1 拆出 2 瓶自动放入首个空槽（槽 2）
## bag.move_or_merge(2, 1)                     # 将槽 2 拖回槽 1 自动合并恢复为 5 瓶
## [/gdscript]
## [/codeblocks]


#region Properties & Internal State

## 槽位数组总长度（恒满足 [code]_capacity >= 1[/code]）。
var _capacity: int = 20

## 定长槽位存储表：下标范围 [code][0, _capacity - 1][/code]，空槽固定为 [code]null[/code]。
var _slots: Array[ItemStack] = []

## 容器总槽位容量（只读属性；运行期动态扩缩容请调用 [method resize_capacity]）。
var capacity: int:
	get:
		return _capacity

#endregion


#region Lifecycle

## 构造定长一维槽位容器。[br]
## [param p_container_id] 容器业务标识（默认 [code]&"bag_slots"[/code]）。[br]
## [param p_capacity] 初始槽位总容量（自动钳制为 [code]>= 1[/code]）。[br]
## [param p_spec_resolver] 物品静态规格反查回调。[br]
## [param p_rule] 可选容器准入与移除规则（如主手武器槽传 [code]capacity = 1[/code] + [code]with_all_tags([&"weapon"])[/code]）。[br]
## [param p_strict_spec] 是否开启严格规格缺失校验。
func _init(
	p_container_id: StringName = &"bag_slots",
	p_capacity: int = 20,
	p_spec_resolver: Callable = Callable(),
	p_rule: ContainerRule = null,
	p_strict_spec: bool = false
) -> void:
	super._init(p_container_id, p_spec_resolver, p_rule, p_strict_spec)
	_capacity = maxi(1, p_capacity)
	_slots.resize(_capacity)

#endregion


#region Slot-Specific Queries

## 判断槽位下标 [param index] 是否落在合法区间 [code][0, capacity - 1][/code] 内。
func is_valid_slot(index: int) -> bool:
	return index >= 0 and index < _capacity


## 判断槽位 [param index] 是否合法且当前为空槽（越界下标统一返回 [code]false[/code]）。
func is_slot_empty(index: int) -> bool:
	return is_valid_slot(index) and _slots[index] == null


## 读取指定槽位 [param index] 处物品堆的深拷贝副本；空槽或下标越界时返回 [code]null[/code]。
func get_slot(index: int) -> ItemStack:
	if not is_valid_slot(index) or _slots[index] == null:
		return null
	return _slots[index].clone_stack()


## 统计当前处于空闲状态（[code]null[/code]）的槽位数量，复杂度 O(capacity)。
func get_empty_slot_count() -> int:
	var empty_cnt: int = 0
	for i: int in _capacity:
		if _slots[i] == null:
			empty_cnt += 1
	return empty_cnt


## 统计当前已被物品占用的槽位数量。
func get_occupied_slot_count() -> int:
	return _capacity - get_empty_slot_count()


## 按实例唯一标识 [param uid] 反查其所在的槽位下标；未命中或 [code]uid <= 0[/code] 时返回 [code]-1[/code]。
func find_slot_by_uid(uid: int) -> int:
	if uid <= 0:
		return -1
	for i: int in _capacity:
		var st: ItemStack = _slots[i]
		if st != null and st.uid == uid:
			return i
	return -1

#endregion


#region BaseItemContainer Queries

## 扫描全部槽位并累加指定 [param item_id] 的总数量，复杂度 O(capacity)。
func get_total_count(item_id: StringName) -> int:
	if item_id.is_empty():
		return 0
	var total: int = 0
	for i: int in _capacity:
		var st: ItemStack = _slots[i]
		if st != null and st.item_id == item_id:
			total += st.count
	return total


## 按唯一实例 [param uid] 查找并返回对应槽位物品的深拷贝副本；未命中返回 [code]null[/code]。
func get_item_by_uid(uid: int) -> ItemStack:
	var idx: int = find_slot_by_uid(uid)
	return _slots[idx].clone_stack() if idx >= 0 else null


## 按槽位下标从左到右导出所有非空物品堆的深拷贝列表。
func get_all_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for i: int in _capacity:
		if _slots[i] != null:
			result.append(_slots[i].clone_stack())
	return result


## 判断所有槽位是否均为空。
func is_empty() -> bool:
	for i: int in _capacity:
		if _slots[i] != null:
			return false
	return true


## 计算当前容器对 [param stack] 的最大可容纳数量（综合已有同类未满槽余量 + 空槽数 × [member ItemSpec.max_stack]）。
func get_addable_count(stack: ItemStack) -> int:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return 0
	var spec: ItemSpec = val_res.value as ItemSpec
	var merge_pred: Callable = _get_merge_predicate()
	var total_room: int = 0
	var empty_slots: int = 0

	for i: int in _capacity:
		var cur: ItemStack = _slots[i]
		if cur == null:
			empty_slots += 1
		elif spec.is_stackable() and cur.can_merge_with(stack, spec.max_stack, merge_pred):
			total_room += maxi(0, spec.max_stack - cur.count)

	total_room += empty_slots * spec.max_stack
	return mini(stack.count, total_room)


## 预演校验整堆 [param stack] 是否能完整装入当前槽位容器；空间不足返回 [constant InventoryError.CAPACITY_FULL]。
func can_add(stack: ItemStack) -> Result:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return val_res
	if get_addable_count(stack) < stack.count:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"SlotItemContainer '%s' has insufficient space for %d of '%s'." % [
				String(container_id), stack.count, String(stack.item_id)
			]
		)
	return Result.ok(true)

#endregion


#region BaseItemContainer Mutations

## 自动寻槽放入整堆 [param stack]（两阶段分配：先填补所有可合并的未满槽，剩余数量按序拆块填入空槽）。
func add(stack: ItemStack) -> Result:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return val_res
	if get_addable_count(stack) < stack.count:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"SlotItemContainer '%s' is full." % String(container_id)
		)

	var spec: ItemSpec = val_res.value as ItemSpec
	var merge_pred: Callable = _get_merge_predicate()
	var remaining: int = stack.count
	var diff := InventoryDiff.new(container_id)

	# 阶段 1：优先填满已有可合并的半满槽位，避免过早消耗宝贵空槽
	if spec.is_stackable():
		for i: int in _capacity:
			if remaining <= 0:
				break
			var cur: ItemStack = _slots[i]
			if cur != null and cur.can_merge_with(stack, spec.max_stack, merge_pred):
				var room: int = spec.max_stack - cur.count
				if room > 0:
					var take: int = mini(room, remaining)
					cur.count += take
					remaining -= take
					diff.mark_slot(i)
					diff.mark_uid(cur.uid)

	# 阶段 2：将剩余数量按 max_stack 切片依次填入前部空闲槽位
	var preserve_uid: bool = stack.uid > 0 and find_slot_by_uid(stack.uid) < 0
	for i: int in _capacity:
		if remaining <= 0:
			break
		if _slots[i] == null:
			var chunk: int = mini(remaining, spec.max_stack)
			var entry: ItemStack = stack.clone_stack()
			entry.count = chunk
			if preserve_uid:
				sync_uid_floor(entry.uid)
				preserve_uid = false
			else:
				entry.uid = allocate_uid()
			_slots[i] = entry
			remaining -= chunk
			diff.mark_slot(i)
			diff.mark_uid(entry.uid)

	diff.record_added(stack.item_id, stack.count)
	notify_changed(diff)
	return Result.ok(diff)


## 按 [param item_id] 原子扣减 [param count] 个物品（采用双趟扫描：首趟仅扣减无扩展元数据的标准堆，次趟再兜底扣减带元数据堆）。
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
		for i: int in _capacity:
			if remaining <= 0:
				break
			var st: ItemStack = _slots[i]
			if st == null or st.item_id != item_id:
				continue
			if not allow_meta and st.has_meta_payload():
				continue
			var take: int = mini(st.count, remaining)
			var old_uid: int = st.uid
			st.count -= take
			remaining -= take
			if st.count <= 0:
				_slots[i] = null
			diff.mark_slot(i)
			diff.mark_uid(old_uid)

	diff.record_removed(item_id, count)
	notify_changed(diff)
	return Result.ok(diff)


## 按唯一实例 [param uid] 定位槽位并移除 [param count] 个物品（传 [code]-1[/code] 整格移除）。
func remove_by_uid(uid: int, count: int = -1) -> Result:
	if uid <= 0 or count == 0 or count < -1:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid uid or count.")
	var idx: int = find_slot_by_uid(uid)
	if idx < 0:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Item uid %d not found." % uid)
	return remove_at(idx, count)


## 清空全部非空槽位，精准标记所有原先有物的槽位下标至 [member InventoryDiff.changed_slots]。
func clear() -> InventoryDiff:
	var diff := InventoryDiff.new(container_id)
	for i: int in _capacity:
		var st: ItemStack = _slots[i]
		if st != null:
			diff.record_removed(st.item_id, st.count)
			diff.mark_slot(i)
			diff.mark_uid(st.uid)
			_slots[i] = null
	notify_changed(diff)
	return diff

#endregion


#region Slot-Specific Atomic Operations

## 定点向指定槽位 [param index] 放入或合并整堆 [param stack]（单槽严格模式：若单槽装不下绝不静默溢出至其它槽位）。[br]
## [param index] 目标槽位下标。[br]
## [param stack] 待放入物品堆（要求 [code]stack.count <= spec.max_stack[/code]）。
func add_at(index: int, stack: ItemStack) -> Result:
	if not is_valid_slot(index):
		return Result.err_code(InventoryError.OUT_OF_BOUNDS, "Slot index %d out of bounds." % index)
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return val_res

	var spec: ItemSpec = val_res.value as ItemSpec
	if stack.count > spec.max_stack:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"Stack count (%d) exceeds max_stack (%d) for single slot." % [stack.count, spec.max_stack]
		)

	var existing: ItemStack = _slots[index]
	var diff := InventoryDiff.new(container_id)

	if existing == null:
		var entry: ItemStack = stack.clone_stack()
		if entry.uid > 0 and find_slot_by_uid(entry.uid) < 0:
			sync_uid_floor(entry.uid)
		else:
			entry.uid = allocate_uid()
		_slots[index] = entry
		diff.record_added(entry.item_id, entry.count)
		diff.mark_slot(index)
		diff.mark_uid(entry.uid)
		notify_changed(diff)
		return Result.ok(diff)

	var merge_pred: Callable = _get_merge_predicate()
	if not existing.can_merge_with(stack, spec.max_stack, merge_pred):
		return Result.err_code(
			InventoryError.MERGE_INCOMPATIBLE,
			"Slot %d is occupied by an incompatible stack." % index
		)
	if existing.count + stack.count > spec.max_stack:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"Slot %d cannot fit %d more (current %d / max %d)." % [
				index, stack.count, existing.count, spec.max_stack
			]
		)

	existing.count += stack.count
	diff.record_added(stack.item_id, stack.count)
	diff.mark_slot(index)
	diff.mark_uid(existing.uid)
	notify_changed(diff)
	return Result.ok(diff)


## 从指定槽位 [param index] 定点移除 [param count] 个物品（传 [code]-1[/code] 清空整格）。
func remove_at(index: int, count: int = -1) -> Result:
	if not is_valid_slot(index):
		return Result.err_code(InventoryError.OUT_OF_BOUNDS, "Slot index %d out of bounds." % index)
	if count == 0 or count < -1:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid remove count %d." % count)
	var rm_res: Result = _validate_remove_allowed()
	if rm_res.is_err():
		return rm_res

	var st: ItemStack = _slots[index]
	if st == null:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Slot %d is empty." % index)

	var actual: int = st.count if count == -1 else count
	if actual > st.count:
		return Result.err_code(
			InventoryError.INSUFFICIENT_ITEM,
			"Slot %d has %d, cannot remove %d." % [index, st.count, actual]
		)

	var diff := InventoryDiff.new(container_id)
	diff.record_removed(st.item_id, actual)
	diff.mark_slot(index)
	diff.mark_uid(st.uid)

	st.count -= actual
	if st.count <= 0:
		_slots[index] = null

	notify_changed(diff)
	return Result.ok(diff)


## 容器内槽位拖拽松手核心原语（自动裁决「移入空槽 / 同类合堆留余 / 满堆或异类互换」）：[br]
## [param from_index] 拖拽起始槽位下标。[br]
## [param to_index] 拖拽落点槽位下标。[br]
## 注意：属于容器内部重排，返回的 [InventoryDiff] 仅标记受影响的槽位与 UID，净增减统计恒为空。
func move_or_merge(from_index: int, to_index: int) -> Result:
	if not is_valid_slot(from_index) or not is_valid_slot(to_index):
		return Result.err_code(InventoryError.OUT_OF_BOUNDS, "Slot index out of bounds.")
	if from_index == to_index:
		return Result.ok(InventoryDiff.new(container_id))

	var src: ItemStack = _slots[from_index]
	if src == null:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Source slot %d is empty." % from_index)

	var dst: ItemStack = _slots[to_index]
	var diff := InventoryDiff.new(container_id)

	# 分支 1：目标为空槽 -> 原实例直接平移，UID 无损保留
	if dst == null:
		_slots[to_index] = src
		_slots[from_index] = null
		diff.mark_slot(from_index)
		diff.mark_slot(to_index)
		diff.mark_uid(src.uid)
		notify_changed(diff)
		return Result.ok(diff)

	var spec: ItemSpec = resolve_spec(src.item_id)
	var max_stack: int = spec.max_stack if spec != null else 1
	var merge_pred: Callable = _get_merge_predicate()

	# 分支 2：目标为可合并同类且未达上限 -> 尽可能合入目标槽，溢出部分留回源槽
	if dst.can_merge_with(src, max_stack, merge_pred) and dst.count < max_stack:
		var transfer_cnt: int = mini(max_stack - dst.count, src.count)
		var old_src_uid: int = src.uid
		dst.count += transfer_cnt
		src.count -= transfer_cnt
		if src.count <= 0:
			_slots[from_index] = null
		diff.mark_slot(from_index)
		diff.mark_slot(to_index)
		diff.mark_uid(old_src_uid)
		diff.mark_uid(dst.uid)
		notify_changed(diff)
		return Result.ok(diff)

	# 分支 3：目标已满或为异类物品 -> 执行双槽位 O(1) 原地互换
	_slots[from_index] = dst
	_slots[to_index] = src
	diff.mark_slot(from_index)
	diff.mark_slot(to_index)
	diff.mark_uid(src.uid)
	diff.mark_uid(dst.uid)
	notify_changed(diff)
	return Result.ok(diff)


## 从 [param from_index] 槽位拆出 [param split_count] 个物品放入目标槽 [param to_index]（传 [code]-1[/code] 自动定位首个空槽）。[br]
## 支持拆入空槽（自动分配新 UID）或拆入同类未满槽（定量补充合并）。
func split_at(from_index: int, split_count: int, to_index: int = -1) -> Result:
	if not is_valid_slot(from_index):
		return Result.err_code(InventoryError.OUT_OF_BOUNDS, "Source slot %d out of bounds." % from_index)
	var src: ItemStack = _slots[from_index]
	if src == null:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Source slot %d is empty." % from_index)
	if split_count <= 0 or split_count >= src.count:
		return Result.err_code(
			InventoryError.INVALID_PARAM,
			"split_count (%d) must be in [1, %d]." % [split_count, src.count - 1]
		)

	var target_slot: int = to_index
	if target_slot == -1:
		for i: int in _capacity:
			if _slots[i] == null:
				target_slot = i
				break
		if target_slot < 0:
			return Result.err_code(InventoryError.CAPACITY_FULL, "No empty slot available to split into.")
	elif not is_valid_slot(target_slot) or target_slot == from_index:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid target slot %d for split." % target_slot)

	var dst: ItemStack = _slots[target_slot]
	var spec: ItemSpec = resolve_spec(src.item_id)
	var max_stack: int = spec.max_stack if spec != null else 99
	var merge_pred: Callable = _get_merge_predicate()

	if dst != null:
		if not dst.can_merge_with(src, max_stack, merge_pred):
			return Result.err_code(InventoryError.MERGE_INCOMPATIBLE, "Target slot holds incompatible item.")
		if dst.count + split_count > max_stack:
			return Result.err_code(InventoryError.CAPACITY_FULL, "Target slot cannot absorb split amount.")
		src.count -= split_count
		dst.count += split_count
		var merge_diff := InventoryDiff.new(container_id)
		merge_diff.mark_slot(from_index)
		merge_diff.mark_slot(target_slot)
		merge_diff.mark_uid(src.uid)
		merge_diff.mark_uid(dst.uid)
		notify_changed(merge_diff)
		return Result.ok(merge_diff)

	var split_res: Result = src.split_off(split_count, allocate_uid())
	if split_res.is_err():
		return split_res
	var separated: ItemStack = split_res.value as ItemStack
	_slots[target_slot] = separated

	var diff := InventoryDiff.new(container_id)
	diff.mark_slot(from_index)
	diff.mark_slot(target_slot)
	diff.mark_uid(src.uid)
	diff.mark_uid(separated.uid)
	notify_changed(diff)
	return Result.ok(diff)


## 一键整理容器：先自动合并所有分散的同类半满碎片堆，再按排序规则紧凑排列至前部槽位。[br]
## [param custom_comparator] 可选自定义排序闭包（签名：[code]func(a: ItemStack, b: ItemStack) -> bool[/code]）；
## 省略时默认按「[member ItemSpec.sort_priority] 降序 ➔ [member ItemStack.item_id] 字典升序 ➔ 数量降序 ➔ UID 升序」稳定排列。
func sort(custom_comparator: Callable = Callable()) -> Result:
	var compacted: Array[ItemStack] = []
	var merge_pred: Callable = _get_merge_predicate()

	# 步骤 1：顺序扫描并归并同类可堆叠碎片，消除零散占槽
	for i: int in _capacity:
		var cur: ItemStack = _slots[i]
		if cur == null:
			continue
		var working: ItemStack = cur.clone_stack()
		var spec: ItemSpec = resolve_spec(working.item_id)
		var max_stack: int = spec.max_stack if spec != null else 1
		if max_stack > 1:
			for prev: ItemStack in compacted:
				if working.count <= 0:
					break
				if prev.can_merge_with(working, max_stack, merge_pred) and prev.count < max_stack:
					var take: int = mini(max_stack - prev.count, working.count)
					prev.count += take
					working.count -= take
		if working.count > 0:
			compacted.append(working)

	# 步骤 2：执行稳定排序
	if custom_comparator.is_valid():
		compacted.sort_custom(custom_comparator)
	else:
		compacted.sort_custom(_default_stack_less_than)

	# 步骤 3：逐槽位比对新旧状态，仅将真正发生变化的槽位标记进 changed_slots
	var diff := InventoryDiff.new(container_id)
	for i: int in _capacity:
		var next_st: ItemStack = compacted[i] if i < compacted.size() else null
		var prev_st: ItemStack = _slots[i]
		if not _is_same_slot_state(prev_st, next_st):
			diff.mark_slot(i)
			if prev_st != null:
				diff.mark_uid(prev_st.uid)
			if next_st != null:
				diff.mark_uid(next_st.uid)
		_slots[i] = next_st

	notify_changed(diff)
	return Result.ok(diff)


## 动态扩缩槽位总容量至 [param new_capacity]（如购买背包扩容格或卸下扩容袋）。[br]
## 安全铁律：当请求缩容（[code]new_capacity < capacity[/code]）且被裁切尾部槽位内仍有物品时，
## 立即拒绝并返回 [constant InventoryError.CAPACITY_FULL]，绝不静默吞没玩家道具。
func resize_capacity(new_capacity: int) -> Result:
	if new_capacity <= 0:
		return Result.err_code(InventoryError.INVALID_PARAM, "new_capacity must be >= 1.")
	if new_capacity == _capacity:
		return Result.ok(InventoryDiff.new(container_id))

	if new_capacity < _capacity:
		for i: int in range(new_capacity, _capacity):
			if _slots[i] != null:
				return Result.err_code(
					InventoryError.CAPACITY_FULL,
					"Cannot shrink capacity to %d: slot %d is occupied." % [new_capacity, i]
				)

	_capacity = new_capacity
	_slots.resize(_capacity)
	return Result.ok(InventoryDiff.new(container_id))

#endregion


#region Snapshot Persistence

## 导出保留精确空槽（[code]null[/code]）位置的一维槽位数组快照字典。
func capture_snapshot() -> Dictionary:
	var serialized_slots: Array = []
	serialized_slots.resize(_capacity)
	for i: int in _capacity:
		var st: ItemStack = _slots[i]
		serialized_slots[i] = st.to_dict(true) if st != null else null
	return {
		"container_id": String(container_id),
		"capacity": _capacity,
		"slots": serialized_slots,
	}


## 从 [param snapshot] 还原槽位容量与精确槽位排布，并同步抬升全局 UID 水位线。
func restore_snapshot(snapshot: Dictionary) -> Result:
	var snap_cap: int = maxi(1, int(snapshot.get("capacity", _capacity)))
	_capacity = snap_cap
	_slots.clear()
	_slots.resize(_capacity)

	var raw_slots: Variant = snapshot.get("slots", [])
	if raw_slots is Array:
		var arr: Array = raw_slots as Array
		var limit: int = mini(_capacity, arr.size())
		for i: int in limit:
			var elem: Variant = arr[i]
			if elem is Dictionary:
				var st := ItemStack.new(elem as Dictionary)
				if st.is_valid():
					_ensure_uid(st, true)
					_slots[i] = st
	return Result.ok(true)

#endregion


#region Internal Comparators

## 默认多级稳定排序比较器：优先级权重降序 -> item_id 升序 -> 堆叠数量降序 -> 实例 UID 升序。
func _default_stack_less_than(a: ItemStack, b: ItemStack) -> bool:
	var spec_a: ItemSpec = resolve_spec(a.item_id)
	var spec_b: ItemSpec = resolve_spec(b.item_id)
	var prio_a: int = spec_a.sort_priority if spec_a != null else 0
	var prio_b: int = spec_b.sort_priority if spec_b != null else 0
	if prio_a != prio_b:
		return prio_a > prio_b
	if a.item_id != b.item_id:
		return String(a.item_id) < String(b.item_id)
	if a.count != b.count:
		return a.count > b.count
	return a.uid < b.uid


## 比对整理前后同一槽位的新旧引用值是否完全未变，避免无变化槽位触发冗余重绘。
func _is_same_slot_state(a: ItemStack, b: ItemStack) -> bool:
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	return a.uid == b.uid and a.item_id == b.item_id and a.count == b.count and a.meta == b.meta

#endregion
