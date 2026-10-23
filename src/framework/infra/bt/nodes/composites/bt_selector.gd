class_name BTSelector
extends BTNode

## 优先级反应式选择组合节点（Reactive Priority Selector Composite Node）。[br]
##
## 从左到右（索引 `0 -> N-1`）依次评估子节点：[br]
## - 若某个子节点返回 `SUCCESS` 或 `RUNNING`，则立即返回该状态；[br]
## - [b]高优抢占自洁[/b]：若上一帧处于 `RUNNING` 的是低优先级子节点 `j`，而当前帧高优先级子节点 `i (i < j)` 抢占成功（返回 `SUCCESS` 或 `RUNNING`），自动对旧子节点 `j` 调用 `abort(ctx)` 清理残留状态。

#region Constants
const _MEM_RUNNING_IDX: StringName = &"running_idx"
#endregion


#region Execution
func _init(p_node_id: int = 0, p_title: String = "Selector") -> void:
	super._init(p_node_id, &"Selector", p_title, false)


func _on_tick(ctx: BTContext) -> int:
	var prev_running_idx: int = int(ctx.blackboard.get_node_mem(node_id, _MEM_RUNNING_IDX, -1))

	for idx in range(children.size()):
		var child: BTNode = children[idx]
		var status := child.tick(ctx)
		if status != BTStatus.Status.FAILURE:
			# 若高优先级分支抢占了之前正在运行的低优先级分支，自动打断旧分支
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
