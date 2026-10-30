class_name InventoryDemoService
extends RefCounted

## 背包交互测试演练场业务编排与契约自检服务（`src/test/inventory/service/`）。[br]
##
## [b]设计职责：[/b][br]
## 1. 组合实例化 [MapItemContainer]（钱包）、带 [ContainerRule] 的 [SlotItemContainer]（三栏装备）、
##    16 格通用 [SlotItemContainer]（背包）与 `6×5` [GridItemContainer]（战术箱）；[br]
## 2. 通过 [InventoryTransaction] 统一驱动跨容器拖拽互换、右键穿脱与「满包消耗腾位锻造」；[br]
## 3. 内置 10 项无副作用底层契约自检套件，兼顾可视化演练与 `--inventory-test-auto-quit` 自动化门禁。


#region Constants & Containers

const LOG_TAG: String = "InventoryTest"
const BAG_CAPACITY: int = 16
const GRID_WIDTH: int = 6
const GRID_HEIGHT: int = 5
const CRAFT_GOLD_COST: int = 300
const CRAFT_ORE_COST: int = 5

## 物品视觉与规格图鉴表（`StringName -> InventoryItemVisualConfig`）。
var catalog: Dictionary = {}

## 注入给全部容器的静态规格反查闭包。
var spec_resolver: Callable = Callable()

## 演练场轻量选中态。
var state: InventoryDemoState = InventoryDemoState.new()

## 货币钱包（O(1) 字典聚合容器）。
var wallet: MapItemContainer = null

## 主手武器栏（单槽 + `&"weapon"` 准入规则）。
var equip_weapon: SlotItemContainer = null

## 副手盾牌栏（单槽 + `&"shield"` 准入规则）。
var equip_shield: SlotItemContainer = null

## 饰品指环栏（单槽 + `&"ring"` 准入规则）。
var equip_ring: SlotItemContainer = null

## 16 格角色主背包（一维定长槽位容器）。
var bag: SlotItemContainer = null

## `6×5` 二维空间战术物资箱（二维矩阵占地容器）。
var grid: GridItemContainer = null

var _containers_by_id: Dictionary = {}

#endregion


#region Lifecycle & Initialization

## 构造演练场服务并初始化全部容器拓扑。
func _init() -> void:
	catalog = InventoryItemVisualConfig.build_catalog()
	var spec_map: Dictionary = InventoryItemVisualConfig.extract_spec_map(catalog)
	spec_resolver = ItemSpec.resolver_from_dict(spec_map)

	wallet = MapItemContainer.new(&"wallet", 0, spec_resolver, null, true)
	equip_weapon = SlotItemContainer.new(
		&"equip_weapon",
		1,
		spec_resolver,
		ContainerRule.new().with_all_tags([&"equip", &"weapon"]),
		true
	)
	equip_shield = SlotItemContainer.new(
		&"equip_shield",
		1,
		spec_resolver,
		ContainerRule.new().with_all_tags([&"equip", &"shield"]),
		true
	)
	equip_ring = SlotItemContainer.new(
		&"equip_ring",
		1,
		spec_resolver,
		ContainerRule.new().with_all_tags([&"equip", &"ring"]),
		true
	)
	bag = SlotItemContainer.new(&"bag", BAG_CAPACITY, spec_resolver, null, true)
	grid = GridItemContainer.new(&"grid", GRID_WIDTH, GRID_HEIGHT, spec_resolver, null, true)

	_containers_by_id = {
		&"wallet": wallet,
		&"equip_weapon": equip_weapon,
		&"equip_shield": equip_shield,
		&"equip_ring": equip_ring,
		&"bag": bag,
		&"grid": grid,
	}


