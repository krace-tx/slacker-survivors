class_name BTGraphDef
extends Resource

## 整棵行为树的抽象语法树资源定义（Behavior Tree Graph AST Resource）。[br]
##
## 支持编译期结构校验 [method validate]、节点总数统计以及与纯 `Dictionary` / JSON 的双向无损转换。

#region Exports
## 行为树唯一标识（如 `&"boss_ashen_warden_bt"`）。
@export var tree_id: StringName = &"bt_graph"

## 根节点 AST 描述子。
@export var root: BTNodeDef = null
#endregion


#region Validation & Traversal
## 校验整棵行为树 AST 的结构合法性（非空根、唯一 `node_id`、组合/装饰节点子数量合法）。
func validate() -> Result:
	if root == null:
		return Result.err_code("BT.EmptyGraph", "BTGraphDef '%s' has no root node." % String(tree_id))
	var seen_ids: Dictionary = {}
	return _validate_node_recursive(root, seen_ids)


## 统计 AST 中的节点总数。
func count_nodes() -> int:
	return _count_recursive(root)


## 将整棵 AST 按前序遍历展平为数组（供可视化蓝图面板一键遍历绘制）。
func flatten_nodes() -> Array[BTNodeDef]:
	var out: Array[BTNodeDef] = []
	_flatten_recursive(root, out)
	return out


func _validate_node_recursive(node: BTNodeDef, seen_ids: Dictionary) -> Result:
	if node.node_type.is_empty():
		return Result.err_code("BT.InvalidNodeType", "Node %d has empty node_type." % node.node_id)
	if seen_ids.has(node.node_id):
		return Result.err_code("BT.DuplicateNodeId", "Duplicate node_id %d in BTGraphDef." % node.node_id)
	seen_ids[node.node_id] = true

	var is_composite := node.node_type in [&"Selector", &"Sequence", &"Parallel"]
	var is_decorator := node.node_type in [&"Inverter", &"Cooldown"]
	if is_composite and node.children.is_empty():
		return Result.err_code(
			"BT.EmptyComposite",
			"Composite node '%s' (id=%d) must have at least 1 child." % [node.title, node.node_id]
		)
	if is_decorator and node.children.size() != 1:
		return Result.err_code(
			"BT.InvalidDecoratorChildCount",
			"Decorator node '%s' (id=%d) must have exactly 1 child." % [node.title, node.node_id]
		)

	for ch_var: Variant in node.children:
		var ch := ch_var as BTNodeDef
		if ch == null:
			return Result.err_code("BT.NullChild", "Node '%s' contains a null child." % node.title)
		var res := _validate_node_recursive(ch, seen_ids)
		if res.is_err():
			return res
	return Result.ok(self)


func _count_recursive(node: BTNodeDef) -> int:
	if node == null:
		return 0
	var total := 1
	for ch_var: Variant in node.children:
		total += _count_recursive(ch_var as BTNodeDef)
	return total


func _flatten_recursive(node: BTNodeDef, out: Array[BTNodeDef]) -> void:
	if node == null:
		return
	out.append(node)
	for ch_var: Variant in node.children:
		_flatten_recursive(ch_var as BTNodeDef, out)
#endregion


#region Serialization
func to_dict() -> Dictionary:
	return {
		"tree_id": String(tree_id),
		"root": root.to_dict() if root != null else {},
	}


static func from_dict(data: Dictionary) -> BTGraphDef:
	var graph := BTGraphDef.new()
	graph.tree_id = StringName(str(data.get("tree_id", "bt_graph")))
	var raw_root: Variant = data.get("root", null)
	if raw_root is Dictionary and not (raw_root as Dictionary).is_empty():
		graph.root = BTNodeDef.from_dict(raw_root as Dictionary)
	return graph
#endregion
