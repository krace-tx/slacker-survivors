class_name InventoryTransaction
extends RefCounted

## 跨容器原子转移、双向换装互换与快照保护多步事务协调器（Atomic Cross-Container Transaction Coordinator）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/transaction/[/code][br]
## [b]解决的核心痛点（为什么不能直接分步调容器 API）：[/b][br]
## 1. [b]杜绝非原子半截脏状态[/b]：锻造、商店购买、开箱等复合操作涉及多个容器的扣费与发奖，
##    一旦最后一步背包空间不足，前置扣掉的货币与材料若不回滚将造成严重的经济吞道具事故；[br]
## 2. [b]攻克「满包消耗腾位悖论」[/b]：当 10/10 满槽背包消耗整格 10 个铁矿锻造 1 把铁剑时，
##    静态前置 [code]can_add[/code] 会误判满包失败；本事务器基于前置快照按真实顺序推演（先扣铁矿腾出空槽 ➔ 再放铁剑），天然支持原地换位合成；[br]
## 3. [b]信号消抖合并[/b]：一次包含 5 个步骤的复合事务在提交成功时，每个受波及容器仅触发 [b]1 次[/b] 合并后的 [signal BaseItemContainer.changed]；[br]
## 4. [b]跨容器一键换装[/b]：[method transfer_slot] 在背包已满时仍支持将背包装备与装备栏旧装备双向校验后原地原子互换。[br]
##
## [codeblocks]
## [gdscript]
## var tx := InventoryTransaction.new() \
##     .take_by_id(wallet, &"gold", 300) \
##     .take_by_id(bag, &"ore_iron", 10) \
##     .give(bag, ItemStack.create(&"sword_iron", 1, {"atk": 25}))
## var res: Result = tx.commit() # 全成返回 Result.ok(InventoryDiff)，任一步失败全量无损回滚
## [/gdscript]
## [/codeblocks]


#region Internal Step Enum & State

## 事务队列内部原子指令类型枚举。
enum _OpKind {
	TAKE_BY_ID = 0,    ## 按配置 ID 定量消耗
	TAKE_BY_UID = 1,   ## 按唯一实例 UID 定量或整堆移除
	TAKE_AT_SLOT = 2,  ## 按一维槽位下标定量或整格移除
	GIVE_AUTO = 3,     ## 自动寻位/寻槽发放物品
	GIVE_AT_SLOT = 4,  ## 向一维槽位容器指定下标定点放入
	GIVE_AT_GRID = 5,  ## 向二维网格容器指定坐标与朝向定点放入
}

## 待执行的有序指令字典队列。
var _steps: Array[Dictionary] = []

## 纯搬运事务标记：为 [code]true[/code] 时表示跨容器平移或互换，提交后自动清零经济净增减统计（仅保留脏槽/UID/ID 通知）。
var _is_transfer_only: bool = false

#endregion


#region Static Cross-Container Transfer Primitives

