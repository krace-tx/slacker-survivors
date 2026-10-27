class_name BTBuilder
extends RefCounted

## 行为树流式 DSL 构建器（Fluent Behavior Tree Builder & AST Generator）。[br]
##
## [b]核心价值（Code-as-Blueprint 同构）：[/b][br]
## 通过链式调用直观拼装行为树，在生成高性能享元 [BTTree] 的**同时**，自动构建出一模一样的 [BTGraphDef] 抽象语法树与 [BTCompiler] 算子表。

#region Private State
var _tree_id: StringName = &"bt_tree"
var _next_node_id: int = 1
var _node_stack: Array[BTNode] = []
var _ast_stack: Array[BTNodeDef] = []
var _root_node: BTNode = null
var _root_ast: BTNodeDef = null
var _compiler: BTCompiler = BTCompiler.new()
var _blackboard_schema: Array[Dictionary] = []
#endregion


#region Entry Factory & Schema
static func create(tree_id: StringName = &"bt_tree") -> BTBuilder:
	var b := BTBuilder.new()
	b._tree_id = tree_id
	return b


func declare_var(key: String, type_name: String, default_val: Variant) -> BTBuilder:
	_blackboard_schema.append({"key": key, "type": type_name, "default": default_val})
	return self
#endregion


#region Composite Builders (Must pair with .end())
## 压入一个优先级选择节点（[BTSelector]，支持 `memory` 防打断记忆模式）。
func selector(title: String = "Selector", memory: bool = false) -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTSelector.new(nid, title, memory)
	var params: Dictionary = {"memory": true} if memory else {}
	var ast_def := BTNodeDef.create(nid, &"Selector", title, params)
	_push_container(rt, ast_def)
	return self


## 压入一个加权随机选择节点（[BTWeightedSelector]）。
func weighted_selector(weights: Array[float] = [], title: String = "WeightedSelector") -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTWeightedSelector.new(nid, title, weights)
	var params: Dictionary = {"weights": weights.duplicate()} if not weights.is_empty() else {}
	var ast_def := BTNodeDef.create(nid, &"WeightedSelector", title, params)
	_push_container(rt, ast_def)
	return self


## 压入一个顺序执行节点（[BTSequence]）。
func sequence(title: String = "Sequence", reactive: bool = false) -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTSequence.new(nid, title, reactive)
	var ast_def := BTNodeDef.create(nid, &"Sequence", title, {"reactive": reactive})
	_push_container(rt, ast_def)
	return self


## 压入一个并行执行节点（[BTParallel]）。
func parallel(title: String = "Parallel", require_all_success: bool = true) -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTParallel.new(nid, title, require_all_success)
	var ast_def := BTNodeDef.create(nid, &"Parallel", title, {"require_all_success": require_all_success})
	_push_container(rt, ast_def)
	return self
#endregion


#region Decorator Builders (Must pair with .end())
## 压入一个冷却装饰节点（[BTCooldown]，支持 `jitter_sec` 随机防齐射抖动）。
func cooldown(cooldown_sec: float, title: String = "", jitter_sec: float = 0.0) -> BTBuilder:
	var nid: int = _alloc_id()
	var resolved_title: String = title if not title.is_empty() else "Cooldown(%.1fs)" % cooldown_sec
	var rt := BTCooldown.new(nid, cooldown_sec, resolved_title, jitter_sec)
	var params: Dictionary = {"cooldown_sec": cooldown_sec}
	if jitter_sec > 0.0:
		params["jitter_sec"] = jitter_sec
	var ast_def := BTNodeDef.create(nid, &"Cooldown", resolved_title, params)
	_push_container(rt, ast_def)
	return self


## 压入一个取反装饰节点（[BTInverter]）。
func inverter(title: String = "Inverter") -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTInverter.new(nid, title)
	var ast_def := BTNodeDef.create(nid, &"Inverter", title)
	_push_container(rt, ast_def)
	return self