## 重置全部容器并装填初始演示物品布局。
func reset_demo() -> void:
	for raw_key: Variant in _containers_by_id:
		var c: BaseItemContainer = _containers_by_id.get(raw_key, null) as BaseItemContainer
		if c != null:
			c.push_signal_suppression()
			c.clear()

	wallet.add(ItemStack.create(&"gold", 1200))
	wallet.add(ItemStack.create(&"gem", 15))

	equip_weapon.add_at(0, ItemStack.create(&"sword_iron", 1, {"atk": 18}))
	equip_ring.add_at(0, ItemStack.create(&"ring_ruby", 1, {"crit": 8}))

	bag.add_at(0, ItemStack.create(&"axe_battle", 1, {"atk": 34}))
	bag.add_at(1, ItemStack.create(&"shield_kite", 1, {"def": 24}))
	bag.add_at(2, ItemStack.create(&"potion_hp", 6))
	bag.add_at(4, ItemStack.create(&"potion_hp", 4))
	bag.add_at(5, ItemStack.create(&"ore_iron", 8))
	bag.add_at(7, ItemStack.create(&"totem_fixed", 1))
	bag.add_at(9, ItemStack.create(&"potion_hp", 2, {"bound": true}))

	grid.place_at(ItemStack.create(&"sword_rune", 1, {"atk": 45}), Vector2i(0, 0), false)
	grid.place_at(ItemStack.create(&"ring_ruby", 1, {"crit": 12}), Vector2i(1, 1), false)
	grid.place_at(ItemStack.create(&"axe_battle", 1, {"atk": 30}), Vector2i(3, 0), true)
	grid.place_at(ItemStack.create(&"totem_fixed", 1), Vector2i(4, 3), false)

	state.craft_serial = 0
	state.supply_cursor = 0

	var first_bag_item: ItemStack = bag.get_slot(0)
	if first_bag_item != null:
		state.set_selection(&"bag", 0, first_bag_item.uid)
	else:
		state.clear_selection()

	for raw_key: Variant in _containers_by_id:
		var c_out: BaseItemContainer = _containers_by_id.get(raw_key, null) as BaseItemContainer
		if c_out != null:
			c_out.pop_signal_suppression()

#endregion


#region Queries

## 获取全部参与演练的容器列表（用于 Presenter 统一绑定 `changed` 信号）。
func get_all_containers() -> Array[BaseItemContainer]:
	return [wallet, equip_weapon, equip_shield, equip_ring, bag, grid]


## 按业务标识检索对应容器实例。
func get_container(container_id: StringName) -> BaseItemContainer:
	return _containers_by_id.get(container_id, null) as BaseItemContainer


## 查询物品视觉配置描述符。
func get_visual_config(item_id: StringName) -> InventoryItemVisualConfig:
	return catalog.get(item_id, null) as InventoryItemVisualConfig


## 解析物品底层拓扑规格。
func get_spec(item_id: StringName) -> ItemSpec:
	var cfg: InventoryItemVisualConfig = get_visual_config(item_id)
	return cfg.spec if cfg != null else null


## 同步并校准当前选中焦点（若选中物品被搬运至新容器或新槽位，自动追踪其 UID；若已消耗则清空焦点）。
func sync_and_get_selected_stack() -> ItemStack:
	if state.selected_uid <= 0:
		state.clear_selection()
		return null

	var search_order: Array[StringName] = [
		state.selected_container_id,
		&"bag",
		&"grid",
		&"equip_weapon",
		&"equip_shield",
		&"equip_ring",
	]
	for cid: StringName in search_order:
		if cid.is_empty():
			continue
		var c: BaseItemContainer = get_container(cid)
		if c == null:
			continue
		var found: ItemStack = c.get_item_by_uid(state.selected_uid)
		if found != null:
			var slot_idx: int = -1
			if c is SlotItemContainer:
				slot_idx = (c as SlotItemContainer).find_slot_by_uid(found.uid)
			state.set_selection(cid, slot_idx, found.uid)
			return found

	state.clear_selection()
	return null


## 零副作用预演当前资源与背包空位是否满足锻造条件。
func can_craft_rune_sword() -> bool:
	var tx: InventoryTransaction = _build_craft_transaction(0)
	return tx.can_commit().is_ok()


## 判断当前选中项是否支持在背包内执行一键拆半。
func can_split_selected() -> bool:
	var st: ItemStack = sync_and_get_selected_stack()
	if st == null or state.selected_container_id != &"bag":
		return false
	return st.count >= 2 and bag.get_empty_slot_count() > 0


## 判断当前选中项是否位于二维网格内且支持旋转操作。
func can_rotate_selected() -> bool:
	var st: ItemStack = sync_and_get_selected_stack()
	if st == null or state.selected_container_id != &"grid":
		return false
	var spec: ItemSpec = get_spec(st.item_id)
	return spec != null and spec.rotatable

#endregion