## 任意异构容器间按唯一实例 [param uid] 原子搬运物品（支持 `Grid <-> Slot`、`Slot <-> Map`、`Grid <-> Map` 任意组合）。[br]
## [param src] 转出源容器（需通过 [method ContainerRule.evaluate_remove] 校验）。[br]
## [param dst] 转入目标容器（需通过目标容器的 [ContainerRule] 与容量校验）。[br]
## [param uid] 待转移物品在源容器中的实例 UID。[br]
## [param count] 转移数量（传 [code]-1[/code] 表示整堆搬运；传小于原堆数量时自动拆分并为新子堆重分配 UID，整堆搬运则保留原 UID）。[br]
## 成功返回 [code]Result.ok(InventoryDiff)[/code]（净增减为空，脏集记录两侧容器受影响项）；失败时两侧容器零改动。
static func transfer_any(
	src: BaseItemContainer,
	dst: BaseItemContainer,
	uid: int,
	count: int = -1
) -> Result:
	if src == null or dst == null:
		return Result.err_code(InventoryError.INVALID_PARAM, "Source or destination container is null.")
	if uid <= 0 or count == 0 or count < -1:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid uid or count.")
	if src == dst:
		return Result.ok(InventoryDiff.new(src.container_id))

	var src_item: ItemStack = src.get_item_by_uid(uid)
	if src_item == null:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Item uid %d not found in source." % uid)

	var actual_count: int = src_item.count if count == -1 else count
	if actual_count > src_item.count:
		return Result.err_code(
			InventoryError.INSUFFICIENT_ITEM,
			"Item uid %d has %d, cannot transfer %d." % [uid, src_item.count, actual_count]
		)

	var moving_stack: ItemStack = src_item.clone_stack()
	moving_stack.count = actual_count
	# 部分拆出转移时置零 uid，交由目标容器生成独立新号，防止源容器剩余部分与目标容器撞号
	if actual_count < src_item.count:
		moving_stack.uid = 0

	var tx := InventoryTransaction.new()
	tx._is_transfer_only = true
	tx.take_by_uid(src, uid, actual_count)
	tx.give(dst, moving_stack)
	return tx.commit()


## 一维槽位容器间定点拖拽松手交互原语（覆盖「穿脱装备、背包与仓库互拖、快捷栏装配、一键替换旧装备」）：[br]
## [param src] 源槽位容器。[br]
## [param src_index] 源槽位下标。[br]
## [param dst] 目标槽位容器（允许与 [param src] 为同一实例，自动退化为单容器拆合换）。[br]
## [param dst_index] 目标槽位下标。[br]
## [param count] 转移数量（默认 [code]-1[/code] 转移整格；传部分数量时支持拆堆放入空槽或合入同类槽）。[br]
## [b]三分支裁决规则：[/b][br]
## 1. 目标槽为空：定量转入（整格保留原 UID，半格自动拆堆分配新 UID）；[br]
## 2. 目标槽同类未满：尽可能合入目标槽至 [member ItemSpec.max_stack]，溢出余量留回源槽；[br]
## 3. 目标槽已满或为异类物品：要求整格转移且双方物品均通过对方容器的 [ContainerRule]，原子互换两格物品，否则返回 [constant InventoryError.SWAP_REJECTED]。
static func transfer_slot(
	src: SlotItemContainer,
	src_index: int,
	dst: SlotItemContainer,
	dst_index: int,
	count: int = -1
) -> Result:
	if src == null or dst == null:
		return Result.err_code(InventoryError.INVALID_PARAM, "Source or destination container is null.")
	if not src.is_valid_slot(src_index) or not dst.is_valid_slot(dst_index):
		return Result.err_code(InventoryError.OUT_OF_BOUNDS, "Source or destination slot out of bounds.")

	# 同容器内部交互直接委托给单容器原语
	if src == dst:
		if count == -1:
			return src.move_or_merge(src_index, dst_index)
		var same_src: ItemStack = src.get_slot(src_index)
		if same_src == null:
			return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Source slot is empty.")
		if count == same_src.count:
			return src.move_or_merge(src_index, dst_index)
		return src.split_at(src_index, count, dst_index)

	var src_stack: ItemStack = src.get_slot(src_index)
	if src_stack == null:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "Source slot %d is empty." % src_index)

	var actual_count: int = src_stack.count if count == -1 else count
	if actual_count <= 0 or actual_count > src_stack.count:
		return Result.err_code(InventoryError.INVALID_PARAM, "Invalid transfer count %d." % actual_count)

	var dst_stack: ItemStack = dst.get_slot(dst_index)

	# 分支 1：目标槽为空 -> 从源槽扣减并定点写入目标槽
	if dst_stack == null:
		var moving: ItemStack = src_stack.clone_stack()
		moving.count = actual_count
		if actual_count < src_stack.count:
			moving.uid = 0
		var tx_empty := InventoryTransaction.new()
		tx_empty._is_transfer_only = true
		tx_empty.take_at_slot(src, src_index, actual_count)
		tx_empty.give_at_slot(dst, dst_index, moving)
		return tx_empty.commit()

	# 分支 2：目标槽同类可合并且尚有堆叠空间 -> 定量补充合并
	var dst_spec: ItemSpec = dst.resolve_spec(src_stack.item_id)
	var max_stack: int = dst_spec.max_stack if dst_spec != null else 1
	var dst_merge_pred: Callable = dst.rule.custom_merge_predicate if dst.rule != null else Callable()
	if dst_stack.can_merge_with(src_stack, max_stack, dst_merge_pred) and dst_stack.count < max_stack:
		var merge_amount: int = mini(actual_count, max_stack - dst_stack.count)
		var merge_slice: ItemStack = src_stack.clone_stack()
		merge_slice.count = merge_amount
		merge_slice.uid = 0
		var tx_merge := InventoryTransaction.new()
		tx_merge._is_transfer_only = true
		tx_merge.take_at_slot(src, src_index, merge_amount)
		tx_merge.give_at_slot(dst, dst_index, merge_slice)
		return tx_merge.commit()

	# 分支 3：目标槽已满或为不同物品 -> 仅当整堆移动时执行双向准入互换（如一键替换武器）
	if actual_count < src_stack.count:
		return Result.err_code(
			InventoryError.SWAP_REJECTED,
			"Cannot swap partial stack (%d / %d) onto an occupied incompatible slot." % [
				actual_count, src_stack.count
			]
		)

	var tx_swap := InventoryTransaction.new()
	tx_swap._is_transfer_only = true
	tx_swap.take_at_slot(src, src_index, -1)
	tx_swap.take_at_slot(dst, dst_index, -1)
	tx_swap.give_at_slot(dst, dst_index, src_stack)
	tx_swap.give_at_slot(src, src_index, dst_stack)
	var res_swap: Result = tx_swap.commit()
	if res_swap.is_err():
		return Result.err_code(
			InventoryError.SWAP_REJECTED,
			"Cross-container swap rejected (%s): %s" % [res_swap.error_code(), res_swap.error_message()]
		)
	return res_swap

