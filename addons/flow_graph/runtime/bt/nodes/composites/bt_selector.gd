class_name BTSelector
extends BTNode

## 优先级选择组合节点（Priority Selector Composite Node）。[br]
##
## 从左到右（索引 `0 -> N-1`）依次评估子节点：[br]
## - 默认 `memory == false`（反应式抢占模式）：每帧从 0 评估，高优先级分支返回非 `FAILURE` 时自动 `abort` 旧低优先级运行分支；[br]
## - 当 `memory == true`（防打断记忆模式）：若上一帧某子分支处于 `RUNNING`，本帧直接从该分支续跑（跳过左侧高优分支抢占），直到该分支结束。

#region Constants & Config
const _MEM_RUNNING_IDX: StringName = &"running_idx"

var memory: bool = false
#endregion


#region Execution
func _init(p_node_id: int = 0, p_title: String = "Selector", p_memory: bool = false) -> void:
	super._init(p_node_id, &"Selector", p_title, false)
	memory = p_memory


func _on_tick(ctx: BTContext) -> int:
	var prev_running_idx: int = int(ctx.blackboard.get_node_mem(node_id, _MEM_RUNNING_IDX, -1))
	var start_idx: int = 0
	if memory and prev_running_idx >= 0 and prev_running_idx < children.size():
		start_idx = prev_running_idx

	for idx: int in range(start_idx, children.size()):
		var child: BTNode = children[idx]
		var status: int = child.tick(ctx)
		if status != BTStatus.Status.FAILURE:
			if prev_running_idx >= 0 and prev_running_idx != idx and prev_running_idx < children.size():
				children[prev_running_idx].abort(ctx)

			if status == BTStatus.Status.RUNNING:
				ctx.blackboard.set_node_mem(node_id, _MEM_RUNNING_IDX, idx)
			else:
				ctx.blackboard.clear_node_mem(node_id)
			return status

	if prev_running_idx >= 0 and prev_running_idx < children.size():
		children[prev_running_idx].abort(ctx)
	ctx.blackboard.clear_node_mem(node_id)
	return BTStatus.Status.FAILURE
#endregion
