class_name ItemStack
extends BaseParams

## 最小运行时物品载荷单元（Runtime Item Stack & Instance Payload）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/types/[/code][br]
## [b]核心设计（堆叠物与独立个体统一建模）：[/b][br]
## 1. [b]轻量双态兼容[/b]：标准消耗品/货币保持 [member meta] 为空字典，实现最小内存与序列化体积；
##    带随机词条、强化等级、耐久度或绑定标记的独立个体将动态属性存入 [member meta] 并持有全局唯一 [member uid]；[br]
## 2. [b]结构化堆叠隔离[/b]：[method can_merge_with] 自动递归比对双方 [member meta] 字典的值等价性——
##    例如两瓶同为 [code]{"bound": true}[/code] 的绑定药水可正常合堆，而绑定药水与非绑定药水自动隔离；[br]
## 3. [b]自动序列化[/b]：继承 [BaseParams]，天然支持 [method BaseParams.to_dict] 与 [method BaseParams.from_dict] 存档转换。


#region Stack Properties

## 运行时实例全局唯一标识：[br]
## - [code]0[/code]：尚未入库分配，或位于 [MapItemContainer] 字典计数池中的纯可替代标准品；[br]
## - [code]> 0[/code]：由 [method BaseItemContainer.allocate_uid] 分配的实例追踪号，跨容器搬运时保持不变。
var uid: int = 0

## 关联静态规格（[ItemSpec]）的物品配置 ID。
var item_id: StringName = &""

## 当前堆叠数量（合法入库堆始终满足 [code]count >= 1[/code]）。
var count: int = 1

## 在二维空间网格容器（[GridItemContainer]）中的 90 度旋转姿态标记；在一维或字典容器中无损透传保留。
var rotated: bool = false

## 业务透明扩展元数据字典（如 [code]{"level": 5, "affixes": ["crit"], "bound": true}[/code]）。[br]
## 基建层仅在克隆、快照序列化及 [method can_merge_with] 等价性判定时访问它，绝不硬编码解析内部业务键名。
var meta: Dictionary = {}

#endregion


#region Public Factories & Atomic Operations

## 快捷工厂：构造一份新的 [ItemStack] 实例（内部自动对 [param p_meta] 执行深拷贝，阻断外部可变字典引用污染）。[br]
## [param p_item_id] 物品配置 ID。[br]
## [param p_count] 初始堆叠数量。[br]
## [param p_meta] 可选动态扩展属性字典。[br]
## [param p_uid] 可选预设唯一实例 ID（传 [code]0[/code] 则在入库时由容器按需分配）。[br]
## [param p_rotated] 二维网格初始旋转朝向。
static func create(
	p_item_id: StringName,
	p_count: int = 1,
	p_meta: Dictionary = {},
	p_uid: int = 0,
	p_rotated: bool = false
) -> ItemStack:
	var stack := ItemStack.new()
	stack.uid = maxi(0, p_uid)
	stack.item_id = p_item_id
	stack.count = p_count
	stack.rotated = p_rotated
	stack.meta = p_meta.duplicate(true)
	return stack


## 检查当前物品堆是否处于合法有效状态（[member item_id] 非空且 [member count] > 0）。
func is_valid() -> bool:
	return not item_id.is_empty() and count > 0


## 检查当前物品堆是否携带任何自定义扩展元数据（即 [member meta] 非空）。
func has_meta_payload() -> bool:
	return not meta.is_empty()


## 执行 O(1) 强类型内存深拷贝（保留原 [member uid] 与旋转标记，并递归深拷贝 [member meta] 字典）。[br]
## 容器对外返回查询结果时统一返回此克隆件，防止调用方在外部意外直接篡改容器内部状态。
func clone_stack() -> ItemStack:
	var copy := ItemStack.new()
	copy.uid = uid
	copy.item_id = item_id
	copy.count = count
	copy.rotated = rotated
	copy.meta = meta.duplicate(true)
	return copy


## 判定当前物品堆在语义上是否允许与另一堆 [param other] 合并堆叠。[br]
## [param other] 待合入的另一堆物品。[br]
## [param max_stack] 静态规格定义的最大堆叠上限（[code]<= 1[/code] 时直接不可合并）。[br]
## [param custom_predicate] 可选自定义合并谓词（签名：[code]func(a: ItemStack, b: ItemStack) -> bool[/code]）。
func can_merge_with(
	other: ItemStack,
	max_stack: int,
	custom_predicate: Callable = Callable()
) -> bool:
	if other == null or not is_valid() or not other.is_valid():
		return false
	if max_stack <= 1 or item_id != other.item_id:
		return false
	# Godot 4 Dictionary `==` 执行递归键值相等比对：同结构同值的元数据允许合并，异值自动隔离
	if meta != other.meta:
		return false
	if custom_predicate.is_valid():
		return bool(custom_predicate.call(self, other))
	return true


## 从当前物品堆中原地拆出 [param split_count] 个物品，生成并返回一个独立的新 [ItemStack]。[br]
## [param split_count] 拆出数量，必须严格满足 [code]1 <= split_count < count[/code]（整堆移动请直接使用转移接口而非拆堆）。[br]
## [param new_uid] 赋予新拆出子堆的唯一实例 ID。[br]
## 成功返回 [code]Result.ok(ItemStack)[/code]；参数越界时返回 [constant InventoryError.INVALID_PARAM] 且原堆数量不变。
func split_off(split_count: int, new_uid: int = 0) -> Result:
	if not is_valid():
		return Result.err_code(InventoryError.INVALID_PARAM, "Cannot split an invalid ItemStack.")
	if split_count <= 0 or split_count >= count:
		return Result.err_code(
			InventoryError.INVALID_PARAM,
			"split_count (%d) must be between 1 and count - 1 (%d)." % [split_count, count - 1]
		)
	count -= split_count
	var separated := ItemStack.create(item_id, split_count, meta, new_uid, rotated)
	return Result.ok(separated)

#endregion
