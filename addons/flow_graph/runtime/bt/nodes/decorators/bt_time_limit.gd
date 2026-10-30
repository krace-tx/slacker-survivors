@tool
class_name BTTimeLimit
extends BTNode

## 超时限制装饰节点（TimeLimit / Timeout Decorator Node）。[br]
##
## 在 `ctx.blackboard` 节点记忆槽中累加子节点持续处于 `RUNNING` 的秒数；
## 一旦达到或超过 `timeout_sec`，立即调用 `children[0].abort(ctx)`、清空计时并返回 `BTStatus.Status.FAILURE`。

#region Constants & Config
const _MEM_ELAPSED: StringName = &"elapsed"

var timeout_sec: float = 3.0
#endregion


#region Execution
func _init(p_node_id: int = 0, p_timeout_sec: float = 3.0, p_title: String = "") -> void:
	var resolved_title: String = p_title if not p_title.is_empty() else "TimeLimit(%.2fs)" % p_timeout_sec
	super._init(p_node_id, &"TimeLimit", resolved_title, false)
	timeout_sec = maxf(0.0, p_timeout_sec)


func _on_tick(ctx: BTContext) -> int:
	if children.is_empty():
		return BTStatus.Status.FAILURE
	if timeout_sec <= 0.0:
		children[0].abort(ctx)
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.FAILURE

	var prev_elapsed: float = float(ctx.blackboard.get_node_mem(node_id, _MEM_ELAPSED, 0.0))
	var next_elapsed: float = prev_elapsed + ctx.delta
	if prev_elapsed > 0.0 and next_elapsed >= timeout_sec:
		children[0].abort(ctx)
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.FAILURE

	var status: int = children[0].tick(ctx)
	if status == BTStatus.Status.RUNNING:
		if next_elapsed >= timeout_sec:
			children[0].abort(ctx)
			ctx.blackboard.clear_node_mem(node_id)
			return BTStatus.Status.FAILURE
		ctx.blackboard.set_node_mem(node_id, _MEM_ELAPSED, next_elapsed)
		return BTStatus.Status.RUNNING

	ctx.blackboard.clear_node_mem(node_id)
	return status
#endregion
