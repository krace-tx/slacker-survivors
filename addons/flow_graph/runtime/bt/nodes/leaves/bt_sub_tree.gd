@tool
class_name BTSubTree
extends BTNode

## 外部公共行为树子图挂载叶节点（SubTree Reference Leaf Node）。[br]
##
## [b]享元命名空间隔离契约：[/b][br]
## 由 [BTCompiler] 加载 `sub_graph_path` 并对子树内全部节点 ID 施加无冲突命名空间偏移后编译注入 `sub_root`；
## 同一棵父树多处挂载同一份 `.tres` 子树时，各自在 `ctx.blackboard` 中拥有完全隔离的节点记忆槽，且子图 `blackboard_schema` 随树纪元自动同步。

#region Config
const _MEM_SCHEMA_EPOCH: StringName = &"schema_epoch"

var sub_graph_path: String = ""
var sub_root: BTNode = null
var sub_schema: Array[Dictionary] = []
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_title: String = "SubTree",
	p_sub_root: BTNode = null,
	p_sub_graph_path: String = "",
	p_sub_schema: Array[Dictionary] = []
) -> void:
	super._init(p_node_id, &"SubTree", p_title, true)
	sub_root = p_sub_root
	sub_graph_path = p_sub_graph_path
	sub_schema = p_sub_schema.duplicate(true)


func _on_tick(ctx: BTContext) -> int:
	if sub_root == null:
		return BTStatus.Status.FAILURE
	if not sub_schema.is_empty():
		var cur_epoch: int = ctx.get_tree_epoch()
		if int(ctx.blackboard.get_node_mem(node_id, _MEM_SCHEMA_EPOCH, -2)) != cur_epoch:
			FlowBlackboardExpr.apply_schema_defaults(sub_schema, ctx.blackboard)
			ctx.blackboard.set_node_mem(node_id, _MEM_SCHEMA_EPOCH, cur_epoch)
	return sub_root.tick(ctx)


func abort(ctx: BTContext) -> void:
	var saved_epoch: Variant = ctx.blackboard.get_node_mem(node_id, _MEM_SCHEMA_EPOCH, null)
	super.abort(ctx)
	if saved_epoch != null:
		ctx.blackboard.set_node_mem(node_id, _MEM_SCHEMA_EPOCH, saved_epoch)


func _on_abort(ctx: BTContext) -> void:
	if sub_root != null:
		sub_root.abort(ctx)


func clear() -> void:
	if sub_root != null:
		sub_root.clear()
		sub_root = null
	sub_schema.clear()
	super.clear()
#endregion
