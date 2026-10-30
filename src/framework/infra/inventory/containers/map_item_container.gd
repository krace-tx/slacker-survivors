class_name MapItemContainer
extends BaseItemContainer

## 字典聚合与独立实例双轨无槽位容器（Map-Aggregated & Unique-Instance Hybrid Container）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/containers/[/code][br]
## [b]适用游戏品类：[/b]货币钱包、RPG/动作局外养成材料库、卡牌/挂机类无需玩家手动拖拽摆格子的背包。[br]
## [b]底层双轨存储不变式：[/b][br]
## 1. [b]纯可替代标准品轨（Fungible Track）[/b]：凡满足 [code]spec.is_stackable()[/code] 且无动态 [member ItemStack.meta] 的标准物品，
##    直接收敛至 [code]_fungible_counts: Dictionary[StringName, int][/code] 累加计数——查询、发放与消耗均为严格 O(1) 且零对象碎片；[br]
## 2. [b]独立属性个体轨（Unique Track）[/b]：凡不可堆叠（如武器/遗物）或携带动态词条元数据的物品，
##    自动分配唯一 [member ItemStack.uid] 存入保序实例表，并支持通过 [member max_unique_capacity] 限制装备/遗物持有上限。


#region Properties & Internal Data Structures

## 独立属性个体（装备/词条物）的最大条目容量上限（[code]0[/code] 表示不限制个体上限；不影响纯标准计数池）。
var max_unique_capacity: int = 0

## 轨道一：纯标准可堆叠物计数表（StringName item_id -> int total_count，严格保持仅存 > 0 的有效键）。
var _fungible_counts: Dictionary = {}

## 轨道二：独立实例哈希映射表（int uid -> ItemStack，提供 O(1) 按 UID 定点检索）。
var _unique_items: Dictionary = {}

## 独立实例确定性入库顺序数组（保证遍历、按 ID 批量消耗以及快照导出顺序 100% 可复现）。
var _unique_order: Array[int] = []

#endregion


#region Lifecycle

## 构造字典型混合容器。[br]
## [param p_container_id] 容器业务标识（默认 [code]&"bag_map"[/code]）。[br]
## [param p_max_unique_capacity] 独立个体实例上限（[code]0[/code] 为无上限）。[br]
## [param p_spec_resolver] 物品静态规格反查回调。[br]
## [param p_rule] 可选容器准入与移除规则。[br]
## [param p_strict_spec] 是否开启严格规格缺失校验。
func _init(
	p_container_id: StringName = &"bag_map",
	p_max_unique_capacity: int = 0,
	p_spec_resolver: Callable = Callable(),
	p_rule: ContainerRule = null,
	p_strict_spec: bool = false
) -> void:
	super._init(p_container_id, p_spec_resolver, p_rule, p_strict_spec)
	max_unique_capacity = maxi(0, p_max_unique_capacity)

#endregion


#region Map-Specific & Base Queries

## 获取当前独立实例轨（Unique Track）已占用的条目数量。
func get_unique_count() -> int:
	return _unique_order.size()


## 查询指定 [param item_id] 的总持有量（纯计数池 O(1) 读取 + 独立实例表同名累加）。
func get_total_count(item_id: StringName) -> int:
	if item_id.is_empty():
		return 0
	var total: int = int(_fungible_counts.get(item_id, 0))
	for uid: int in _unique_order:
		var st: ItemStack = _unique_items.get(uid, null) as ItemStack
		if st != null and st.item_id == item_id:
			total += st.count
	return total


## 按唯一实例 [param uid] O(1) 查找独立物品堆并返回深拷贝副本（标准计数池物品无独立 UID，返回 [code]null[/code]）。
func get_item_by_uid(uid: int) -> ItemStack:
	if uid <= 0 or not _unique_items.has(uid):
		return null
	var st: ItemStack = _unique_items.get(uid, null) as ItemStack
	return st.clone_stack() if st != null else null


## 导出全部物品堆的克隆列表（先按字典序导出标准计数池，再按入库顺序导出全部独立个体）。
func get_all_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	var ids: Array = _fungible_counts.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for raw_id: Variant in ids:
		var item_id: StringName = StringName(str(raw_id))
		var cnt: int = int(_fungible_counts[raw_id])
		if cnt > 0:
			result.append(ItemStack.create(item_id, cnt))
	for uid: int in _unique_order:
		var st: ItemStack = _unique_items.get(uid, null) as ItemStack
		if st != null:
			result.append(st.clone_stack())
	return result


## 判断标准计数池与独立实例表是否均为空。
func is_empty() -> bool:
	return _fungible_counts.is_empty() and _unique_order.is_empty()


