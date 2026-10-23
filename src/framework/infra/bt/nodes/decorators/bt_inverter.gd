class_name BTInverter
extends BTNode

## 逻辑取反装饰节点（Inverter Decorator Node）。[br]
##
## 将子节点的 `SUCCESS` 翻转为 `FAILURE`、`FAILURE` 翻转为 `SUCCESS`，`RUNNING` 保持不变。

#region Execution
func _init(p_node_id: int = 0, p_title: String = "Inverter") -> void:
	super._init(p_node_id, &"Inverter", p_title, false)


func _on_tick(ctx: BTContext) -> int:
	if children.is_empty():
		return BTStatus.Status.FAILURE
	var child_status := children[0].tick(ctx)
	return BTStatus.invert(child_status)
#endregion
