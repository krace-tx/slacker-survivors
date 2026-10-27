class_name BTCooldown
extends BTNode

## 技能/分支冷却装饰节点（Cooldown Decorator Node）。[br]
##
## 当子节点执行完成并返回 `SUCCESS` 后，在 `ctx.blackboard` 的节点私有记忆区写入冷却解锁时间戳（支持 `jitter_sec` 随机防齐射抖动）。
## 在冷却期间再次被评估时直接短路返回 `FAILURE`（子节点处于 `RUNNING` 期间不锁断）。

#region Constants & Config
const _MEM_READY_AT: StringName = &"ready_at"
const _MEM_CHILD_RUNNING: StringName = &"child_running"

var cooldown_sec: float = 1.0
var jitter_sec: float = 0.0
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_cooldown_sec: float = 1.0,
	p_title: String = "",
	p_jitter_sec: float = 0.0
) -> void:
	var resolved_title: String = p_title if not p_title.is_empty() else "Cooldown(%.1fs)" % p_cooldown_sec
	super._init(p_node_id, &"Cooldown", resolved_title, false)
	cooldown_sec = maxf(0.0, p_cooldown_sec)
	jitter_sec = maxf(0.0, p_jitter_sec)


func _on_tick(ctx: BTContext) -> int:
	if children.is_empty():
		return BTStatus.Status.FAILURE

	var is_child_running: bool = bool(ctx.blackboard.get_node_mem(node_id, _MEM_CHILD_RUNNING, false))
	var ready_at: float = float(ctx.blackboard.get_node_mem(node_id, _MEM_READY_AT, -1.0))

	if not is_child_running and ready_at > 0.0 and ctx.elapsed_time < ready_at:
		return BTStatus.Status.FAILURE

	var status: int = children[0].tick(ctx)
	if status == BTStatus.Status.RUNNING:
		ctx.blackboard.set_node_mem(node_id, _MEM_CHILD_RUNNING, true)
	elif status == BTStatus.Status.SUCCESS:
		ctx.blackboard.set_node_mem(node_id, _MEM_CHILD_RUNNING, false)
		var actual_cd: float = cooldown_sec
		if jitter_sec > 0.0:
			actual_cd = randf_range(maxf(0.0, cooldown_sec - jitter_sec), cooldown_sec + jitter_sec)
		ctx.blackboard.set_node_mem(node_id, _MEM_READY_AT, ctx.elapsed_time + actual_cd)
	else:
		ctx.blackboard.set_node_mem(node_id, _MEM_CHILD_RUNNING, false)
	return status


func abort(ctx: BTContext) -> void:
	# 被打断时仅清理 child_running 与子树状态，保留已触发过的冷却解锁时间戳 ready_at
	var ready_at: float = float(ctx.blackboard.get_node_mem(node_id, _MEM_READY_AT, -1.0))
	super.abort(ctx)
	if ready_at > 0.0:
		ctx.blackboard.set_node_mem(node_id, _MEM_READY_AT, ready_at)
#endregion
