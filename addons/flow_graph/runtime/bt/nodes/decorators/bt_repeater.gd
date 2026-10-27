class_name BTRepeater
extends BTNode

## 循环执行装饰节点（Repeater Decorator Node）。[br]
##
## [b]享元执行契约：[/b][br]
## - 循环执行唯一子节点 `repeat_count` 次（`<= 0` 表示无限循环持续返回 `RUNNING`）；[br]
## - 若 `abort_on_failure == true` 且子节点返回 `FAILURE`，立即清空计数并返回 `FAILURE`；[br]
## - 循环计次严格存储在单实体 `ctx.blackboard` 节点记忆槽中。

#region Constants & Config
const _MEM_COMPLETED_COUNT: StringName = &"completed_count"

var repeat_count: int = 3
var abort_on_failure: bool = true
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_repeat_count: int = 3,
	p_abort_on_failure: bool = true,
	p_title: String = ""
) -> void:
	var default_lbl: String = "Repeat(inf)" if p_repeat_count <= 0 else "Repeat(x%d)" % p_repeat_count
	var resolved_title: String = p_title if not p_title.is_empty() else default_lbl
	super._init(p_node_id, &"Repeater", resolved_title, false)
	repeat_count = p_repeat_count
	abort_on_failure = p_abort_on_failure


func _on_tick(ctx: BTContext) -> int:
	if children.is_empty():
		return BTStatus.Status.FAILURE

	var child_status: int = children[0].tick(ctx)
	if child_status == BTStatus.Status.RUNNING:
		return BTStatus.Status.RUNNING

	if child_status == BTStatus.Status.FAILURE and abort_on_failure:
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.FAILURE

	if repeat_count <= 0:
		return BTStatus.Status.RUNNING

	var done: int = int(ctx.blackboard.get_node_mem(node_id, _MEM_COMPLETED_COUNT, 0)) + 1
	if done >= repeat_count:
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.SUCCESS

	ctx.blackboard.set_node_mem(node_id, _MEM_COMPLETED_COUNT, done)
	return BTStatus.Status.RUNNING
#endregion