#region Interactive Mutations

## 发放一批补给物资（货币入钱包，道具优先入背包、满格时自动转入战术箱）。
func grant_supply() -> Result:
	var bundles: Array[ItemStack] = [
		ItemStack.create(&"ore_iron", 5),
		ItemStack.create(&"potion_hp", 4),
		ItemStack.create(&"ring_ruby", 1, {"crit": 10}),
		ItemStack.create(&"shield_kite", 1, {"def": 28}),
	]
	var pick: ItemStack = bundles[state.supply_cursor % bundles.size()]
	state.supply_cursor += 1

	var target_c: BaseItemContainer = bag if bag.can_add(pick).is_ok() else grid
	var tx := InventoryTransaction.new()
	tx.give(wallet, ItemStack.create(&"gold", 200))
	tx.give(wallet, ItemStack.create(&"gem", 5))
	tx.give(target_c, pick)
	return tx.commit()


## 原子锻造符文长剑（消耗 300 金币 + 5 寒铁矿 -> 产出 1 把词条符文长剑；天然支持满包腾位合成）。
func craft_rune_sword() -> Result:
	if not wallet.has_enough(&"gold", CRAFT_GOLD_COST):
		return Result.err_code(InventoryError.INSUFFICIENT_ITEM, "金币不足 300")
	if not bag.has_enough(&"ore_iron", CRAFT_ORE_COST):
		return Result.err_code(InventoryError.INSUFFICIENT_ITEM, "背包铁矿不足 5")

	var bonus_atk: int = 42 + (state.craft_serial % 4) * 3
	var tx: InventoryTransaction = _build_craft_transaction(bonus_atk)
	var res: Result = tx.commit()
	if res.is_ok():
		state.craft_serial += 1
		var diff: InventoryDiff = res.value as InventoryDiff
		if diff != null and not diff.changed_uids.is_empty():
			var last_uid: int = diff.changed_uids[diff.changed_uids.size() - 1]
			var new_slot: int = bag.find_slot_by_uid(last_uid)
			if new_slot >= 0:
				state.set_selection(&"bag", new_slot, last_uid)
	return res


## 一键整理主背包（合并半满碎片堆并按权重重排）。
func sort_bag() -> Result:
	return bag.sort()


## 将当前在主背包内选中的复数物品堆拆出一半至首个空闲槽位。
func split_selected() -> Result:
	var st: ItemStack = sync_and_get_selected_stack()
	if st == null or state.selected_container_id != &"bag":
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "请先选中背包可叠物品")
	if st.count < 2:
		return Result.err_code(InventoryError.INVALID_PARAM, "数量不足以拆分")
	var half: int = maxi(1, st.count / 2)
	return bag.split_at(state.selected_slot_index, half, -1)


## 旋转二维战术箱中的指定实例 [param uid]（传 `0` 时默认旋转当前选中项）。
func rotate_grid_item(uid: int = 0) -> Result:
	var target_uid: int = uid if uid > 0 else state.selected_uid
	if target_uid <= 0:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "未选中战术箱物品")
	return grid.rotate_item(target_uid)


## 校验拖拽载荷 [param drag_data] 是否允许落入目标槽位容器 [param dst_id] 的 [param dst_index] 槽。
func can_drop_on_slot(drag_data: Dictionary, dst_id: StringName, dst_index: int) -> bool:
	if not bool(drag_data.get("inv_drag", false)):
		return false
	var dst_c: SlotItemContainer = get_container(dst_id) as SlotItemContainer
	if dst_c == null or not dst_c.is_valid_slot(dst_index):
		return false

	var src_id: StringName = drag_data.get("src_id", &"") as StringName
	var src_c: BaseItemContainer = get_container(src_id)
	var uid: int = int(drag_data.get("uid", 0))
	if src_c == null or uid <= 0:
		return false

	var moving: ItemStack = src_c.get_item_by_uid(uid)
	if moving == null:
		return false
	var moving_spec: ItemSpec = dst_c.resolve_spec(moving.item_id)
	if moving_spec == null:
		return false
	if dst_c.rule != null and dst_c.rule.evaluate_accept(moving, moving_spec).is_err():
		return false

	# 若目标槽已有异类物品且源容器挂载了准入规则，校验互换回源容器的合法性
	var dst_existing: ItemStack = dst_c.get_slot(dst_index)
	if dst_existing != null and src_c != dst_c and src_c.rule != null:
		var dst_spec: ItemSpec = src_c.resolve_spec(dst_existing.item_id)
		if dst_spec == null or src_c.rule.evaluate_accept(dst_existing, dst_spec).is_err():
			return false
	return true