## 压入一个循环装饰节点（[BTRepeater]）。
func repeater(repeat_count: int = 3, abort_on_failure: bool = true, title: String = "") -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTRepeater.new(nid, repeat_count, abort_on_failure, title)
	var ast_def := BTNodeDef.create(nid, &"Repeater", rt.title, {
		"repeat_count": repeat_count,
		"abort_on_failure": abort_on_failure,
	})
	_push_container(rt, ast_def)
	return self


## 压入一个超时限制装饰节点（[BTTimeLimit]）。
func time_limit(timeout_sec: float = 3.0, title: String = "") -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTTimeLimit.new(nid, timeout_sec, title)
	var ast_def := BTNodeDef.create(nid, &"TimeLimit", rt.title, {"timeout_sec": timeout_sec})
	_push_container(rt, ast_def)
	return self


## 压入一个强制成功装饰节点（[BTForceStatus]）。
func force_success(title: String = "ForceSuccess") -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTForceStatus.new(nid, true, title)
	var ast_def := BTNodeDef.create(nid, &"ForceSuccess", title)
	_push_container(rt, ast_def)
	return self


## 压入一个强制失败装饰节点（[BTForceStatus]）。
func force_failure(title: String = "ForceFailure") -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTForceStatus.new(nid, false, title)
	var ast_def := BTNodeDef.create(nid, &"ForceFailure", title)
	_push_container(rt, ast_def)
	return self


## 压入一个周期黑板刷新服务节点（[BTService]）。
func service(
	service_key: StringName,
	interval_sec: float = 0.25,
	jitter_sec: float = 0.05,
	callable: Callable = Callable(),
	title: String = ""
) -> BTBuilder:
	var nid: int = _alloc_id()
	if not service_key.is_empty() and callable.is_valid():
		_compiler.register_service(service_key, callable)
	var resolved_title: String = title if not title.is_empty() else ("Service(%s)" % String(service_key))
	var params: Dictionary = {
		"service_key": String(service_key),
		"interval_sec": interval_sec,
		"jitter_sec": jitter_sec,
	}
	var rt := BTService.new(nid, callable, interval_sec, jitter_sec, resolved_title, service_key, params)
	var ast_def := BTNodeDef.create(nid, &"Service", resolved_title, params)
	_push_container(rt, ast_def)
	return self
#endregion


#region Leaf Builders (Auto-attached to current parent)
## 添加一个闭包条件叶节点（`predicate: Callable(ctx: BTContext) -> bool`）。
func condition(title: String, predicate: Callable, condition_key: StringName = &"") -> BTBuilder:
	var nid: int = _alloc_id()
	var raw_key: String = String(condition_key).strip_edges()
	var negate: bool = false
	while raw_key.begins_with("!"):
		negate = not negate
		raw_key = raw_key.substr(1).strip_edges()
	var clean_key: StringName = StringName(raw_key) if not raw_key.is_empty() else StringName("cond_%d" % nid)
	_compiler.register_condition(clean_key, predicate)
	var ast_key: String = ("!%s" % String(clean_key)) if negate else String(clean_key)
	var rt := BTCondition.new(nid, title, predicate, &"", &"==", null, "", negate)
	var ast_def := BTNodeDef.create(nid, &"Condition", title, {"condition_key": ast_key})
	_attach_leaf(rt, ast_def)
	return self


## 添加一个声明式布尔表达式条件叶节点（通过 [FlowBlackboardExpr] 求值）。
func expr_condition(title: String, expr: String) -> BTBuilder:
	var nid: int = _alloc_id()
	var rt := BTCondition.new(nid, title, Callable(), &"", &"==", null, expr)
	var ast_def := BTNodeDef.create(nid, &"Condition", title, {"expr": expr})
	_attach_leaf(rt, ast_def)
	return self


## 添加一个声明式黑板键值比较条件叶节点。
func bb_compare(title: String, bb_key: StringName, op: StringName, compare_value: Variant) -> BTBuilder:
	var nid: int = _alloc_id()
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
	var nid: int = _alloc_id()
	var a_key: StringName = action_key if not action_key.is_empty() else StringName("act_%d" % nid)
	_compiler.register_action(a_key, callable)
	var merged_params: Dictionary = params.duplicate(true)
	merged_params["action_key"] = String(a_key)
	var rt := BTAction.new(nid, title, callable, a_key, merged_params)
	var ast_def := BTNodeDef.create(nid, &"Action", title, merged_params)
	_attach_leaf(rt, ast_def)
	return self