## 计算最多可放入的 [param stack] 数量（标准可替代品无上限；独立个体受 [member max_unique_capacity] 与同类可合并余量共同约束）。
func get_addable_count(stack: ItemStack) -> int:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return 0
	var spec: ItemSpec = val_res.value as ItemSpec
	if _is_fungible_eligible(stack, spec):
		return stack.count

	var merge_pred: Callable = _get_merge_predicate()
	var capacity_gain: int = 0
	if spec.is_stackable():
		for uid: int in _unique_order:
			var existing: ItemStack = _unique_items.get(uid, null) as ItemStack
			if existing != null and existing.can_merge_with(stack, spec.max_stack, merge_pred):
				capacity_gain += maxi(0, spec.max_stack - existing.count)

	if max_unique_capacity <= 0:
		return stack.count

	var free_entries: int = maxi(0, max_unique_capacity - _unique_order.size())
	capacity_gain += free_entries * spec.max_stack
	return mini(stack.count, capacity_gain)


## 预演校验整堆 [param stack] 是否可完整入库；超出独立个体配额时返回 [constant InventoryError.CAPACITY_FULL]。
func can_add(stack: ItemStack) -> Result:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return val_res
	if get_addable_count(stack) < stack.count:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"MapItemContainer '%s' unique capacity (%d) exceeded." % [String(container_id), max_unique_capacity]
		)
	return Result.ok(true)

#endregion


#region Mutation Implementation

## 原子入库整堆 [param stack]：标准品 O(1) 累加计数；带元数据或不可堆叠个体优先合并已有堆，余量分配新 UID 入表。
func add(stack: ItemStack) -> Result:
	var val_res: Result = _validate_accept_and_resolve(stack)
	if val_res.is_err():
		return val_res
	if get_addable_count(stack) < stack.count:
		return Result.err_code(
			InventoryError.CAPACITY_FULL,
			"MapItemContainer '%s' cannot fit %d of '%s'." % [
				String(container_id), stack.count, String(stack.item_id)
			]
		)

	var spec: ItemSpec = val_res.value as ItemSpec
	var diff := InventoryDiff.new(container_id)

	# 分支 1：纯可替代标准品直接走 O(1) 整数累加
	if _is_fungible_eligible(stack, spec):
		var prev: int = int(_fungible_counts.get(stack.item_id, 0))
		_fungible_counts[stack.item_id] = prev + stack.count
		diff.record_added(stack.item_id, stack.count)
		notify_changed(diff)
		return Result.ok(diff)

	# 分支 2：带扩展元数据的堆叠物或不可堆叠个体
	var remaining: int = stack.count
	var merge_pred: Callable = _get_merge_predicate()
	if spec.is_stackable():
		for uid: int in _unique_order:
			if remaining <= 0:
				break
			var existing: ItemStack = _unique_items.get(uid, null) as ItemStack
			if existing != null and existing.can_merge_with(stack, spec.max_stack, merge_pred):
				var room: int = spec.max_stack - existing.count
				if room > 0:
					var take: int = mini(room, remaining)
					existing.count += take
					remaining -= take
					diff.mark_uid(existing.uid)

	# 若首件自带外部有效 UID（如从槽位/网格跨容器转入的词条装备），无损继承原 UID
	var preserve_incoming_uid: bool = stack.uid > 0 and not _unique_items.has(stack.uid)
	while remaining > 0:
		var chunk: int = mini(remaining, spec.max_stack)
		var entry: ItemStack = stack.clone_stack()
		entry.count = chunk
		if preserve_incoming_uid:
			sync_uid_floor(entry.uid)
			preserve_incoming_uid = false
		else:
			entry.uid = allocate_uid()
		_unique_items[entry.uid] = entry
		_unique_order.append(entry.uid)
		diff.mark_uid(entry.uid)
		remaining -= chunk

	diff.record_added(stack.item_id, stack.count)
	notify_changed(diff)
	return Result.ok(diff)


## 按 [param item_id] 原子消耗 [param count] 个物品（严格先扣减无元数据的标准计数池，不足部分再按入库顺序扣减独立实例）。
func remove_by_id(item_id: StringName, count: int = 1) -> Result:
	if item_id.is_empty() or count <= 0:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid item_id or count.")
	var rm_rule_res: Result = _validate_remove_allowed()
	if rm_rule_res.is_err():
		return rm_rule_res
	if not has_enough(item_id, count):
		return Result.err_code(
			InventoryError.INSUFFICIENT_ITEM,
			"Insufficient '%s': required %d, owned %d." % [String(item_id), count, get_total_count(item_id)]
		)

	var remaining: int = count
	var diff := InventoryDiff.new(container_id)

	# 阶段 1：优先扣减标准计数池，归零时立即擦除键以维持 is_empty() 精确性
	var fungible_owned: int = int(_fungible_counts.get(item_id, 0))
	if fungible_owned > 0:
		var take_f: int = mini(fungible_owned, remaining)
		var left_f: int = fungible_owned - take_f
		if left_f > 0:
			_fungible_counts[item_id] = left_f
		else:
			_fungible_counts.erase(item_id)
		remaining -= take_f

	# 阶段 2：余量按入库先后顺序扣减独立实例表
	var idx: int = 0
	while remaining > 0 and idx < _unique_order.size():
		var uid: int = _unique_order[idx]
		var st: ItemStack = _unique_items.get(uid, null) as ItemStack
		if st == null or st.item_id != item_id:
			idx += 1
			continue
		var take_u: int = mini(st.count, remaining)
		st.count -= take_u
		remaining -= take_u
		diff.mark_uid(uid)
		if st.count <= 0:
			_unique_items.erase(uid)
			_unique_order.remove_at(idx)
		else:
			idx += 1

	diff.record_removed(item_id, count)
	notify_changed(diff)
	return Result.ok(diff)