#endregion


#region Fluent Batch Transaction Builder

## 链式追加一步「从容器 [param container] 按配置 [param item_id] 扣减 [param count] 个物品」指令。
func take_by_id(container: BaseItemContainer, item_id: StringName, count: int = 1) -> InventoryTransaction:
	_steps.append({
		"op": _OpKind.TAKE_BY_ID,
		"container": container,
		"item_id": item_id,
		"count": count,
	})
	return self


## 链式追加一步「从容器 [param container] 按唯一实例 [param uid] 扣减 [param count] 个物品（[code]-1[/code] 为整堆）」指令。
func take_by_uid(container: BaseItemContainer, uid: int, count: int = -1) -> InventoryTransaction:
	_steps.append({
		"op": _OpKind.TAKE_BY_UID,
		"container": container,
		"uid": uid,
		"count": count,
	})
	return self


## 链式追加一步「从一维槽位容器 [param container] 的 [param slot_index] 槽扣减 [param count] 个物品（[code]-1[/code] 为整格）」指令。
func take_at_slot(container: SlotItemContainer, slot_index: int, count: int = -1) -> InventoryTransaction:
	_steps.append({
		"op": _OpKind.TAKE_AT_SLOT,
		"container": container,
		"slot_index": slot_index,
		"count": count,
	})
	return self


## 链式追加一步「向容器 [param container] 自动寻位发放整堆 [param stack]」指令（内部保存克隆副本防外部篡改）。
func give(container: BaseItemContainer, stack: ItemStack) -> InventoryTransaction:
	_steps.append({
		"op": _OpKind.GIVE_AUTO,
		"container": container,
		"stack": stack.clone_stack() if stack != null else null,
	})
	return self


