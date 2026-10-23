class_name BTCondition
extends BTNode

## 条件判断叶节点（Condition Leaf Node）。[br]
##
## [b]双模条件求值：[/b][br]
## 1. [b]代码闭包模式 (`predicate: Callable`)[/b]：直接执行 `predicate.call(ctx) -> bool`；[br]
## 2. [b]AST 蓝图黑板比较模式 (`bb_key`, `op`, `compare_value`)[/b]：无需写代码即可在蓝图/JSON 中直接配置 `hp_ratio <= 0.5` 或 `posture_broken == true`。

#region Config
var predicate: Callable = Callable()
var bb_key: StringName = &""
var op: StringName = &"=="
var compare_value: Variant = null
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_title: String = "Condition",
	p_predicate: Callable = Callable(),
	p_bb_key: StringName = &"",
	p_op: StringName = &"==",
	p_compare_value: Variant = null
) -> void:
	super._init(p_node_id, &"Condition", p_title, true)
	predicate = p_predicate
	bb_key = p_bb_key
	op = p_op
	compare_value = p_compare_value


func _on_tick(ctx: BTContext) -> int:
	if predicate.is_valid():
		var ok := bool(predicate.call(ctx)) if predicate.get_argument_count() >= 1 else bool(predicate.call())
		return BTStatus.Status.SUCCESS if ok else BTStatus.Status.FAILURE

	if not bb_key.is_empty():
		var actual: Variant = ctx.blackboard.get_var(bb_key, null)
		var matched := _evaluate_comparison(actual, op, compare_value)
		return BTStatus.Status.SUCCESS if matched else BTStatus.Status.FAILURE

	return BTStatus.Status.FAILURE


static func _evaluate_comparison(lhs: Variant, operator: StringName, rhs: Variant) -> bool:
	if lhs == null:
		return operator == &"!=" and rhs != null
	match operator:
		&"==": return lhs == rhs
		&"!=": return lhs != rhs
		&"<":  return float(lhs) < float(rhs)
		&"<=": return float(lhs) <= float(rhs)
		&">":  return float(lhs) > float(rhs)
		&">=": return float(lhs) >= float(rhs)
		_:     return lhs == rhs
#endregion