## 执行向一维槽位容器 [param dst_id] 下标 [param dst_index] 的拖拽落位（支持 `Slot <-> Slot` 与 `Grid -> Slot`）。
func drop_on_slot(drag_data: Dictionary, dst_id: StringName, dst_index: int) -> Result:
	var src_id: StringName = drag_data.get("src_id", &"") as StringName
	var src_slot: int = int(drag_data.get("slot_index", -1))
	var uid: int = int(drag_data.get("uid", 0))

	var src_c: BaseItemContainer = get_container(src_id)
	var dst_c: SlotItemContainer = get_container(dst_id) as SlotItemContainer
	if src_c == null or dst_c == null:
		return Result.err_code(InventoryError.INVALID_PARAM, "无效的目标栏位")

	# 路径 1：一维槽位 <-> 一维槽位（含同容器移动/合堆/互换，跨容器穿脱/替换）
	if src_c is SlotItemContainer:
		var res_slot: Result = InventoryTransaction.transfer_slot(
			src_c as SlotItemContainer,
			src_slot,
			dst_c,
			dst_index
		)
		if res_slot.is_ok():
			var landed: ItemStack = dst_c.get_slot(dst_index)
			if landed != null:
				state.set_selection(dst_id, dst_index, landed.uid)
		return res_slot

	# 路径 2：二维网格 -> 一维槽位（空槽落位、同类合堆或与原槽物品异构原子互换）
	if src_c is GridItemContainer:
		var grid_src: GridItemContainer = src_c as GridItemContainer
		var moving: ItemStack = grid_src.get_item_by_uid(uid)
		if moving == null:
			return Result.err_code(InventoryError.ITEM_NOT_FOUND, "源物品不存在")

		var dst_existing: ItemStack = dst_c.get_slot(dst_index)
		var dst_spec: ItemSpec = dst_c.resolve_spec(moving.item_id)
		var max_stack: int = dst_spec.max_stack if dst_spec != null else 1
		var tx := InventoryTransaction.new()

		if dst_existing == null:
			tx.take_by_uid(grid_src, uid, -1)
			tx.give_at_slot(dst_c, dst_index, moving)
		elif dst_existing.can_merge_with(moving, max_stack) and dst_existing.count < max_stack:
			var merge_cnt: int = mini(moving.count, max_stack - dst_existing.count)
			var slice: ItemStack = moving.clone_stack()
			slice.count = merge_cnt
			slice.uid = 0
			tx.take_by_uid(grid_src, uid, merge_cnt)
			tx.give_at_slot(dst_c, dst_index, slice)
		else:
			tx.take_by_uid(grid_src, uid, -1)
			tx.take_at_slot(dst_c, dst_index, -1)
			tx.give_at_slot(dst_c, dst_index, moving)
			tx.give(grid_src, dst_existing)

		var res_grid_to_slot: Result = tx.commit()
		if res_grid_to_slot.is_ok():
			var now_in_slot: ItemStack = dst_c.get_slot(dst_index)
			if now_in_slot != null:
				state.set_selection(dst_id, dst_index, now_in_slot.uid)
		return res_grid_to_slot

	return Result.err_code(InventoryError.INVALID_PARAM, "不支持的容器交互")