## 按唯一实例 [param uid] 扣减指定 [param count] 个物品（传 [code]-1[/code] 整堆销毁）。
func remove_by_uid(uid: int, count: int = -1) -> Result:
	if uid <= 0 or count == 0 or count < -1:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid uid or count.")
	var rm_rule_res: Result = _validate_remove_allowed()
	if rm_rule_res.is_err():
		return rm_rule_res
	if not _unique_items.has(uid):
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Item uid %d not found." % uid)

	var st: ItemStack = _unique_items.get(uid, null) as ItemStack
	var actual_remove: int = st.count if count == -1 else count
	if actual_remove > st.count:
		return Result.err_code(
			InventoryError.INSUFFICIENT_ITEM,
			"Item uid %d has %d, cannot remove %d." % [uid, st.count, actual_remove]
		)

	var diff := InventoryDiff.new(container_id)
	diff.record_removed(st.item_id, actual_remove)
	diff.mark_uid(uid)

	st.count -= actual_remove
	if st.count <= 0:
		_unique_items.erase(uid)
		_unique_order.erase(uid)

	notify_changed(diff)
	return Result.ok(diff)


## 清空标准计数池与全部独立实例，并返回汇总移除量的 [InventoryDiff]。
func clear() -> InventoryDiff:
	var diff := InventoryDiff.new(container_id)
	for raw_id: Variant in _fungible_counts:
		var item_id: StringName = StringName(str(raw_id))
		diff.record_removed(item_id, int(_fungible_counts[raw_id]))
	for uid: int in _unique_order:
		var st: ItemStack = _unique_items.get(uid, null) as ItemStack
		if st != null:
			diff.record_removed(st.item_id, st.count)
			diff.mark_uid(uid)

	_fungible_counts.clear()
	_unique_items.clear()
	_unique_order.clear()
	notify_changed(diff)
	return diff

#endregion


#region Snapshot Persistence

## 导出包含 [code]fungible[/code] 计数表与保序 [code]uniques[/code] 数组的纯净 JSON 友好字典快照。
func capture_snapshot() -> Dictionary:
	var fungible_out: Dictionary = {}
	for raw_id: Variant in _fungible_counts:
		var cnt: int = int(_fungible_counts[raw_id])
		if cnt > 0:
			fungible_out[String(raw_id)] = cnt

	var unique_out: Array[Dictionary] = []
	for uid: int in _unique_order:
		var st: ItemStack = _unique_items.get(uid, null) as ItemStack
		if st != null:
			unique_out.append(st.to_dict(true))

	return {
		"container_id": String(container_id),
		"max_unique_capacity": max_unique_capacity,
		"fungible": fungible_out,
		"uniques": unique_out,
	}


## 从 [param snapshot] 字典恢复双轨存储状态，并自动调用 [method BaseItemContainer.sync_uid_floor] 对齐全局 UID 水位线。
func restore_snapshot(snapshot: Dictionary) -> Result:
	_fungible_counts.clear()
	_unique_items.clear()
	_unique_order.clear()

	if snapshot.has("max_unique_capacity"):
		max_unique_capacity = maxi(0, int(snapshot.get("max_unique_capacity", 0)))

	var raw_fungible: Variant = snapshot.get("fungible", {})
	if raw_fungible is Dictionary:
		var f_dict: Dictionary = raw_fungible as Dictionary
		for raw_key: Variant in f_dict:
			var item_id: StringName = StringName(str(raw_key))
			var cnt: int = int(f_dict[raw_key])
			if not item_id.is_empty() and cnt > 0:
				_fungible_counts[item_id] = cnt

	var raw_uniques: Variant = snapshot.get("uniques", [])
	if raw_uniques is Array:
		var u_arr: Array = raw_uniques as Array
		for elem: Variant in u_arr:
			if elem is Dictionary:
				var st := ItemStack.new(elem as Dictionary)
				if st.is_valid():
					_ensure_uid(st, true)
					_unique_items[st.uid] = st
					_unique_order.append(st.uid)

	return Result.ok(true)

#endregion


#region Internal Helpers

## 判定 [param stack] 是否具备进入 O(1) 纯标准计数池的资格：[br]
## 要求静态规格支持复数堆叠、当前堆未携带任何扩展元数据字典，且容器未挂载自定义特殊合并谓词。
func _is_fungible_eligible(stack: ItemStack, spec: ItemSpec) -> bool:
	if not spec.is_stackable():
		return false
	if stack.has_meta_payload():
		return false
	if rule != null and rule.custom_merge_predicate.is_valid():
		return false
	return true

#endregion
