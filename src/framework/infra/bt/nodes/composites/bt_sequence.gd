class_name BTSequence
extends BTNode

## 顺序执行组合节点（Sequence Composite Node）。[br]
##
## 按顺序执行子节点：[br]
## - 当 `reactive == false`（默认记忆模式，适用于连招序列：`前摇 -> 出刀 -> 后摇休息`）时，上一帧返回 `RUNNING` 的子节点在下一帧直接从该子节点继续推进；[br]
## - 当 `reactive == true`（反应式守卫模式）时，每帧从第 0 个子节点重新校验前置条件，若前置条件变为 `FAILURE`，立即 `abort` 后续正在运行的动作子节点。

#region Constants & Config
const _MEM_RUNNING_IDX: StringName = &"running_idx"

var reactive: bool = false
#endregion


#region Execution
func _init(p_node_id: int = 0, p_title: String = "Sequence", p_reactive: bool = false) -> void:
	super._init(p_node_id, &"Sequence", p_title, false)
	reactive = p_reactive


func _on_tick(ctx: BTContext) -> int:
	var prev_running_idx: int = int(ctx.blackboard.get_node_mem(node_id, _MEM_RUNNING_IDX, 0))
	var start_idx := 0 if reactive else maxi(0, prev_running_idx)

	for idx in range(start_idx, children.size()):
		var child: BTNode = children[idx]
		var status := child.tick(ctx)
		if status == BTStatus.Status.RUNNING:
			if reactive and prev_running_idx > idx and prev_running_idx < children.size():
				children[prev_running_idx].abort(ctx)
			ctx.blackboard.set_node_mem(node_id, _MEM_RUNNING_IDX, idx)
			return BTStatus.Status.RUNNING
		if status == BTStatus.Status.FAILURE:
			if prev_running_idx >= 0 and prev_running_idx != idx and prev_running_idx < children.size():
				children[prev_running_idx].abort(ctx)
			ctx.blackboard.clear_node_mem(node_id)
			return BTStatus.Status.FAILURE

	ctx.blackboard.clear_node_mem(node_id)
	return BTStatus.Status.SUCCESS
#endregion