## 预判拖拽载荷 [param drag_data] 在二维战术箱坐标 [param target_pos] 与朝向 [param is_rotated] 是否可合法落位。
func can_drop_on_grid(drag_data: Dictionary, target_pos: Vector2i, is_rotated: bool) -> bool:
	if not bool(drag_data.get("inv_drag", false)):
		return false
	var item_id: StringName = drag_data.get("item_id", &"") as StringName
	var src_id: StringName = drag_data.get("src_id", &"") as StringName
	var uid: int = int(drag_data.get("uid", 0))
	var src_c: BaseItemContainer = get_container(src_id)
	if src_c == null or uid <= 0:
		return false

	var moving: ItemStack = src_c.get_item_by_uid(uid)
	var spec: ItemSpec = get_spec(item_id)
	if moving == null or spec == null:
		return false
	if is_rotated and not spec.rotatable:
		return false
	if grid.rule != null and grid.rule.evaluate_accept(moving, spec).is_err():
		return false

	var rect := Rect2i(target_pos, spec.get_effective_size(is_rotated))
	if not grid.is_rect_in_bounds(rect):
		return false

	var ignore_uid: int = uid if src_id == &"grid" else 0
	var blockers: Array[int] = grid.get_occupying_uids(rect, ignore_uid)
	if blockers.is_empty():
		return true
	if blockers.size() == 1:
		var dst_st: ItemStack = grid.get_item_by_uid(blockers[0])
		if dst_st != null and dst_st.can_merge_with(moving, spec.max_stack) and dst_st.count < spec.max_stack:
			return src_id == &"grid" or dst_st.count + moving.count <= spec.max_stack
	return false


## 执行向二维战术箱坐标 [param target_pos] 与朝向 [param is_rotated] 的拖拽落位。
func drop_on_grid(drag_data: Dictionary, target_pos: Vector2i, is_rotated: bool) -> Result:
	var src_id: StringName = drag_data.get("src_id", &"") as StringName
	var src_slot: int = int(drag_data.get("slot_index", -1))
	var uid: int = int(drag_data.get("uid", 0))

	if src_id == &"grid":
		var move_res: Result = grid.move_item(uid, target_pos, is_rotated)
		if move_res.is_ok() and grid.get_item_by_uid(uid) != null:
			state.set_selection(&"grid", -1, uid)
		return move_res

	var src_slot_c: SlotItemContainer = get_container(src_id) as SlotItemContainer
	if src_slot_c == null:
		return Result.err_code(InventoryError.INVALID_PARAM, "无效的源栏位")
	var moving: ItemStack = src_slot_c.get_slot(src_slot)
	if moving == null:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "源槽位为空")

	var tx := InventoryTransaction.new()
	tx.take_at_slot(src_slot_c, src_slot, -1)
	tx.give_at_grid(grid, target_pos, moving, is_rotated)
	var res: Result = tx.commit()
	if res.is_ok():
		var landed_uid: int = grid.get_cell_uid(target_pos.x, target_pos.y)
		if landed_uid > 0:
			state.set_selection(&"grid", -1, landed_uid)
	return res


## 右键快捷交互：背包内装备一键穿戴替换、非装备一键移入战术箱；装备栏或战术箱物品一键收回背包。
func quick_transfer(src_id: StringName, slot_index: int, uid: int) -> Result:
	var src_c: BaseItemContainer = get_container(src_id)
	if src_c == null or uid <= 0:
		return Result.err_code(InventoryError.INVALID_PARAM, "无效目标")
	var st: ItemStack = src_c.get_item_by_uid(uid)
	if st == null:
		return Result.err_code(InventoryError.ITEM_NOT_FOUND, "物品不存在")

	var spec: ItemSpec = get_spec(st.item_id)
	var res: Result = null

	if src_id == &"bag" and spec != null:
		if spec.has_tag(&"weapon"):
			res = InventoryTransaction.transfer_slot(bag, slot_index, equip_weapon, 0)
		elif spec.has_tag(&"shield"):
			res = InventoryTransaction.transfer_slot(bag, slot_index, equip_shield, 0)
		elif spec.has_tag(&"ring"):
			res = InventoryTransaction.transfer_slot(bag, slot_index, equip_ring, 0)
		else:
			res = InventoryTransaction.transfer_any(bag, grid, uid, -1)
	else:
		res = InventoryTransaction.transfer_any(src_c, bag, uid, -1)

	if res != null and res.is_ok():
		state.selected_uid = uid
		sync_and_get_selected_stack()
	return res


## 将底层 [InventoryError] 转换为极简中文提示短语（2~6 字，绝不堆砌冗长报错）。
static func format_error_brief(res: Result) -> String:
	if res == null or res.is_ok():
		return ""
	match res.error_code():
		InventoryError.RULE_REJECTED, InventoryError.SWAP_REJECTED:
			return "栏位类型不符"
		InventoryError.CAPACITY_FULL:
			return "空间已满"
		InventoryError.INSUFFICIENT_ITEM:
			return res.error_message() if not res.error_message().is_empty() else "材料不足"
		InventoryError.ROTATION_FORBIDDEN:
			return "不可旋转"
		InventoryError.COLLISION:
			return "位置重叠"
		InventoryError.OUT_OF_BOUNDS:
			return "超出边界"
		_:
			return "无法执行"

