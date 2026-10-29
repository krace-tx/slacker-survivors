@abstract
class_name BaseItemContainer
extends RefCounted

## 通用物品容器抽象基类契约（Abstract Item Container Contract）。[br]
##
## [b]所属位置：[/b][code]src/framework/infra/inventory/[/code]（模块根级公开抽象门面）[br]
## [b]核心职责与第一性原理：[/b][br]
## 1. [b]拓扑无关统一原语[/b]：屏蔽底层存储结构差异（[MapItemContainer] 字典聚合、[SlotItemContainer] 定长一维数组、
##    [GridItemContainer] 二维空间矩阵），向上层业务服务与跨容器事务器（[InventoryTransaction]）暴露统一的增删查改与快照协议；[br]
## 2. [b]全局单调实例 UID 分配与防撞号[/b]：维护进程级递增水位线 [member _uid_sequence]，确保任何独立物品在跨容器转移、
##    装备穿脱或从磁盘反序列化恢复后，其 [member ItemStack.uid] 恒定保留且绝不与新生成物品发生碰撞；[br]
## 3. [b]可重入信号静默栈[/b]：通过 [method push_signal_suppression] 与 [method pop_signal_suppression] 引用计数守卫，
##    允许复合事务在执行多步中间变更时静默挂起通知，待最终提交成功后再一次性发射合并后的 [signal changed]。[br]
## [b]做：[/b]容量与规则校验、UID 水位管理、增删查改契约定义、无损快照编解码。[br]
## [b]不做：[/b]读盘落盘、网络同步、全局事件广播、具体业务数值计算或挂载任何场景树节点。


#region Signals

## 容器内容发生实质性变更且当前未处于事务静默期时发射，携带本次增量变更单 [param diff]。
signal changed(diff: InventoryDiff)

#endregion


#region Static UID Sequence

## 进程内全局单调递增的实例 UID 水位计数器（保证跨容器实例转移永不撞号）。
static var _uid_sequence: int = 0

#endregion


#region Common Properties & Internal State

## 容器业务语义标识（如 [code]&"bag"[/code]、[code]&"wallet"[/code]、[code]&"equip_weapon"[/code]，会写入 [member InventoryDiff.container_id]）。
var container_id: StringName = &"default"

## 挂载的容器准入过滤与移除锁算子（为 [code]null[/code] 时默认放行所有合法 [ItemStack]）。
var rule: ContainerRule = null

## 严格规格校验模式：[br]
## - [code]true[/code]：当 [member _spec_resolver] 未命中目标 [code]item_id[/code] 时直接返回 [constant InventoryError.SPEC_NOT_FOUND]；[br]
## - [code]false[/code]（默认）：未配置或未命中解析器时自动回退为安全默认规格（[code]max_stack = 99, grid_size = 1x1[/code]）。
var strict_spec: bool = false

## 注入的静态规格反查闭包（签名：[code]func(item_id: StringName) -> ItemSpec[/code]）。
var _spec_resolver: Callable = Callable()

## 信号静默嵌套深度计数（[code]> 0[/code] 时挂起 [method notify_changed]，支持嵌套事务安全重入）。
var _signal_suppression_depth: int = 0

#endregion


#region Lifecycle & Fluent Configuration

## 构造容器抽象底座。[br]
## [param p_container_id] 容器唯一业务名称（传空自动回退为 [code]&"default"[/code]）。[br]
## [param p_spec_resolver] 物品静态规格反查回调。[br]
## [param p_rule] 可选容器准入与合并规则算子。[br]
## [param p_strict_spec] 是否开启严格规格缺失报错。
func _init(
	p_container_id: StringName = &"default",
	p_spec_resolver: Callable = Callable(),
	p_rule: ContainerRule = null,
	p_strict_spec: bool = false
) -> void:
	container_id = p_container_id if not p_container_id.is_empty() else &"default"
	_spec_resolver = p_spec_resolver
	rule = p_rule
	strict_spec = p_strict_spec