## 链式追加一步「向一维槽位容器 [param container] 的 [param slot_index] 槽定点放入 [param stack]」指令。
func give_at_slot(container: SlotItemContainer, slot_index: int, stack: ItemStack) -> InventoryTransaction:
	_steps.append({
		"op": _OpKind.GIVE_AT_SLOT,
		"container": container,
		"slot_index": slot_index,
		"stack": stack.clone_stack() if stack != null else null,
	})
	return self


## 链式追加一步「向二维网格容器 [param container] 的坐标 [param pos] 与朝向 [param is_rotated] 定点放入 [param stack]」指令。
func give_at_grid(
	container: GridItemContainer,
	pos: Vector2i,
	stack: ItemStack,
	is_rotated: bool = false
) -> InventoryTransaction:
	_steps.append({
		"op": _OpKind.GIVE_AT_GRID,
		"container": container,
		"pos": pos,
		"rotated": is_rotated,
		"stack": stack.clone_stack() if stack != null else null,
	})
	return self


## 清空当前事务器内已编排的全部待执行步骤并重置搬运标记，便于复用实例。
func reset() -> void:
	_steps.clear()
	_is_transfer_only = false


## 100% 零副作用预演校验当前事务队列能否成功提交（适合驱动 UI 合成按钮置灰/亮起状态）：[br]
## 内部在静默快照与 UID 水位保护下真实跑完整个步骤链，随后无条件还原全部容器快照与全局 UID 序号。[br]
## 可行返回 [code]Result.ok(true)[/code]；不可行返回首个失败步骤对应的 [Result] 错误原因。
func can_commit() -> Result:
	return _run_internal(true)


## 原子提交当前已编排的全部步骤：[br]
## - 全部步骤成功：弹出信号锁，对每个发生实质变化的参与容器发射 1 次合并后的 [signal BaseItemContainer.changed]，并返回 [code]Result.ok(InventoryDiff)[/code]；[br]
## - 任意步骤失败：立即将全部参与容器恢复至前置快照并回退全局 UID 水位线，返回该失败步骤的 [Result]。
func commit() -> Result:
	return _run_internal(false)

#endregion


#region Internal Snapshot Execution & Rollback Engine

## 事务核心执行管线：[param dry_run_only] 为 [code]true[/code] 时无论成败均回滚还原，仅验证可行性。
func _run_internal(dry_run_only: bool) -> Result:
	if _steps.is_empty():
		return Result.ok(InventoryDiff.new(&"transaction"))

	# 阶段 1：提取去重后的参与容器集合，拦截空容器引用
	var participants: Array[BaseItemContainer] = []
	for step: Dictionary in _steps:
		var raw_c: Variant = step.get("container", null)
		if not (raw_c is BaseItemContainer):
			return Result.err_code(InventoryError.INVALID_PARAM, "Transaction step references a null container.")
		var c: BaseItemContainer = raw_c as BaseItemContainer
		if not participants.has(c):
			participants.append(c)

	# 阶段 2：记录前置容器快照与全局 UID 水位线，并压入信号静默锁抑制中间态广播
	var saved_uid_floor: int = BaseItemContainer.get_uid_floor()
	var snapshots: Array[Dictionary] = []
	var instance_diffs: Dictionary = {}
	for c: BaseItemContainer in participants:
		snapshots.append(c.capture_snapshot())
		instance_diffs[c.get_instance_id()] = InventoryDiff.new(c.container_id)
		c.push_signal_suppression()

	# 阶段 3：严格按编排顺序逐步推演，遇到首个错误立即短路中断
	var summary_diff := InventoryDiff.new(&"transaction")
	var failed_res: Result = null

	for step: Dictionary in _steps:
		var step_container: BaseItemContainer = step["container"] as BaseItemContainer
		var step_res: Result = _execute_single_step(step)
		if step_res.is_err():
			failed_res = step_res
			break
		var step_diff: InventoryDiff = step_res.value as InventoryDiff
		if step_diff != null:
			summary_diff.merge_from(step_diff)
			var inst_diff: InventoryDiff = instance_diffs[step_container.get_instance_id()] as InventoryDiff
			inst_diff.merge_from(step_diff)

	# 阶段 4：发生错误或处于预演模式 -> 全量回滚容器快照与 UID 水位线，确保 0 脏状态残留
	if failed_res != null or dry_run_only:
		for i: int in participants.size():
			var c_restore: BaseItemContainer = participants[i]
			c_restore.restore_snapshot(snapshots[i])
			c_restore.pop_signal_suppression()
		BaseItemContainer.restore_uid_floor(saved_uid_floor)
		if failed_res != null:
			return failed_res
		return Result.ok(true)

	# 阶段 5：正式提交成功 -> 纯搬运事务清零经济净增减，随后按容器实例逐一发射单次合并变更信号
	if _is_transfer_only:
		_clear_transfer_net_totals(summary_diff)
	for c_commit: BaseItemContainer in participants:
		c_commit.pop_signal_suppression()
		var inst_sub: InventoryDiff = instance_diffs.get(c_commit.get_instance_id(), null) as InventoryDiff
		if inst_sub != null:
			if _is_transfer_only:
				_clear_transfer_net_totals(inst_sub)
			if not inst_sub.is_empty():
				c_commit.notify_changed(inst_sub)

	return Result.ok(summary_diff)