#endregion


#region Automated 10-Case Kernel Self-Check

## 在隔离沙盒实例上运行 10 项底层容器契约自动化验证，返回通过用例数。
func run_kernel_self_check() -> int:
	var saved_floor: int = BaseItemContainer.get_uid_floor()
	var cases: Array[Callable] = [
		_case_01_spec_and_stack,
		_case_02_container_rules,
		_case_03_map_container,
		_case_04_slot_container,
		_case_05_grid_packing_and_rotation,
		_case_06_grid_adjacency_scan,
		_case_07_cross_slot_equip_swap,
		_case_08_full_bag_crafting_paradox,
		_case_09_transaction_rollback_and_dry_run,
		_case_10_heterogeneous_transfer_and_snapshot,
	]

	var passed: int = 0
	for i: int in cases.size():
		var fn: Callable = cases[i]
		var res: Result = fn.call() as Result
		if res != null and res.is_ok():
			passed += 1
		else:
			var err_msg: String = res.error_message() if res != null else "Null Result"
			App.logger.error(LOG_TAG, "[Case %02d FAIL] %s" % [i + 1, err_msg])

	BaseItemContainer.restore_uid_floor(maxi(saved_floor, BaseItemContainer.get_uid_floor()))
	state.passed_cases = passed
	state.total_cases = cases.size()

	if passed == cases.size():
		App.logger.info(LOG_TAG, "Inventory kernel self-check PASSED (%d/%d)." % [passed, cases.size()])
	else:
		App.logger.error(LOG_TAG, "Inventory kernel self-check FAILED (%d/%d)." % [passed, cases.size()])
	return passed

#endregion


#region Internal Helpers & Sandbox Cases

func _build_craft_transaction(atk_value: int) -> InventoryTransaction:
	var tx := InventoryTransaction.new()
	tx.take_by_id(wallet, &"gold", CRAFT_GOLD_COST)
	tx.take_by_id(bag, &"ore_iron", CRAFT_ORE_COST)
	tx.give(bag, ItemStack.create(&"sword_rune", 1, {"atk": atk_value, "crafted": true}))
	return tx


func _case_01_spec_and_stack() -> Result:
	var a := ItemStack.create(&"potion_hp", 6)
	var b := ItemStack.create(&"potion_hp", 4)
	var bound := ItemStack.create(&"potion_hp", 2, {"bound": true})
	if not a.can_merge_with(b, 10) or a.can_merge_with(bound, 10):
		return Result.err_code("Test.Case01", "Merge isolation failed.")
	if a.split_off(6).is_ok():
		return Result.err_code("Test.Case01", "Full count split must fail.")
	var split_res: Result = a.split_off(2, 777)
	if split_res.is_err():
		return split_res
	var restored := ItemStack.new(bound.to_dict(true))
	if restored.item_id != &"potion_hp" or not bool(restored.meta.get("bound", false)):
		return Result.err_code("Test.Case01", "ItemStack round-trip failed.")
	return Result.ok(true)


func _case_02_container_rules() -> Result:
	var rule := ContainerRule.new() \
		.with_all_tags([&"equip"]) \
		.with_any_tags([&"weapon", &"ring"]) \
		.with_blocked_tags([&"quest"]) \
		.with_remove_allowed(false)
	if rule.evaluate_accept(ItemStack.create(&"sword_iron", 1), get_spec(&"sword_iron")).is_err():
		return Result.err_code("Test.Case02", "Sword rejected unexpectedly.")
	if rule.evaluate_accept(ItemStack.create(&"potion_hp", 1), get_spec(&"potion_hp")).is_ok():
		return Result.err_code("Test.Case02", "Potion accepted unexpectedly.")
	if rule.evaluate_accept(ItemStack.create(&"quest_letter", 1), get_spec(&"quest_letter")).is_ok():
		return Result.err_code("Test.Case02", "Blocked tag accepted unexpectedly.")
	if rule.evaluate_remove().is_ok():
		return Result.err_code("Test.Case02", "Locked removal succeeded unexpectedly.")
	return Result.ok(true)


