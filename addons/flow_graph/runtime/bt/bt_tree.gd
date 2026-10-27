class_name BTTree
extends RefCounted

## 享元可执行行为树容器（Flyweight Executable Behavior Tree）。[br]
##
## [b]核心设计：[/b][br]
## 1. 同时持有无状态运行根节点 [member root]（`BTNode`）与源抽象语法树 [member ast]（`BTGraphDef`）；[br]
## 2. 首帧自动按 `ast.blackboard_schema` 向实体黑板注入缺失默认值；[br]
## 3. 支持运行期 [method hot_reload_from_ir] 原位热更享元根节点，同屏百怪下一帧即刻按新 AI 逻辑评估。

#region Properties
var tree_id: StringName = &"bt_tree"
var root: BTNode = null
var ast: BTGraphDef = null

var _compiler: RefCounted = null
var _reload_epoch: int = 0
#endregion


#region Lifecycle & Execution
func _init(p_tree_id: StringName = &"bt_tree", p_root: BTNode = null, p_ast: BTGraphDef = null) -> void:
	tree_id = p_tree_id
	root = p_root
	ast = p_ast


## 内部由 `BTCompiler` / `BTBuilder` 绑定算子编译器句柄，支撑运行期无损热重载。
func bind_compiler(compiler: RefCounted) -> void:
	_compiler = compiler


## 对单个实体上下文执行一次行为树评估（自动尊重 `ctx.tick_interval` 分频节流与调试器单步挂起）。
func tick(ctx: BTContext, delta: float) -> int:
	if root == null or ctx == null:
		return BTStatus.Status.FAILURE

	if ast != null and not ast.blackboard_schema.is_empty():
		if ctx.tick_count == 0 or int(ctx.blackboard.get_node_mem(-1, &"__schema_epoch", -1)) != _reload_epoch:
			FlowBlackboardExpr.apply_schema_defaults(ast.blackboard_schema, ctx.blackboard)
			ctx.blackboard.set_node_mem(-1, &"__schema_epoch", _reload_epoch)

	var ctx_id: int = ctx.get_instance_id()
	if GraphDebugBridge.should_suspend_tick(ctx_id):
		return ctx.get_last_root_status()
	if not ctx.begin_tick(delta):
		return ctx.get_last_root_status()

	var forced_id: int = ctx.get_debug_forced_node_id()
	if forced_id > 0:
		if ctx.consume_debug_force_switched():
			root.abort(ctx)
		var path_out: Array[BTNode] = []
		if _find_node_path(root, forced_id, path_out) and not path_out.is_empty():
			var target_node: BTNode = path_out[path_out.size() - 1]
			var f_status: int = target_node.tick(ctx)
			for i: int in range(path_out.size() - 1):
				var anc: BTNode = path_out[i]
				ctx.record_node_status(anc.node_id, f_status, false, anc.title)
			if f_status != BTStatus.Status.RUNNING:
				ctx.clear_debug_force_node()
			ctx.set_last_root_status(f_status)
			GraphDebugBridge.push_frame(ctx_id, true)
			return f_status
		ctx.clear_debug_force_node()

	var status: int = root.tick(ctx)
	ctx.set_last_root_status(status)
	GraphDebugBridge.push_frame(ctx_id)
	return status


## 从标准图中间表示字典热重载整棵享元行为树（校验或算子缺失时安全报错，不破坏原运行树）。
func hot_reload_from_ir(ir: Dictionary) -> FlowGraphResult:
	var probe_def := BTGraphDef.new()
	probe_def.apply_flow_graph_ir(ir)

	var comp: Variant = _compiler
	if comp == null or not comp.has_method(&"compile"):
		return FlowGraphResult.err_code("BT.MissingCompiler", "BTTree '%s' has no bound BTCompiler for hot-reload." % String(tree_id))

	var comp_res: FlowGraphResult = comp.call(&"compile", probe_def, true) as FlowGraphResult
	if comp_res == null or comp_res.is_err():
		return comp_res if comp_res != null else FlowGraphResult.err_code("BT.HotReloadFailed", "Compiler returned null.")

	var rebuilt_tree: BTTree = comp_res.value as BTTree
	if ast == null:
		ast = probe_def
	else:
		ast.apply_flow_graph_ir(ir)
		if ast.root != null and comp.has_method(&"_auto_layout_ast_if_needed"):
			comp.call(&"_auto_layout_ast_if_needed", ast.root, 0, {"row": 0})

	root = rebuilt_tree.root
	tree_id = ast.tree_id
	_reload_epoch += 1
	return FlowGraphResult.ok(self)


static func _find_node_path(cur: BTNode, target_id: int, path_out: Array[BTNode]) -> bool:
	if cur == null:
		return false
	path_out.append(cur)
	if cur.node_id == target_id:
		return true
	for ch: BTNode in cur.children:
		if _find_node_path(ch, target_id, path_out):
			return true
	path_out.pop_back()
	return false


## 强制打断并清空指定实体上下文在当前行为树中的所有跨帧运行状态。
func abort(ctx: BTContext) -> void:
	if root == null or ctx == null:
		return
	root.abort(ctx)
	ctx.set_last_root_status(BTStatus.Status.FAILURE)


## 获取与本运行树一一对应的抽象语法树（AST）定义。
func get_ast() -> BTGraphDef:
	return ast


## 释放节点拓扑、编译器与叶节点闭包回调引用，打破潜在的宿主 RefCounted 环路。
func clear() -> void:
	if root != null:
		root.clear()
		root = null
	ast = null
	_compiler = null
#endregion
