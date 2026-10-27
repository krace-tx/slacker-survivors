class_name BTForceStatus
extends BTNode

## 强制完成态覆写装饰节点（ForceSuccess / ForceFailure Decorator Node）。[br]
##
## 子节点返回 `RUNNING` 时原样透传 `RUNNING`；一旦子节点完成（`SUCCESS` 或 `FAILURE`），强制返回 `SUCCESS` 或 `FAILURE`。

#region Config
var force_success: bool = true
#endregion


#region Execution
func _init(p_node_id: int = 0, p_force_success: bool = true, p_title: String = "") -> void:
	var ntype: StringName = &"ForceSuccess" if p_force_success else &"ForceFailure"
	var resolved_title: String = p_title if not p_title.is_empty() else String(ntype)
	super._init(p_node_id, ntype, resolved_title, false)
	force_success = p_force_success


func _on_tick(ctx: BTContext) -> int:
	var target_status: int = BTStatus.Status.SUCCESS if force_success else BTStatus.Status.FAILURE
	if children.is_empty():
		return target_status
	var child_status: int = children[0].tick(ctx)
	if child_status == BTStatus.Status.RUNNING:
		return BTStatus.Status.RUNNING
	return target_status
#endregion