func _case_03_map_container() -> Result:
	var c := MapItemContainer.new(&"test_map", 2, spec_resolver)
	c.add(ItemStack.create(&"gold", 500))
	c.add(ItemStack.create(&"gold", 250))
	if c.get_total_count(&"gold") != 750 or c.get_unique_count() != 0:
		return Result.err_code("Test.Case03", "Fungible count mismatch.")
	c.add(ItemStack.create(&"sword_iron", 1, {"atk": 12}))
	c.add(ItemStack.create(&"sword_iron", 1, {"atk": 18}))
	if c.add(ItemStack.create(&"ring_ruby", 1)).is_ok():
		return Result.err_code("Test.Case03", "Unique capacity overflow not caught.")
	c.remove_by_id(&"gold", 300)
	if c.get_total_count(&"gold") != 450:
		return Result.err_code("Test.Case03", "Gold deduction mismatch.")
	return Result.ok(true)


func _case_04_slot_container() -> Result:
	var c := SlotItemContainer.new(&"test_slot", 4, spec_resolver)
	c.add(ItemStack.create(&"potion_hp", 15))
	c.split_at(1, 2, -1)
	c.add_at(3, ItemStack.create(&"sword_iron", 1))
	c.move_or_merge(3, 0)
	if c.resize_capacity(3).is_ok():
		return Result.err_code("Test.Case04", "Unsafe shrink must fail.")
	c.sort()
	if c.get_slot(0).item_id != &"sword_iron" or c.get_slot(1).count != 10 or c.get_slot(2).count != 5:
		return Result.err_code("Test.Case04", "Sort compaction mismatch.")
	if c.resize_capacity(3).is_err():
		return Result.err_code("Test.Case04", "Safe shrink failed.")
	return Result.ok(true)


func _case_05_grid_packing_and_rotation() -> Result:
	var c := GridItemContainer.new(&"test_grid", 3, 2, spec_resolver)
	if c.add(ItemStack.create(&"sword_iron", 1)).is_err() or c.add(ItemStack.create(&"sword_iron", 1)).is_err():
		return Result.err_code("Test.Case05", "Auto-rotated 1x3 swords failed to pack in 3x2.")
	if c.add(ItemStack.create(&"sword_iron", 1)).is_ok():
		return Result.err_code("Test.Case05", "Overflow sword should fail.")
	c.clear()
	var rot_err: Result = c.place_at(ItemStack.create(&"totem_fixed", 1), Vector2i.ZERO, true)
	if rot_err.error_code() != InventoryError.ROTATION_FORBIDDEN:
		return Result.err_code("Test.Case05", "Non-rotatable check failed.")
	return Result.ok(true)


func _case_06_grid_adjacency_scan() -> Result:
	var c := GridItemContainer.new(&"adj_grid", 4, 4, spec_resolver)
	c.place_at(ItemStack.create(&"sword_iron", 1), Vector2i(1, 0), false)
	c.place_at(ItemStack.create(&"ring_ruby", 1), Vector2i(2, 1), false)
	c.place_at(ItemStack.create(&"potion_hp", 1), Vector2i(0, 3), false)
	var s_uid: int = c.get_cell_uid(1, 0)
	var r_uid: int = c.get_cell_uid(2, 1)
	var p_uid: int = c.get_cell_uid(0, 3)
	if not c.get_adjacent_uids(s_uid, false).has(r_uid) or c.get_adjacent_uids(s_uid, false).size() != 1:
		return Result.err_code("Test.Case06", "Orthogonal neighbors mismatch.")
	if not c.get_adjacent_uids(s_uid, true).has(p_uid) or c.get_adjacent_uids(s_uid, true).size() != 2:
		return Result.err_code("Test.Case06", "Diagonal neighbors mismatch.")
	return Result.ok(true)


