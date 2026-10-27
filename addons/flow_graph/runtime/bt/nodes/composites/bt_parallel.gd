@tool
class_name BTParallel
extends BTNode

## 并行组合节点（Parallel Composite Node）。[br]
##
## 同帧评估全部子节点（如“边绕圈走位边瞄准玩家”）：[br]
## - 若 `require_all_success == true`，任意子节点返回 `FAILURE` 则立即整体 `FAILURE`（并自动 `abort` 其余运行中兄弟分支），全部 `SUCCESS` 才返回 `SUCCESS`；[br]
## - 若 `require_all_success == false`，任意子节点返回 `SUCCESS` 则立即整体 `SUCCESS`（并自动 `abort` 其余运行中兄弟分支）。

#region Constants & Config
const _MEM_RUNNING_INDICES: StringName = &"running_indices"

var require_all_success: bool = true
#endregion


#region Execution
func _init(p_node_id: int = 0, p_title: String = "Parallel", p_require_all: bool = true) -> void:
	super._init(p_node_id, &"Parallel", p_title, false)
	require_all_success = p_require_all


func _on_tick(ctx: BTContext) -> int:
	var count: int = children.size()
	if count == 0:
		return BTStatus.Status.FAILURE

	var prev_running: PackedInt32Array = ctx.blackboard.get_node_mem(
		node_id, _MEM_RUNNING_INDICES, PackedInt32Array()
	) as PackedInt32Array
	var cur_running := PackedInt32Array()
	var success_count: int = 0
	var failure_count: int = 0

	for i: int in range(count):
		var status: int = children[i].tick(ctx)
		if status == BTStatus.Status.SUCCESS:
			success_count += 1
			if not require_all_success:
				_abort_remaining_siblings(ctx, i, cur_running, prev_running, count)
				ctx.blackboard.clear_node_mem(node_id)
				return BTStatus.Status.SUCCESS
		elif status == BTStatus.Status.FAILURE:
			failure_count += 1
			if require_all_success:
				_abort_remaining_siblings(ctx, i, cur_running, prev_running, count)
				ctx.blackboard.clear_node_mem(node_id)
				return BTStatus.Status.FAILURE
		else:
			cur_running.append(i)

	if require_all_success and success_count == count:
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.SUCCESS
	if not require_all_success and failure_count == count:
		ctx.blackboard.clear_node_mem(node_id)
		return BTStatus.Status.FAILURE

	ctx.blackboard.set_node_mem(node_id, _MEM_RUNNING_INDICES, cur_running)
	return BTStatus.Status.RUNNING


func _abort_remaining_siblings(
	ctx: BTContext,
	eval_up_to: int,
	cur_running: PackedInt32Array,
	prev_running: PackedInt32Array,
	count: int
) -> void:
	for r_idx: int in cur_running:
		if r_idx >= 0 and r_idx < count:
			children[r_idx].abort(ctx)
	for p_idx: int in prev_running:
		if p_idx > eval_up_to and p_idx < count:
			children[p_idx].abort(ctx)
#endregion
