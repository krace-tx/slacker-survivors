@tool
class_name BTCondition
extends BTNode

## 条件判断叶节点（Condition Leaf Node）。[br]
##
## [b]多模条件求值：[/b][br]
## 1. [b]轻量表达式模式 (`expr: String`)[/b]：通过 [FlowBlackboardExpr] 静态编译缓存求值 `!enemy_in_sight`、`hp_ratio <= 0.3 && ammo > 0`；[br]
## 2. [b]代码闭包模式 (`predicate: Callable`)[/b]：构造期预缓存元数，支持 `negate`（`!condition_key`）直接取反；[br]
## 3. [b]黑板键值比较模式 (`bb_key`, `op`, `compare_value`)[/b]：预缓存操作符字符串，热路径零字符串分配比较黑板键值。

#region Config
var predicate: Callable = Callable()
var bb_key: StringName = &""
var op: StringName = &"=="
var compare_value: Variant = null
var expr: String = ""
var negate: bool = false
var cond_lookup: Callable = Callable()

var _pred_argc: int = 0
var _op_str: String = "=="
var _bb_key_str: String = ""
var _is_negated_bb_expr: bool = false
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_title: String = "Condition",
	p_predicate: Callable = Callable(),
	p_bb_key: StringName = &"",
	p_op: StringName = &"==",
	p_compare_value: Variant = null,
	p_expr: String = "",
	p_negate: bool = false,
	p_cond_lookup: Callable = Callable()
) -> void:
	super._init(p_node_id, &"Condition", p_title, true)
	predicate = p_predicate
	_pred_argc = predicate.get_argument_count() if predicate.is_valid() else 0
	bb_key = p_bb_key
	op = p_op
	_op_str = String(p_op)
	compare_value = p_compare_value
	expr = p_expr
	negate = p_negate
	cond_lookup = p_cond_lookup
	_bb_key_str = String(p_bb_key)
	_is_negated_bb_expr = (compare_value == null and _bb_key_str.begins_with("!"))


func _on_tick(ctx: BTContext) -> int:
	if not expr.is_empty():
		var expr_ok: bool = FlowBlackboardExpr.eval_expr(expr, cond_lookup, ctx.blackboard, ctx)
		if negate:
			expr_ok = not expr_ok
		return BTStatus.Status.SUCCESS if expr_ok else BTStatus.Status.FAILURE

	if predicate.is_valid():
		var pred_ok: bool = bool(predicate.call(ctx)) if _pred_argc >= 1 else bool(predicate.call())
		if negate:
			pred_ok = not pred_ok
		return BTStatus.Status.SUCCESS if pred_ok else BTStatus.Status.FAILURE

	if not bb_key.is_empty():
		if _is_negated_bb_expr:
			var neg_bb_ok: bool = FlowBlackboardExpr.eval_expr(_bb_key_str, cond_lookup, ctx.blackboard, ctx)
			return BTStatus.Status.SUCCESS if neg_bb_ok else BTStatus.Status.FAILURE
		var actual: Variant = ctx.blackboard.get_var(bb_key, null)
		var matched: bool = _evaluate_comparison(actual, op, _op_str, compare_value)
		if negate:
			matched = not matched
		return BTStatus.Status.SUCCESS if matched else BTStatus.Status.FAILURE

	return BTStatus.Status.FAILURE


static func _evaluate_comparison(lhs: Variant, operator: StringName, op_str: String, rhs: Variant) -> bool:
	if lhs == null:
		return operator == &"!=" and rhs != null
	return FlowBlackboardExpr.compare_values(lhs, op_str, rhs)


func clear() -> void:
	predicate = Callable()
	_pred_argc = 0
	cond_lookup = Callable()
	compare_value = null
	super.clear()
#endregion
