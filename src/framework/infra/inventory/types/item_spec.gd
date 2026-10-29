class_name ItemSpec
extends BaseParams

## 物品静态规格最小契约描述符（Minimal Item Specification Descriptor）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/types/[/code][br]
## [b]核心设计（享元解耦）：[/b][br]
## 1. [b]仅保留容器拓扑原语[/b]：只描述「能不能叠、最多叠几个、占多大格子、能不能转、带什么分类标签、整理排第几」；[br]
## 2. [b]零业务污染[/b]：绝不混入攻击力、售价、图标贴图或多语言文案等具体玩法字段；[br]
## 3. [b]反查回调注入[/b]：容器通过 [Callable]（见 [method resolver_from_dict]）按 [member item_id] 动态反查本对象，
##    无论上层策划表采用 JSON、CSV 还是自定义 [Resource] 均无需改动底层容器代码。[br]
##
## [codeblocks]
## [gdscript]
## var sword_spec := ItemSpec.create(&"sword_iron", 1, [&"equip", &"weapon"], Vector2i(1, 3), true, 90)
## var eff_size: Vector2i = sword_spec.get_effective_size(true) # Vector2i(3, 1)
## [/gdscript]
## [/codeblocks]


#region Spec Properties

## 物品静态配置全局唯一标识（推荐与策划配表主键保持一致）。
var item_id: StringName = &""

## 单槽或单堆允许的最大堆叠数量：[br]
## - [code]1[/code]：不可堆叠独立个体（如武器、护甲、遗物）；[br]
## - [code]> 1[/code]：可堆叠标准消耗品、材料或货币。
var max_stack: int = 99

## 在二维空间网格容器（[GridItemContainer]）中未旋转时占据的基础宽高尺寸（单位：格，最小钳制为 [code](1, 1)[/code]）。
var grid_size: Vector2i = Vector2i.ONE

## 在二维空间网格容器中是否允许 90 度旋转（旋转后实际占地宽高互换为 [code](grid_size.y, grid_size.x)[/code]）。
var rotatable: bool = true

## 语义分类标签列表（如 [code]&"weapon"[/code]、[code]&"consumable"[/code]、[code]&"quest"[/code]，供 [ContainerRule] 执行准入过滤）。
var tags: Array[StringName] = []

## 容器一键整理（[method SlotItemContainer.sort]）时的排序优先级权重（数值越大越靠前；同权重按 [member item_id] 升序排列）。
var sort_priority: int = 0

#endregion


#region Public Factories & Helpers

## 快捷工厂：构造并完成边界归一化的一份 [ItemSpec] 描述符。[br]
## [param p_item_id] 物品唯一配置 ID。[br]
## [param p_max_stack] 单堆最大上限（自动钳制为 [code]>= 1[/code]）。[br]
## [param p_tags] 分类标签数组（内部保存浅拷贝副本防外部篡改）。[br]
## [param p_grid_size] 二维网格基础宽高（自动钳制各分量为 [code]>= 1[/code]）。[br]
## [param p_rotatable] 二维网格中是否允许旋转。[br]
## [param p_sort_priority] 一键整理排序优先级权重。
static func create(
	p_item_id: StringName,
	p_max_stack: int = 99,
	p_tags: Array[StringName] = [],
	p_grid_size: Vector2i = Vector2i.ONE,
	p_rotatable: bool = true,
	p_sort_priority: int = 0
) -> ItemSpec:
	var spec := ItemSpec.new()
	spec.item_id = p_item_id
	spec.max_stack = maxi(1, p_max_stack)
	spec.grid_size = Vector2i(maxi(1, p_grid_size.x), maxi(1, p_grid_size.y))
	spec.rotatable = p_rotatable
	spec.tags = p_tags.duplicate()
	spec.sort_priority = p_sort_priority
	return spec


## 将内存规格字典包装为可供 [method BaseItemContainer.set_spec_resolver] 注入的标准解析闭包。[br]
## [param spec_map] 键为 [StringName] 或 [String]、值为 [ItemSpec] 的映射表，时间复杂度 O(1)。
static func resolver_from_dict(spec_map: Dictionary) -> Callable:
	return func(query_id: StringName) -> ItemSpec:
		var found: Variant = spec_map.get(query_id, null)
		if found is ItemSpec:
			return found as ItemSpec
		var str_found: Variant = spec_map.get(String(query_id), null)
		return str_found as ItemSpec if str_found is ItemSpec else null


## 原地执行数值边界自愈（确保 [member max_stack] >= 1 且 [member grid_size] 宽高各 >= 1），返回自身便于链式调用。
func sanitize() -> ItemSpec:
	max_stack = maxi(1, max_stack)
	grid_size = Vector2i(maxi(1, grid_size.x), maxi(1, grid_size.y))
	return self


## 判断该物品是否支持复数堆叠（即 [code]max_stack > 1[/code]）。
func is_stackable() -> bool:
	return max_stack > 1


## 判断该物品是否携带指定的语义分类标签 [param tag]。
func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## 计算物品在给定旋转标记 [param is_rotated] 下实际占据的二维网格尺寸。[br]
## 注意：仅当 [param is_rotated] 与 [member rotatable] 同时为 [code]true[/code] 时宽高才会互换。
func get_effective_size(is_rotated: bool = false) -> Vector2i:
	var base_w: int = maxi(1, grid_size.x)
	var base_h: int = maxi(1, grid_size.y)
	if is_rotated and rotatable:
		return Vector2i(base_h, base_w)
	return Vector2i(base_w, base_h)

#endregion
