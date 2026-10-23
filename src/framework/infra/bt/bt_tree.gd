class_name BTTree
extends RefCounted

## 享元可执行行为树容器（Flyweight Executable Behavior Tree）。[br]
##
## [b]核心设计：[/b][br]
## 1. 同时持有无状态运行根节点 [member root]（`BTNode`）与源抽象语法树 [member ast]（`BTGraphDef`）；[br]
## 2. 任意数量的实体均可将各自的 [BTContext] 传入同一个 [BTTree] 的 [method tick] 方法并发求值；[br]
## 3. 任何可视化蓝图或调试面板只需读取 [method get_ast] 并配合某个实体的 [BTContext]，即可实时渲染该实体的行为树执行流。

#region Properties
var tree_id: StringName = &"bt_tree"
var root: BTNode = null
var ast: BTGraphDef = null
#endregion


#region Lifecycle & Execution
func _init(p_tree_id: StringName = &"bt_tree", p_root: BTNode = null, p_ast: BTGraphDef = null) -> void:
	tree_id = p_tree_id
	root = p_root
	ast = p_ast


## 对单个实体上下文执行一次行为树评估（自动尊重 `ctx.tick_interval` 分频节流）。
func tick(ctx: BTContext, delta: float) -> int:
	if root == null or ctx == null:
		return BTStatus.Status.FAILURE
	if not ctx.begin_tick(delta):
		return ctx.get_last_root_status()
	var status := root.tick(ctx)
	ctx.set_last_root_status(status)
	return status


## 强制打断并清空指定实体上下文在当前行为树中的所有跨帧运行状态。
func abort(ctx: BTContext) -> void:
	if root == null or ctx == null:
		return
	root.abort(ctx)
	ctx.set_last_root_status(BTStatus.Status.FAILURE)


## 获取与本运行树一一对应的抽象语法树（AST）定义。
func get_ast() -> BTGraphDef:
	return ast
#endregion
