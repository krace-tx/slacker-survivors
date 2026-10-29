class_name InventoryError
extends RefCounted

## 背包与通用容器基建标准化错误码常量表（Inventory Infrastructure Error Codes）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/types/[/code][br]
## [b]设计契约：[/b][br]
## 1. 严格遵循全框架统一的 [code]{Module}.{Reason}[/code] 二段式错误码规范；[br]
## 2. 供 [BaseItemContainer] 各派生容器、[ContainerRule] 及 [InventoryTransaction] 构造强类型失败 [Result]；[br]
## 3. 上层业务可通过 [method Result.error_code] 与本类常量精确比对，区分「背包已满」「材料不足」「标签不符」等UI提示分支。


#region Error Code Constants

## 非法调用入参（如数量 [code]<= 0[/code]、空 [code]item_id[/code]、非法拆分区间或传入 [code]null[/code] 容器引用）。
const INVALID_PARAM: String = "Inventory.InvalidParam"

## 一维槽位索引超出 [code][0, capacity - 1][/code]，或二维网格占地矩形越出 [code][0, width) × [0, height)[/code] 边界。
const OUT_OF_BOUNDS: String = "Inventory.OutOfBounds"

## 容器开启严格规格模式（[member BaseItemContainer.strict_spec] 为 [code]true[/code]）时，未能解析目标 [ItemSpec]。
const SPEC_NOT_FOUND: String = "Inventory.SpecNotFound"

## 容器挂载的 [ContainerRule] 拒绝本次操作（命中黑名单标签、缺失必需标签、移除被锁定或自定义谓词拦截）。
const RULE_REJECTED: String = "Inventory.RuleRejected"

## 容器剩余槽位、独立个体配额、单堆最大上限或二维网格连续空间不足以容纳目标物品。
const CAPACITY_FULL: String = "Inventory.CapacityFull"

## 容器或指定实例当前持有的物品数量少于请求扣减或转出的数量。
const INSUFFICIENT_ITEM: String = "Inventory.InsufficientItem"

## 请求访问、移动、拆分或移除的目标槽位、网格坐标或唯一实例 [code]uid[/code] 不存在对应物品。
const ITEM_NOT_FOUND: String = "Inventory.ItemNotFound"

## 定点合并失败：两堆物品的 [code]item_id[/code] 不同、物品不可堆叠（[code]max_stack == 1[/code]）或扩展元数据 [code]meta[/code] 不等价。
const MERGE_INCOMPATIBLE: String = "Inventory.MergeIncompatible"

## 对静态规格声明为禁止旋转（[member ItemSpec.rotatable] 为 [code]false[/code]）的物品请求了 90 度旋转放置。
const ROTATION_FORBIDDEN: String = "Inventory.RotationForbidden"

## 二维空间网格的目标矩形区域内存在多件阻挡物，或存在无法与当前物品直接合并的单个阻挡物。
const COLLISION: String = "Inventory.Collision"

## 跨容器互换（如穿戴替换装备）失败：请求了非整堆互换，或换回源容器的旧物品未通过源容器的 [ContainerRule] 校验。
const SWAP_REJECTED: String = "Inventory.SwapRejected"

#endregion
