class_name ContainerRule
extends RefCounted

## 容器准入过滤、移除锁与自定义合并谓词算子（Declarative & Functional Container Rule）。[br]
##
## [b]所属子包：[/b][code]src/framework/infra/inventory/rule/[/code][br]
## [b]设计动机：[/b][br]
## 背包、武器槽、饰品栏、快捷药水栏与任务物品包在底层共享完全相同的容器数据结构，
## 它们的唯一业务差异仅在于「允许什么放进来、允许什么拿出去、什么条件下允许叠在一起」。
## 将这三项判定抽离为独立的无状态规则对象挂载于 [member BaseItemContainer.rule]，即可实现零继承派生扩展任意专用槽位。[br]
##
## [codeblocks]
## [gdscript]
## # 构造仅允许放入「双持武器或盾牌」且禁止放入「诅咒物」的副手装备槽规则
## var offhand_rule := ContainerRule.new() \
##     .with_all_tags([&"equip"]) \
##     .with_any_tags([&"shield", &"dagger"]) \
##     .with_blocked_tags([&"cursed"])
## [/gdscript]
## [/codeblocks]


#region Rule Configuration Fields

## 准入白名单（逻辑与 AND）：非空时，待放入物品的 [member ItemSpec.tags] 必须同时包含此处列出的全部标签。
var required_all_tags: Array[StringName] = []

## 准入白名单（逻辑或 OR）：非空时，待放入物品的 [member ItemSpec.tags] 至少命中其中任意一个标签即可。
var required_any_tags: Array[StringName] = []

## 准入黑名单（逻辑非 NOT）：只要待放入物品命中此处任意一个标签即被立即拦截（优先级高于白名单）。
var blocked_tags: Array[StringName] = []

## 移除许可开关：设为 [code]false[/code] 时禁止从该容器中扣减或转出任何物品（适用于只读预览箱或剧情锁定栏位）。
var allow_remove: bool = true

## 自定义准入校验闭包：签名为 [code]func(stack: ItemStack, spec: ItemSpec) -> bool | Result[/code]。[br]
## 当返回 [Result] 时可透传业务自定义错误码与原因文案；返回 [code]false[/code] 时统一包装为 [constant InventoryError.RULE_REJECTED]。
var custom_accept_predicate: Callable = Callable()

## 自定义堆叠等价校验闭包：签名为 [code]func(a: ItemStack, b: ItemStack) -> bool[/code]。[br]
## 在基础 ID 与 [member ItemStack.meta] 比对通过后追加调用，可用于实现特殊业务隔离（如限时道具过期时间相近才允许合并）。
var custom_merge_predicate: Callable = Callable()

#endregion


#region Fluent Builder API

## 链式设置必须同时具备的全部标签集合 [param tags]（AND 关系）。
func with_all_tags(tags: Array[StringName]) -> ContainerRule:
	required_all_tags = tags.duplicate()
	return self


## 链式设置至少具备其一的候选标签集合 [param tags]（OR 关系）。
func with_any_tags(tags: Array[StringName]) -> ContainerRule:
	required_any_tags = tags.duplicate()
	return self


## 链式设置严禁放入的黑名单标签集合 [param tags]（NOT 关系）。
func with_blocked_tags(tags: Array[StringName]) -> ContainerRule:
	blocked_tags = tags.duplicate()
	return self


## 链式设置容器是否允许执行移除或转出操作 [param allowed]。
func with_remove_allowed(allowed: bool) -> ContainerRule:
	allow_remove = allowed
	return self


## 链式注入自定义准入校验闭包 [param predicate]（签名：[code]func(stack: ItemStack, spec: ItemSpec) -> bool | Result[/code]）。
func with_accept_predicate(predicate: Callable) -> ContainerRule:
	custom_accept_predicate = predicate
	return self


## 链式注入自定义合并等价校验闭包 [param predicate]（签名：[code]func(a: ItemStack, b: ItemStack) -> bool[/code]）。
func with_merge_predicate(predicate: Callable) -> ContainerRule:
	custom_merge_predicate = predicate
	return self

#endregion


#region Evaluation Primitives

## 依次按「黑名单 ➔ 必需全标签 ➔ 任一候选标签 ➔ 自定义闭包」顺序评估 [param stack] 是否允许进入容器。[br]
## [param stack] 待放入的运行时物品堆。[br]
## [param spec] 已解析的对应静态规格描述符。[br]
## 通过返回 [code]Result.ok(true)[/code]；被拦截返回 [constant InventoryError.RULE_REJECTED]（或自定义闭包返回的 [Result]）。
func evaluate_accept(stack: ItemStack, spec: ItemSpec) -> Result:
	if stack == null or not stack.is_valid():
		return Result.err_code(InventoryError.INVALID_PARAM, "ItemStack is null or invalid.")
	if spec == null:
		return Result.err_code(InventoryError.SPEC_NOT_FOUND, "ItemSpec is null.")

	# 1. 黑名单一票否决
	for blocked: StringName in blocked_tags:
		if spec.has_tag(blocked):
			return Result.err_code(
				InventoryError.RULE_REJECTED,
				"Item '%s' carries blocked tag '%s'." % [String(stack.item_id), String(blocked)]
			)

	# 2. 必需全标签校验 (AND)
	for req_tag: StringName in required_all_tags:
		if not spec.has_tag(req_tag):
			return Result.err_code(
				InventoryError.RULE_REJECTED,
				"Item '%s' misses required tag '%s'." % [String(stack.item_id), String(req_tag)]
			)

	# 3. 候选任一标签校验 (OR)
	if not required_any_tags.is_empty():
		var matched_any: bool = false
		for candidate: StringName in required_any_tags:
			if spec.has_tag(candidate):
				matched_any = true
				break
		if not matched_any:
			return Result.err_code(
				InventoryError.RULE_REJECTED,
				"Item '%s' matches none of required_any_tags." % String(stack.item_id)
			)

	# 4. 外部自定义准入谓词扩展点
	if custom_accept_predicate.is_valid():
		var custom_out: Variant = custom_accept_predicate.call(stack, spec)
		if custom_out is Result:
			var custom_res: Result = custom_out as Result
			if custom_res.is_err():
				return custom_res
		elif not bool(custom_out):
			return Result.err_code(
				InventoryError.RULE_REJECTED,
				"Item '%s' rejected by custom_accept_predicate." % String(stack.item_id)
			)

	return Result.ok(true)


## 评估当前容器是否允许移除或转出物品；锁定时返回 [constant InventoryError.RULE_REJECTED]。
func evaluate_remove() -> Result:
	if not allow_remove:
		return Result.err_code(InventoryError.RULE_REJECTED, "Container removal is locked by rule.")
	return Result.ok(true)

#endregion
