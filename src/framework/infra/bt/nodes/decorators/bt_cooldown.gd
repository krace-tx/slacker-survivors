class_name BTCooldown
extends BTNode

## 技能/分支冷却装饰节点（Cooldown Decorator Node）。[br]
##
## 当子节点执行完成并返回 `SUCCESS` 后，在 `ctx.blackboard` 的节点私有记忆区写入冷却解锁时间戳（`ctx.elapsed_time + cooldown_sec`）。
## 在冷却期间再次被评估时直接短路返回 `FAILURE`（子节点处于 `RUNNING` 期间不锁断）。

#region Constants & Config
const _MEM_READY_AT: StringName = &"ready_at"
const _MEM_CHILD_RUNNING: StringName = &"child_running"

var cooldown_sec: float = 1.0
#endregion


#region Execution
func _init(p_node_id: int = 0, p_cooldown_sec: float = 1.0, p_title: String = "") -> void:
	var resolved_title := p_title if not p_title.is_empty() else "Cooldown(%.1fs)" % p_cooldown_sec
	super._init(p_node_id, &"Cooldown", resolved_title, false)
	cooldown_sec = maxf(0.0, p_cooldown_sec)


func _on_tick(ctx: BTContext) -> int:
	if children.is_empty():
		return BTStatus.Status.FAILURE

	var is_child_running := bool(ctx.blackboard.get_node_mem(node_id, _MEM_CHILD_RUNNING, false))
	var ready_at := float(ctx.blackboard.get_node_mem(node_id, _MEM_READY_AT, -1.0))

	if not is_child_running and ready_at > 0.0 and ctx.elapsed_time < ready_at:
		return BTStatus.Status.FAILURE

	var status := children[0].tick(ctx)
	if status == BTStatus.Status.RUNNING:
		ctx.blackboard.set_node_mem(node_id, _MEM_CHILD_RUNNING, true)
	elif status == BTStatus.Status.SUCCESS:
		ctx.blackboard.set_node_mem(node_id, _MEM_CHILD_RUNNING, false)
		ctx.blackboard.set_node_mem(node_id, _MEM_READY_AT, ctx.elapsed_time + cooldown_sec)
	else:
		ctx.blackboard.set_node_mem(node_id, _MEM_CHILD_RUNNING, false)
	return status


func _on_abort(ctx: BTContext) -> void:
	# 注意：被打断时仅清除 child_running 标记，保留已触发过的冷却时间戳 ready_at！
	var ready_at := float(ctx.blackboard.get_node_mem(node_id, _MEM_READY_AT, -1.0))
	ctx.blackboard.clear_node_mem(node_id)
	if ready_at > 0.0:
		ctx.blackboard.set_node_mem(node_id, _MEM_READY_AT, ready_at)
#endregion