func _case_07_cross_slot_equip_swap() -> Result:
	var b := SlotItemContainer.new(&"b", 2, spec_resolver)
	var w := SlotItemContainer.new(&"w", 1, spec_resolver, ContainerRule.new().with_all_tags([&"weapon"]))
	b.add_at(0, ItemStack.create(&"sword_iron", 1))
	b.add_at(1, ItemStack.create(&"potion_hp", 5))
	w.add_at(0, ItemStack.create(&"axe_battle", 1))
	if InventoryTransaction.transfer_slot(b, 1, w, 0).is_ok():
		return Result.err_code("Test.Case07", "Invalid weapon swap should fail.")
	var ok_swap: Result = InventoryTransaction.transfer_slot(b, 0, w, 0)
	if ok_swap.is_err() or w.get_slot(0).item_id != &"sword_iron" or b.get_slot(0).item_id != &"axe_battle":
		return Result.err_code("Test.Case07", "Valid full-bag weapon swap failed.")
	return Result.ok(true)


func _case_08_full_bag_crafting_paradox() -> Result:
	var w := MapItemContainer.new(&"w", 0, spec_resolver)
	var b := SlotItemContainer.new(&"b", 2, spec_resolver)
	w.add(ItemStack.create(&"gold", 500))
	b.add_at(0, ItemStack.create(&"ore_iron", 10))
	b.add_at(1, ItemStack.create(&"potion_hp", 10))
	var sig_cnt: Array[int] = [0, 0]
	w.changed.connect(func(_d: InventoryDiff) -> void: sig_cnt[0] += 1)
	b.changed.connect(func(_d: InventoryDiff) -> void: sig_cnt[1] += 1)
	var tx := InventoryTransaction.new()
	tx.take_by_id(w, &"gold", 300)
	tx.take_by_id(b, &"ore_iron", 10)
	tx.give(b, ItemStack.create(&"sword_iron", 1))
	if tx.commit().is_err() or sig_cnt[0] != 1 or sig_cnt[1] != 1:
		return Result.err_code("Test.Case08", "Full-bag crafting or coalesced signal failed.")
	return Result.ok(true)


func _case_09_transaction_rollback_and_dry_run() -> Result:
	var w := MapItemContainer.new(&"w", 0, spec_resolver)
	var b := SlotItemContainer.new(&"b", 1, spec_resolver)
	w.add(ItemStack.create(&"gold", 1000))
	b.add_at(0, ItemStack.create(&"ore_iron", 10))
	var floor_before: int = BaseItemContainer.get_uid_floor()
	var tx := InventoryTransaction.new()
	tx.take_by_id(w, &"gold", 400)
	tx.take_by_id(b, &"ore_iron", 5)
	tx.give(b, ItemStack.create(&"sword_iron", 1))
	if tx.can_commit().is_ok() or tx.commit().is_ok():
		return Result.err_code("Test.Case09", "Unvacated full-bag craft must fail.")
	if w.get_total_count(&"gold") != 1000 or b.get_total_count(&"ore_iron") != 10:
		return Result.err_code("Test.Case09", "Rollback leaked items.")
	if BaseItemContainer.get_uid_floor() != floor_before:
		return Result.err_code("Test.Case09", "Rollback leaked UID floor.")
	return Result.ok(true)


func _case_10_heterogeneous_transfer_and_snapshot() -> Result:
	var g := GridItemContainer.new(&"g", 4, 4, spec_resolver)
	var m := MapItemContainer.new(&"m", 10, spec_resolver)
	g.place_at(ItemStack.create(&"potion_hp", 8), Vector2i(0, 0))
	g.place_at(ItemStack.create(&"axe_battle", 1, {"sharpness": 99}), Vector2i(1, 0))
	var p_uid: int = g.get_cell_uid(0, 0)
	var a_uid: int = g.get_cell_uid(1, 0)
	if InventoryTransaction.transfer_any(g, m, p_uid, 5).is_err():
		return Result.err_code("Test.Case10", "Partial Grid->Map transfer failed.")
	if InventoryTransaction.transfer_any(g, m, a_uid, -1).is_err():
		return Result.err_code("Test.Case10", "Unique Grid->Map transfer failed.")
	var g2 := GridItemContainer.new(&"g", 1, 1, spec_resolver)
	var m2 := MapItemContainer.new(&"m", 1, spec_resolver)
	g2.restore_snapshot(g.capture_snapshot())
	m2.restore_snapshot(m.capture_snapshot())
	if g2.get_total_count(&"potion_hp") != 3 or m2.get_total_count(&"potion_hp") != 5:
		return Result.err_code("Test.Case10", "Snapshot round-trip counts mismatch.")
	return Result.ok(true)

#endregion