## 分配并返回一个新的全局唯一实例 UID（恒满足 [code]>= 1[/code]）。
static func allocate_uid() -> int:
	_uid_sequence += 1
	return _uid_sequence


## 将全局 UID 水位线向上对齐至不低于 [param observed_uid]（在反序列化加载历史存档或导入外部预设 UID 时调用，杜绝后续分配撞号）。
static func sync_uid_floor(observed_uid: int) -> void:
	if observed_uid > _uid_sequence:
		_uid_sequence = observed_uid


## 读取当前全局 UID 水位线快照（仅供 [InventoryTransaction] 预演或失败回滚时记录水位）。
static func get_uid_floor() -> int:
	return _uid_sequence


## 将全局 UID 水位线回退还原至事务执行前的 [param previous_floor]（确保 [method InventoryTransaction.can_commit] 100% 零副作用）。
static func restore_uid_floor(previous_floor: int) -> void:
	_uid_sequence = maxi(0, previous_floor)


## 链式注入或替换物品规格反查回调 [param resolver] 及严格模式开关 [param p_strict_spec]。
func set_spec_resolver(resolver: Callable, p_strict_spec: bool = false) -> BaseItemContainer:
	_spec_resolver = resolver
	strict_spec = p_strict_spec
	return self


## 链式挂载或替换容器规则算子 [param p_rule]。
func set_rule(p_rule: ContainerRule) -> BaseItemContainer:
	rule = p_rule
	return self


## 按 [param item_id] 解析对应的 [ItemSpec]（内部自动调用 [method ItemSpec.sanitize] 保证边界合法）。[br]
## 若未命中且 [member strict_spec] 为 [code]true[/code] 则返回 [code]null[/code]；否则返回默认可堆叠规格。
func resolve_spec(item_id: StringName) -> ItemSpec:
	if item_id.is_empty():
		return null
	if _spec_resolver.is_valid():
		var resolved: Variant = _spec_resolver.call(item_id)
		if resolved is ItemSpec:
			return (resolved as ItemSpec).sanitize()
	if strict_spec:
		return null
	return ItemSpec.create(item_id, 99)

#endregion


#region Signal Suppression Protocol

## 压入一层信号静默锁（事务执行期间抑制单步操作直接触发 [signal changed]）。
func push_signal_suppression() -> void:
	_signal_suppression_depth += 1


## 弹出一层信号静默锁（归零后恢复 [method notify_changed] 正常发射）。
func pop_signal_suppression() -> void:
	_signal_suppression_depth = maxi(0, _signal_suppression_depth - 1)


## 当静默深度为 [code]0[/code] 且变更单 [param diff] 非空时，对外发射 [signal changed]。
func notify_changed(diff: InventoryDiff) -> void:
	if _signal_suppression_depth == 0 and diff != null and not diff.is_empty():
		changed.emit(diff)

#endregion


#region Concrete Convenience Queries

## 判断容器内持有的指定 [param item_id] 累计总数量是否达到或超过 [param required_count]（要求 [code]required_count > 0[/code]）。
func has_enough(item_id: StringName, required_count: int = 1) -> bool:
	if item_id.is_empty() or required_count <= 0:
		return false
	return get_total_count(item_id) >= required_count

#endregion


#region Abstract Container Contract

## 查询容器内指定 [param item_id] 的累计持有总数量（同时汇总标准堆叠池与全部独立个体实例）。
@abstract
func get_total_count(item_id: StringName) -> int


## 按唯一实例 [param uid] 检索对应物品堆的深拷贝副本；未命中或 [code]uid <= 0[/code] 时返回 [code]null[/code]。
@abstract
func get_item_by_uid(uid: int) -> ItemStack


## 导出当前容器内全部有效物品堆的深拷贝快照数组（按确定性顺序排列，外部修改不影响容器内部数据）。
@abstract
func get_all_stacks() -> Array[ItemStack]


## 判断当前容器是否完全为空（不包含任何堆叠计数或独立实例）。
@abstract
func is_empty() -> bool


