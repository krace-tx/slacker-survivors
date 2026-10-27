class_name BTNode
extends RefCounted

## 享元行为树无状态运行节点基类（Stateless Flyweight Behavior Tree Node Base）。[br]
##
## [b]享元铁律（Flyweight Invariant）：[/b][br]
## 本类及所有子类实例严禁在成员变量中保存任何单实体运行期可变状态（如计时器、当前执行子索引）；
## 跨帧状态必须通过 `ctx.blackboard.get_node_mem(node_id, ...)` 读写，保证同一棵树实例可被任意数量实体共享。

#region Readonly Topology Properties
var node_id: int = 0
var node_type: StringName = &"Node"
var title: String = ""
var children: Array[BTNode] = []
var is_leaf: bool = false
#endregion


#region Lifecycle & Execution
func _init(p_node_id: int = 0, p_node_type: StringName = &"Node", p_title: String = "", p_is_leaf: bool = false) -> void:
	node_id = p_node_id
	node_type = p_node_type
	title = p_title if not p_title.is_empty() else String(p_node_type)
	is_leaf = p_is_leaf


## 添加一个子节点并返回自身（支持链式组装）。
func add_child_node(child: BTNode) -> BTNode:
	if child != null:
		children.append(child)
	return self


## 执行单步评估并自动向 [BTContext] 写入可视化遥测轨迹。
func tick(ctx: BTContext) -> int:
	var status := _on_tick(ctx)
	ctx.record_node_status(node_id, status, is_leaf and node_type != &"Condition", title)
	return status


## 当正在运行的分支被高优先级分支抢占或外部强制重置时调用，递归清理本节点与子树的记忆槽。
func abort(ctx: BTContext) -> void:
	_on_abort(ctx)
	ctx.blackboard.clear_node_mem(node_id)
	for ch: BTNode in children:
		if ch != null:
			ch.abort(ctx)


## 子类重写：具体节点评估逻辑。
func _on_tick(_ctx: BTContext) -> int:
	return BTStatus.Status.FAILURE


## 子类可选重写：被打断时的清理钩子。
func _on_abort(_ctx: BTContext) -> void:
	pass


## 递归释放子节点与闭包回调引用，打破潜在的宿主 RefCounted 环路。
func clear() -> void:
	for ch: BTNode in children:
		if ch != null:
			ch.clear()
	children.clear()
#endregion
