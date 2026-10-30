class_name InventoryDemoState
extends RefCounted

## 背包交互测试演练场的轻量 UI 选中态模型（`src/test/inventory/model/`）。[br]
##
## [b]设计职责：[/b]仅记录当前玩家聚焦选中的容器标识、槽位下标、实例 UID 以及内核契约自检通过数。


#region State Fields

## 当前选中物品所在的容器 ID（未选中时为空 [StringName]）。
var selected_container_id: StringName = &""

## 当前选中的一维槽位下标（二维网格或未选中时为 [code]-1[/code]）。
var selected_slot_index: int = -1

## 当前选中的唯一实例 UID（未选中时为 [code]0[/code]）。
var selected_uid: int = 0

## 内核契约自检通过用例数。
var passed_cases: int = 0

## 内核契约自检总用例数。
var total_cases: int = 10

## 锻造批次计数（用于为每次新锻造的符文长剑生成微幅递增攻击词条）。
var craft_serial: int = 0

## 补给轮换游标。
var supply_cursor: int = 0

#endregion


#region Helpers

## 记录新的选中目标。
func set_selection(container_id: StringName, slot_index: int, uid: int) -> void:
	selected_container_id = container_id
	selected_slot_index = slot_index
	selected_uid = uid


## 清空当前选中焦点。
func clear_selection() -> void:
	selected_container_id = &""
	selected_slot_index = -1
	selected_uid = 0


## 判断当前是否存在有效选中项。
func has_selection() -> bool:
	return not selected_container_id.is_empty() and selected_uid > 0

#endregion