## 计算在不违背 [ContainerRule] 且不溢出容器容量的前提下，当前容器最多还能吸收多少个与 [param stack] 同规格同元数据的物品（取值范围 [code][0, stack.count][/code]）。
@abstract
func get_addable_count(stack: ItemStack) -> int


## 无副作用预演校验整堆 [param stack] 是否允许完整放入容器。[br]
## 通过返回 [code]Result.ok(true)[/code]；否则返回携带 [InventoryError] 标准错误码的失败 [Result]。
@abstract
func can_add(stack: ItemStack) -> Result


## 原子放入整堆 [param stack]（All-or-Nothing：若容器空间不足以装下全部数量则整体拒绝，绝不发生半截吞物）。[br]
## 成功返回 [code]Result.ok(InventoryDiff)[/code]；失败返回对应 [InventoryError]。
@abstract
func add(stack: ItemStack) -> Result


## 按配置 [param item_id] 原子扣减 [param count] 个物品（优先消耗无扩展元数据的标准堆，保护带词条/绑定的特殊堆）。[br]
## 成功返回 [code]Result.ok(InventoryDiff)[/code]；数量不足返回 [constant InventoryError.INSUFFICIENT_ITEM]。
@abstract
func remove_by_id(item_id: StringName, count: int = 1) -> Result


## 按唯一实例 [param uid] 精准扣减 [param count] 个物品（传 [code]-1[/code] 表示整堆移除）。[br]
## 成功返回 [code]Result.ok(InventoryDiff)[/code]；未命中返回 [constant InventoryError.ITEM_NOT_FOUND]。
@abstract
func remove_by_uid(uid: int, count: int = -1) -> Result


## 清空容器内的全部物品，发射变更通知并返回记录了所有移除项的 [InventoryDiff]。
@abstract
func clear() -> InventoryDiff


## 捕获当前容器完整状态的纯净 [Dictionary] 快照（可直接交给存储层 JSON 序列化，或供事务回滚恢复）。
@abstract
func capture_snapshot() -> Dictionary


## 从 [method capture_snapshot] 导出的 [param snapshot] 字典无损恢复容器状态（自动同步全局 UID 水位线）。
@abstract
func restore_snapshot(snapshot: Dictionary) -> Result

#endregion


#region Protected Validation & UID Helpers

## 派生类共用前置守卫：校验 [param stack] 非空合法 ➔ 解析 [ItemSpec] ➔ 执行 [ContainerRule] 准入评估。[br]
## 全部通过时返回 [code]Result.ok(spec)[/code]。
func _validate_accept_and_resolve(stack: ItemStack) -> Result:
	if stack == null or not stack.is_valid():
		return Result.err_code(InventoryError.INVALID_PARAM, "ItemStack is null or invalid.")
	var spec: ItemSpec = resolve_spec(stack.item_id)
	if spec == null:
		return Result.err_code(
			InventoryError.SPEC_NOT_FOUND,
			"ItemSpec not found for '%s'." % String(stack.item_id)
		)
	if rule != null:
		var rule_res: Result = rule.evaluate_accept(stack, spec)
		if rule_res.is_err():
			return rule_res
	return Result.ok(spec)


## 派生类共用移除守卫：检查容器挂载的 [ContainerRule] 是否允许移除物品。
func _validate_remove_allowed() -> Result:
	if rule != null:
		return rule.evaluate_remove()
	return Result.ok(true)


## 提取当前容器挂载的自定义堆叠合并谓词（无规则时返回空 [Callable]）。
func _get_merge_predicate() -> Callable:
	return rule.custom_merge_predicate if rule != null else Callable()


## 确保入库物品按需具备合法唯一 [member ItemStack.uid] 并同步抬升全局水位线。[br]
## [param stack] 待入库物品克隆件。[br]
## [param force_uid] 为 [code]true[/code] 时强制为无元数据标准堆也分配独立 UID（供槽位与网格容器定位使用）。
func _ensure_uid(stack: ItemStack, force_uid: bool = false) -> void:
	if stack.uid > 0:
		sync_uid_floor(stack.uid)
	elif force_uid or stack.has_meta_payload():
		stack.uid = allocate_uid()

#endregion
