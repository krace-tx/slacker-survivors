class_name BTBuilder
extends RefCounted

## 行为树流式 DSL 构建器（Fluent Behavior Tree Builder & AST Generator）。[br]
##
## [b]核心价值（Code-as-Blueprint 同构）：[/b][br]
## 通过链式调用直观拼装行为树，在生成高性能享元 [BTTree] 的**同时**，自动构建出一模一样的 [BTGraphDef] 抽象语法树（含自动层级坐标）与 [BTCompiler] 算子表。
## 既支持直接传入匿名函数 `Callable`，也支持导出为 JSON / `.tres` 或交由可视化蓝图面板实时绘制。

#region Private State
var _tree_id: StringName = &"bt_tree"
var _next_node_id: int = 1
var _node_stack: Array[BTNode] = []
var _ast_stack: Array[BTNodeDef] = []
var _root_node: BTNode = null
var _root_ast: BTNodeDef = null
var _compiler: BTCompiler = BTCompiler.new()
#endregion


#region Entry Factory
static func create(tree_id: StringName = &"bt_tree") -> BTBuilder:
	var b := BTBuilder.new()
	b._tree_id = tree_id
	return b
#endregion


#region Composite Builders (Must pair with .end())
## 压入一个优先级选择节点（[BTSelector]）。后续添加的节点将成为其子节点，直到调用 [method end]。
func selector(title: String = "Selector") -> BTBuilder:
	var nid := _alloc_id()
	var rt := BTSelector.new(nid, title)
	var ast_def := BTNodeDef.create(nid, &"Selector", title)
	_push_container(rt, ast_def)
	return self


## 压入一个顺序执行节点（[BTSequence]）。后续添加的节点将成为其子节点，直到调用 [method end]。
func sequence(title: String = "Sequence", reactive: bool = false) -> BTBuilder:
	var nid := _alloc_id()
	var rt := BTSequence.new(nid, title, reactive)
	var ast_def := BTNodeDef.create(nid, &"Sequence", title, {"reactive": reactive})
	_push_container(rt, ast_def)
	return self


## 压入一个并行执行节点（[BTParallel]）。后续添加的节点将成为其子节点，直到调用 [method end]。
func parallel(title: String = "Parallel", require_all_success: bool = true) -> BTBuilder:
	var nid := _alloc_id()
	var rt := BTParallel.new(nid, title, require_all_success)
	var ast_def := BTNodeDef.create(nid, &"Parallel", title, {"require_all_success": require_all_success})
	_push_container(rt, ast_def)
	return self
#endregion


#region Decorator Builders (Must pair with .end())
## 压入一个冷却装饰节点（[BTCooldown]）。需包含 1 个子节点并调用 [method end]。
func cooldown(cooldown_sec: float, title: String = "") -> BTBuilder:
	var nid := _alloc_id()
	var resolved_title := title if not title.is_empty() else "Cooldown(%.1fs)" % cooldown_sec
	var rt := BTCooldown.new(nid, cooldown_sec, resolved_title)
	var ast_def := BTNodeDef.create(nid, &"Cooldown", resolved_title, {"cooldown_sec": cooldown_sec})
	_push_container(rt, ast_def)
	return self


## 压入一个取反装饰节点（[BTInverter]）。需包含 1 个子节点并调用 [method end]。
func inverter(title: String = "Inverter") -> BTBuilder:
	var nid := _alloc_id()
	var rt := BTInverter.new(nid, title)
	var ast_def := BTNodeDef.create(nid, &"Inverter", title)
	_push_container(rt, ast_def)
	return self
#endregion


