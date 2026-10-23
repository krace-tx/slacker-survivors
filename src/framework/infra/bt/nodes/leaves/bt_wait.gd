class_name BTWait
extends BTNode

## 定时等待叶节点（Wait / Delay Leaf Node）。[br]
##
## 在持续等待期间返回 `RUNNING`（进度保存在单实体 `ctx.blackboard` 节点记忆槽），计时满 `duration_sec` 后返回 `SUCCESS`。

#region Constants & Config
const _MEM_ELAPSED: StringName = &"elapsed"

var duration_sec: float = 0.5
#endregion


#region Execution
func _init(p_node_id: int = 0, p_duration_sec: float = 0.5, p_title: String = "") -> void:
	var resolved_title := p_title if not p_title.is_empty() else "Wait(%.2fs)" % p_duration_sec
	super._init(p_node_id, &"Wait", resolved_title, true)
	duration_sec = maxf(0.0, p_duration_sec)


func _on_tick(ctx: BTContext) -> int:
	if duration_sec <= 0.0:
		return BTStatus.Status.SUCCESS
	var elapsed := float(ctx.blackboard.get_node_mem(node_id, _MEM_ELAPSED, 0.0)) + ctx.delta
	if elapsed >= duration_sec:
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.SUCCESS
	ctx.blackboard.set_node_mem(node_id, _MEM_ELAPSED, elapsed)
	return BTStatus.Status.RUNNING
#endregion