## 添加一个定时等待叶节点（[BTWait]，支持 `jitter_sec` 随机时长抖动）。
func wait(duration_sec: float, title: String = "", jitter_sec: float = 0.0) -> BTBuilder:
	var nid: int = _alloc_id()
	var resolved_title: String = title if not title.is_empty() else "Wait(%.2fs)" % duration_sec
	var rt := BTWait.new(nid, duration_sec, resolved_title, jitter_sec)
	var params: Dictionary = {"duration_sec": duration_sec}
	if jitter_sec > 0.0:
		params["jitter_sec"] = jitter_sec
	var ast_def := BTNodeDef.create(nid, &"Wait", resolved_title, params)
	_attach_leaf(rt, ast_def)
	return self


## 添加一个外部公共子树挂载叶节点（[BTSubTree]）。
func sub_tree(sub_graph_path: String, title: String = "") -> BTBuilder:
	var nid: int = _alloc_id()
	var resolved_title: String = title if not title.is_empty() else sub_graph_path.get_file().get_basename()
	var params: Dictionary = {"sub_graph_path": sub_graph_path}
	var sub_res: FlowGraphResult = _compiler.compile_sub_tree_node(nid, resolved_title, params)
	var rt: BTNode = (sub_res.value as BTNode) if sub_res.is_ok() else BTSubTree.new(nid, resolved_title, null, sub_graph_path)
	var ast_def := BTNodeDef.create(nid, &"SubTree", resolved_title, params)
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
func build() -> BTTree:
	var graph_def := BTGraphDef.new()
	graph_def.tree_id = _tree_id
	graph_def.root = _root_ast
	graph_def.blackboard_schema = _blackboard_schema.duplicate(true)
	BTCompiler._auto_layout_ast_if_needed(graph_def.root, 0, {"row": 0})
	var tree := BTTree.new(_tree_id, _root_node, graph_def)
	tree.bind_compiler(_compiler)
	return tree


func get_compiler() -> BTCompiler:
	return _compiler


func _alloc_id() -> int:
	var id: int = _next_node_id
	_next_node_id += 1
	return id


func _push_container(rt: BTNode, ast_def: BTNodeDef) -> void:
	_attach_leaf(rt, ast_def)
	_node_stack.append(rt)
	_ast_stack.append(ast_def)


func _attach_leaf(rt: BTNode, ast_def: BTNodeDef) -> void:
	var caller_src: Dictionary = GraphDebugBridge.capture_caller_source()
	if not caller_src.is_empty():
		ast_def.debug_source_file = str(caller_src.get("file", ""))
		ast_def.debug_source_line = int(caller_src.get("line", 0))
	if _root_node == null:
		_root_node = rt
		_root_ast = ast_def
	else:
		if not _node_stack.is_empty():
			var parent_rt: BTNode = _node_stack[_node_stack.size() - 1]
			if parent_rt is BTWeightedSelector:
				var ws: BTWeightedSelector = parent_rt as BTWeightedSelector
				var ch_idx: int = ws.children.size()
				if ast_def.params.has("weight"):
					var explicit_w: float = float(ast_def.params.get("weight", 1.0))
					if ch_idx < ws.weights.size():
						ws.weights[ch_idx] = explicit_w
						parent_rt.add_child_node(rt)
					else:
						ws.add_weighted_child(rt, explicit_w)
				elif ch_idx < ws.weights.size():
					ast_def.params["weight"] = ws.weights[ch_idx]
					parent_rt.add_child_node(rt)
				else:
					ws.add_weighted_child(rt, 1.0)
			else:
				parent_rt.add_child_node(rt)
		if not _ast_stack.is_empty():
			var parent_ast: BTNodeDef = _ast_stack[_ast_stack.size() - 1]
			parent_ast.children.append(ast_def)
#endregion