#region Leaf Builders (Auto-attached to current parent)
## 添加一个闭包条件叶节点（`predicate: Callable(ctx: BTContext) -> bool`）。
func condition(title: String, predicate: Callable, condition_key: StringName = &"") -> BTBuilder:
	var nid := _alloc_id()
	var c_key := condition_key if not condition_key.is_empty() else StringName("cond_%d" % nid)
	_compiler.register_condition(c_key, predicate)
	var rt := BTCondition.new(nid, title, predicate)
	var ast_def := BTNodeDef.create(nid, &"Condition", title, {"condition_key": String(c_key)})
	_attach_leaf(rt, ast_def)
	return self


## 添加一个声明式黑板键值比较条件叶节点（支持无代码 JSON/AST 蓝图完整的序列化与重编译）。
func bb_compare(title: String, bb_key: StringName, op: StringName, compare_value: Variant) -> BTBuilder:
	var nid := _alloc_id()
	var rt := BTCondition.new(nid, title, Callable(), bb_key, op, compare_value)
	var ast_def := BTNodeDef.create(nid, &"Condition", title, {
		"bb_key": String(bb_key),
		"op": String(op),
		"value": compare_value,
	})
	_attach_leaf(rt, ast_def)
	return self


## 添加一个动作叶节点（`callable: Callable(ctx: BTContext) -> int|bool`）。
func action(title: String, callable: Callable, action_key: StringName = &"", params: Dictionary = {}) -> BTBuilder:
	var nid := _alloc_id()
	var a_key := action_key if not action_key.is_empty() else StringName("act_%d" % nid)
	_compiler.register_action(a_key, callable)
	var merged_params := params.duplicate(true)
	merged_params["action_key"] = String(a_key)
	var rt := BTAction.new(nid, title, callable, a_key, merged_params)
	var ast_def := BTNodeDef.create(nid, &"Action", title, merged_params)
	_attach_leaf(rt, ast_def)
	return self


## 添加一个定时等待叶节点（[BTWait]）。
func wait(duration_sec: float, title: String = "") -> BTBuilder:
	var nid := _alloc_id()
	var resolved_title := title if not title.is_empty() else "Wait(%.2fs)" % duration_sec
	var rt := BTWait.new(nid, duration_sec, resolved_title)
	var ast_def := BTNodeDef.create(nid, &"Wait", resolved_title, {"duration_sec": duration_sec})
	_attach_leaf(rt, ast_def)
	return self


## 结束当前组合节点或装饰节点的子树构建，退回上一层父节点。
func end() -> BTBuilder:
	if not _node_stack.is_empty():
		_node_stack.pop_back()
	if not _ast_stack.is_empty():
		_ast_stack.pop_back()
	return self
#endregion


#region Build & Compiler Export
## 完成构建并返回享元 [BTTree]（内含同步生成的 [BTGraphDef] AST）。
func build() -> BTTree:
	var graph_def := BTGraphDef.new()
	graph_def.tree_id = _tree_id
	graph_def.root = _root_ast
	BTCompiler._auto_layout_ast_if_needed(graph_def.root, 0, {"row": 0})
	return BTTree.new(_tree_id, _root_node, graph_def)


## 获取已自动注册了本树所有动作与条件的 [BTCompiler]（可用于验证将导出的 AST JSON 重新编译为新树）。
func get_compiler() -> BTCompiler:
	return _compiler


func _alloc_id() -> int:
	var id := _next_node_id
	_next_node_id += 1
	return id


func _push_container(rt: BTNode, ast_def: BTNodeDef) -> void:
	_attach_leaf(rt, ast_def)
	_node_stack.append(rt)
	_ast_stack.append(ast_def)


func _attach_leaf(rt: BTNode, ast_def: BTNodeDef) -> void:
	if _root_node == null:
		_root_node = rt
		_root_ast = ast_def
	else:
		if not _node_stack.is_empty():
			var parent_rt: BTNode = _node_stack[_node_stack.size() - 1]
			parent_rt.add_child_node(rt)
		if not _ast_stack.is_empty():
			var parent_ast: BTNodeDef = _ast_stack[_ast_stack.size() - 1]
			parent_ast.children.append(ast_def)
#endregion
