class_name BTAction
extends BTNode

## 动作执行叶节点（Action Leaf Node）。[br]
##
## 支持直接传入 `Callable(ctx: BTContext) -> int`（返回 [enum BTStatus.Status] 或 `bool`），
## 亦支持由 [BTCompiler] 从动作注册表按 `action_key` + `params` 动态装配。

#region Config
var action_callable: Callable = Callable()
var action_key: StringName = &""
var params: Dictionary = {}
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_title: String = "Action",
	p_callable: Callable = Callable(),
	p_action_key: StringName = &"",
	p_params: Dictionary = {}
) -> void:
	super._init(p_node_id, &"Action", p_title, true)
	action_callable = p_callable
	action_key = p_action_key
	params = p_params.duplicate(true)


func _on_tick(ctx: BTContext) -> int:
	if not action_callable.is_valid():
		return BTStatus.Status.FAILURE

	var res: Variant = null
	var argc := action_callable.get_argument_count()
	if argc >= 2:
		res = action_callable.call(ctx, params)
	elif argc == 1:
		res = action_callable.call(ctx)
	else:
		res = action_callable.call()

	if res is bool:
		return BTStatus.Status.SUCCESS if bool(res) else BTStatus.Status.FAILURE
	if res is int:
		return clampi(int(res), BTStatus.Status.SUCCESS, BTStatus.Status.RUNNING)
	return BTStatus.Status.SUCCESS
#endregion
