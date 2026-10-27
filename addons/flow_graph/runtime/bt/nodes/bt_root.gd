@tool
class_name BTRoot
extends BTNode

## 行为树唯一根入口节点（Behavior Tree Entry Root Node）。[br]
##
## 作为行为树顶层显式入口，仅挂载唯一子节点并透传每帧评估结果，无实例可变状态，天然满足享元契约。

#region Execution
func _init(p_node_id: int = 0, p_title: String = "Root") -> void:
	super._init(p_node_id, &"Root", p_title, false)


func _on_tick(ctx: BTContext) -> int:
	if children.is_empty():
		return BTStatus.Status.FAILURE
	return children[0].tick(ctx)
#endregion
