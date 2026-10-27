class_name BTWait
extends BTNode

## 定时等待叶节点（Wait / Delay Leaf Node）。[br]
##
## 在持续等待期间返回 `RUNNING`（进度与随机采样目标时长均保存在单实体 `ctx.blackboard` 节点记忆槽），计时满后返回 `SUCCESS`。

#region Constants & Config
const _MEM_ELAPSED: StringName = &"elapsed"
const _MEM_TARGET: StringName = &"target_dur"

var duration_sec: float = 0.5
var jitter_sec: float = 0.0
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_duration_sec: float = 0.5,
	p_title: String = "",
	p_jitter_sec: float = 0.0
) -> void:
	var resolved_title: String = p_title if not p_title.is_empty() else "Wait(%.2fs)" % p_duration_sec
	super._init(p_node_id, &"Wait", resolved_title, true)
	duration_sec = maxf(0.0, p_duration_sec)
	jitter_sec = maxf(0.0, p_jitter_sec)


func _on_tick(ctx: BTContext) -> int:
	if duration_sec <= 0.0 and jitter_sec <= 0.0:
		return BTStatus.Status.SUCCESS

	var target_dur: float = float(ctx.blackboard.get_node_mem(node_id, _MEM_TARGET, -1.0))
	if target_dur < 0.0:
		if jitter_sec > 0.0:
			target_dur = randf_range(maxf(0.0, duration_sec - jitter_sec), duration_sec + jitter_sec)
		else:
			target_dur = duration_sec
		ctx.blackboard.set_node_mem(node_id, _MEM_TARGET, target_dur)

	if target_dur <= 0.0:
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.SUCCESS

	var elapsed: float = float(ctx.blackboard.get_node_mem(node_id, _MEM_ELAPSED, 0.0)) + ctx.delta
	if elapsed >= target_dur:
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.SUCCESS
	ctx.blackboard.set_node_mem(node_id, _MEM_ELAPSED, elapsed)
	return BTStatus.Status.RUNNING
#endregion