## 分派执行单条原子指令字典。
func _execute_single_step(step: Dictionary) -> Result:
	var op: int = int(step.get("op", -1))
	match op:
		_OpKind.TAKE_BY_ID:
			var c_id: BaseItemContainer = step["container"] as BaseItemContainer
			var item_id: StringName = step["item_id"] as StringName
			var count_id: int = int(step["count"])
			return c_id.remove_by_id(item_id, count_id)

		_OpKind.TAKE_BY_UID:
			var c_uid: BaseItemContainer = step["container"] as BaseItemContainer
			var uid: int = int(step["uid"])
			var count_uid: int = int(step["count"])
			return c_uid.remove_by_uid(uid, count_uid)

		_OpKind.TAKE_AT_SLOT:
			var c_slot_rm: SlotItemContainer = step["container"] as SlotItemContainer
			var rm_idx: int = int(step["slot_index"])
			var rm_cnt: int = int(step["count"])
			return c_slot_rm.remove_at(rm_idx, rm_cnt)

		_OpKind.GIVE_AUTO:
			var c_give: BaseItemContainer = step["container"] as BaseItemContainer
			var st_give: ItemStack = step.get("stack", null) as ItemStack
			return c_give.add(st_give)

		_OpKind.GIVE_AT_SLOT:
			var c_slot_add: SlotItemContainer = step["container"] as SlotItemContainer
			var add_idx: int = int(step["slot_index"])
			var st_slot: ItemStack = step.get("stack", null) as ItemStack
			return c_slot_add.add_at(add_idx, st_slot)

		_OpKind.GIVE_AT_GRID:
			var c_grid_add: GridItemContainer = step["container"] as GridItemContainer
			var pos: Vector2i = step["pos"] as Vector2i
			var rot: bool = bool(step["rotated"])
			var st_grid: ItemStack = step.get("stack", null) as ItemStack
			return c_grid_add.place_at(st_grid, pos, rot)

	return Result.err_code(InventoryError.INVALID_PARAM, "Unknown transaction operation %d." % op)


## 清空搬运型事务的净新增与净移除统计，同时完整保留受影响的槽位、UID 与物品 ID 脏集。
static func _clear_transfer_net_totals(diff: InventoryDiff) -> void:
	if diff == null:
		return
	diff.added_totals.clear()
	diff.removed_totals.clear()
	for child: InventoryDiff in diff.sub_diffs:
		child.added_totals.clear()
		child.removed_totals.clear()

#endregion
