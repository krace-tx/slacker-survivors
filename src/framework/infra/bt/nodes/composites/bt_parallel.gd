class_name BTParallel
extends BTNode

## 并行组合节点（Parallel Composite Node）。[br]
##
## 同帧评估全部子节点（如“边绕圈走位边瞄准玩家”）：[br]
## - 若 `require_all_success == true`，任意子节点返回 `FAILURE` 则立即整体 `FAILURE`，全部 `SUCCESS` 才返回 `SUCCESS`；[br]
## - 若 `require_all_success == false`，任意子节点返回 `SUCCESS` 则立即整体 `SUCCESS`。

#region Config
var require_all_success: bool = true
#endregion


#region Execution
func _init(p_node_id: int = 0, p_title: String = "Parallel", p_require_all: bool = true) -> void:
	super._init(p_node_id, &"Parallel", p_title, false)
	require_all_success = p_require_all


func _on_tick(ctx: BTContext) -> int:
	var success_count := 0
	var failure_count := 0

	for child: BTNode in children:
		var status := child.tick(ctx)
		if status == BTStatus.Status.SUCCESS:
			success_count += 1
			if not require_all_success:
				return BTStatus.Status.SUCCESS
		elif status == BTStatus.Status.FAILURE:
			failure_count += 1
			if require_all_success:
				return BTStatus.Status.FAILURE

	if require_all_success and success_count == children.size():
		return BTStatus.Status.SUCCESS
	if not require_all_success and failure_count == children.size():
		return BTStatus.Status.FAILURE
	return BTStatus.Status.RUNNING
#endregion
