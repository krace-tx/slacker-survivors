class_name InventoryDiff
extends RefCounted

## 容器与跨容器事务产生的结构化增量变更单（Structured Inventory Delta & Dirty Set）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/types/[/code][br]
## [b]核心设计（严格分离「经济净增减」与「视图局部脏集」）：[/b][br]
## 1. [b]经济净增减统计[/b]（[member added_totals] / [member removed_totals]）：
##    仅在真正产出或销毁物品时记录数量变化，供上层触发「获得新道具飘字」「任务收集进度」或「埋点审计」；
##    容器内部的槽位整理、拆堆、换位以及跨容器穿脱装备均保证净增减为空，绝不触发虚假的获得提示；[br]
## 2. [b]UI 局部重绘脏集[/b]（[member changed_slots] / [member changed_uids] / [member changed_item_ids]）：
##    精确记录本次受波及的槽位下标、实例 UID 与物品 ID，驱动 UI 执行 O(dirty) 局部格子刷新而非全量重建节点；[br]
## 3. [b]跨容器事务分层归档[/b]（[member sub_diffs]）：
##    多容器事务提交后，可通过 [method get_container_diff] 提取指定容器专属的局部变更单。


#region Diff Properties

## 本变更单归属的容器标识（跨容器事务顶层汇总单固定为 [code]&"transaction"[/code]）。
var container_id: StringName = &""

## 本次操作净新增物品总量统计（映射关系：[code]StringName (item_id) -> int (count)[/code]）。
var added_totals: Dictionary = {}

## 本次操作净移除/消耗物品总量统计（映射关系：[code]StringName (item_id) -> int (count)[/code]）。
var removed_totals: Dictionary = {}

## 受波及的一维槽位索引去重列表（专供 [SlotItemContainer] 局部刷新对应格子 UI）。
var changed_slots: PackedInt32Array = PackedInt32Array()

## 受波及的独立物品实例 UID 去重列表（专供 [GridItemContainer] 与 [MapItemContainer] 局部刷新实例卡片）。
var changed_uids: Array[int] = []

## 受波及的物品静态 ID 去重列表（专供货币栏或字典型材料行按 [code]item_id[/code] 定向刷新）。
var changed_item_ids: Array[StringName] = []

## 跨容器事务汇总单下辖的各参与容器子变更单列表。
var sub_diffs: Array[InventoryDiff] = []

#endregion


#region Lifecycle

## 构造指定归属容器标识 [param p_container_id] 的空白变更单。
func _init(p_container_id: StringName = &"") -> void:
	container_id = p_container_id

#endregion


#region Recording API

## 累加记录指定 [param item_id] 的净新增数量 [param amount]，并同步将其加入 [member changed_item_ids]。
func record_added(item_id: StringName, amount: int) -> void:
	if item_id.is_empty() or amount <= 0:
		return
	var prev: int = int(added_totals.get(item_id, 0))
	added_totals[item_id] = prev + amount
	mark_item_id(item_id)


## 累加记录指定 [param item_id] 的净移除数量 [param amount]，并同步将其加入 [member changed_item_ids]。
func record_removed(item_id: StringName, amount: int) -> void:
	if item_id.is_empty() or amount <= 0:
		return
	var prev: int = int(removed_totals.get(item_id, 0))
	removed_totals[item_id] = prev + amount
	mark_item_id(item_id)


## 将一维槽位下标 [param slot_index] 标记为脏槽位（自动忽略负数并去重）。
func mark_slot(slot_index: int) -> void:
	if slot_index < 0:
		return
	if not changed_slots.has(slot_index):
		changed_slots.append(slot_index)


## 将物品实例 [param uid] 标记为脏实例（自动忽略 [code]<= 0[/code] 并去重）。
func mark_uid(uid: int) -> void:
	if uid <= 0:
		return
	if not changed_uids.has(uid):
		changed_uids.append(uid)


## 将物品配置标识 [param item_id] 标记为脏条目（自动忽略空名称并去重）。
func mark_item_id(item_id: StringName) -> void:
	if item_id.is_empty():
		return
	if not changed_item_ids.has(item_id):
		changed_item_ids.append(item_id)


## 将另一份变更单 [param other] 归并入当前变更单：[br]
## - 若二者 [member container_id] 相同：直接原地合并全部脏集列表；[br]
## - 若当前为跨容器汇总单：累加顶层净增减与 [member changed_item_ids]，并将子单按容器归档至 [member sub_diffs]。
func merge_from(other: InventoryDiff) -> void:
	if other == null or other.is_empty():
		return

	for raw_id: Variant in other.added_totals:
		var item_id: StringName = StringName(str(raw_id))
		record_added(item_id, int(other.added_totals[raw_id]))

	for raw_id: Variant in other.removed_totals:
		var item_id: StringName = StringName(str(raw_id))
		record_removed(item_id, int(other.removed_totals[raw_id]))

	if container_id == other.container_id:
		for slot_idx: int in other.changed_slots:
			mark_slot(slot_idx)
		for uid: int in other.changed_uids:
			mark_uid(uid)
		for cid: StringName in other.changed_item_ids:
			mark_item_id(cid)
		return

	for cid_top: StringName in other.changed_item_ids:
		mark_item_id(cid_top)

	if not other.sub_diffs.is_empty():
		for child: InventoryDiff in other.sub_diffs:
			_merge_sub_diff(child)
	else:
		_merge_sub_diff(other)

#endregion


#region Query API

## 判断本次操作是否未产生任何实质性状态变化（所有统计表与脏集均为空）。
func is_empty() -> bool:
	return (
		added_totals.is_empty()
		and removed_totals.is_empty()
		and changed_slots.is_empty()
		and changed_uids.is_empty()
		and changed_item_ids.is_empty()
		and sub_diffs.is_empty()
	)


## 按容器标识 [param target_container_id] 查找对应的子变更单（若自身即匹配则直接返回 [code]self[/code]，未命中返回 [code]null[/code]）。
func get_container_diff(target_container_id: StringName) -> InventoryDiff:
	if container_id == target_container_id:
		return self
	for child: InventoryDiff in sub_diffs:
		if child.container_id == target_container_id:
			return child
	return null

#endregion


#region Internal Helpers

## 将单容器变更单 [param incoming] 按 [member container_id] 合并入 [member sub_diffs] 列表。
func _merge_sub_diff(incoming: InventoryDiff) -> void:
	for existing: InventoryDiff in sub_diffs:
		if existing.container_id == incoming.container_id:
			for slot_idx: int in incoming.changed_slots:
				existing.mark_slot(slot_idx)
			for uid: int in incoming.changed_uids:
				existing.mark_uid(uid)
			for cid: StringName in incoming.changed_item_ids:
				existing.mark_item_id(cid)
			for raw_id: Variant in incoming.added_totals:
				existing.record_added(StringName(str(raw_id)), int(incoming.added_totals[raw_id]))
			for raw_id: Variant in incoming.removed_totals:
				existing.record_removed(StringName(str(raw_id)), int(incoming.removed_totals[raw_id]))
			return

	var copy := InventoryDiff.new(incoming.container_id)
	copy.added_totals = incoming.added_totals.duplicate()
	copy.removed_totals = incoming.removed_totals.duplicate()
	copy.changed_slots = incoming.changed_slots.duplicate()
	copy.changed_uids = incoming.changed_uids.duplicate()
	copy.changed_item_ids = incoming.changed_item_ids.duplicate()
	sub_diffs.append(copy)

#endregion
