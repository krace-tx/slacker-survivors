class_name BTCompiler
extends RefCounted

## 行为树抽象语法树（AST）解析编译器与算子注册表（Behavior Tree AST Compiler & Registry）。[br]
##
## [b]核心职责：[/b][br]
## 1. 维护动作算子表（`_action_registry`）与条件算子表（`_condition_registry`）；[br]
## 2. 将纯数据描述的 [BTGraphDef]（来自 `.tres` 资产、可视化蓝图连线或 JSON 字典）递归校验并编译为可执行的享元 [BTTree]；[br]
## 3. 自动对 AST 进行树状层级坐标排版（若蓝图节点未指定 `editor_pos`），便于直接绘制可视化节点图。

#region Private Registries
var _action_registry: Dictionary = {}    ## {StringName: Callable}
var _condition_registry: Dictionary = {} ## {StringName: Callable}
#endregion


#region Registration API
## 注册一个命名动作算子（`Callable(ctx: BTContext, params: Dictionary) -> int|bool`）。
func register_action(action_key: StringName, callable: Callable) -> BTCompiler:
	if not action_key.is_empty() and callable.is_valid():
		_action_registry[action_key] = callable
	return self


## 注册一个命名条件算子（`Callable(ctx: BTContext) -> bool`）。
func register_condition(condition_key: StringName, callable: Callable) -> BTCompiler:
	if not condition_key.is_empty() and callable.is_valid():
		_condition_registry[condition_key] = callable
	return self


func has_action(action_key: StringName) -> bool:
	return _action_registry.has(action_key)


func has_condition(condition_key: StringName) -> bool:
	return _condition_registry.has(condition_key)
#endregion


#region AST Compilation
## 将 [BTGraphDef] 抽象语法树校验并编译为享元 [BTTree]，返回 `Result.ok(BTTree)`。
func compile(graph_def: BTGraphDef) -> Result:
	if graph_def == null:
		return Result.err_code("BT.NullGraphDef", "Cannot compile null BTGraphDef.")
	var val_res := graph_def.validate()
	if val_res.is_err():
		return val_res

	_auto_layout_ast_if_needed(graph_def.root, 0, {"row": 0})
	var root_res := _compile_node_recursive(graph_def.root)
	if root_res.is_err():
		return root_res

	var root_node := root_res.value as BTNode
	var tree := BTTree.new(graph_def.tree_id, root_node, graph_def)
	return Result.ok(tree)


func _compile_node_recursive(def: BTNodeDef) -> Result:
	var ntype := def.node_type
	var nid := def.node_id
	var ntitle := def.title
	var p := def.params

	var runtime_node: BTNode = null
	match ntype:
		&"Selector":
			runtime_node = BTSelector.new(nid, ntitle)
		&"Sequence":
			var is_reactive := bool(p.get("reactive", false))
			runtime_node = BTSequence.new(nid, ntitle, is_reactive)
		&"Parallel":
			var req_all := bool(p.get("require_all_success", true))
			runtime_node = BTParallel.new(nid, ntitle, req_all)
		&"Inverter":
			runtime_node = BTInverter.new(nid, ntitle)
		&"Cooldown":
			var cd_sec := float(p.get("cooldown_sec", 1.0))
			runtime_node = BTCooldown.new(nid, cd_sec, ntitle)
		&"Wait":
			var dur_sec := float(p.get("duration_sec", 0.5))
			runtime_node = BTWait.new(nid, dur_sec, ntitle)
		&"Condition":
			var cond_key := StringName(str(p.get("condition_key", "")))
			var bb_key := StringName(str(p.get("bb_key", "")))
			var op := StringName(str(p.get("op", "==")))
			var cmp_val: Variant = p.get("value", null)
			var cond_cb: Callable = _condition_registry.get(cond_key, Callable())
			if cond_key != &"" and not cond_cb.is_valid() and bb_key == &"":
				return Result.err_code(
					"BT.UnregisteredCondition",
					"Condition key '%s' (node_id=%d) is not registered in BTCompiler." % [String(cond_key), nid]
				)
			runtime_node = BTCondition.new(nid, ntitle, cond_cb, bb_key, op, cmp_val)
		&"Action":
			var act_key := StringName(str(p.get("action_key", "")))
			var act_cb: Callable = _action_registry.get(act_key, Callable())
			if not act_cb.is_valid():
				return Result.err_code(
					"BT.UnregisteredAction",
					"Action key '%s' (node_id=%d) is not registered in BTCompiler." % [String(act_key), nid]
				)
			runtime_node = BTAction.new(nid, ntitle, act_cb, act_key, p)
		_:
			return Result.err_code("BT.UnknownNodeType", "Unknown BT node_type '%s' (id=%d)." % [String(ntype), nid])

	for ch_var: Variant in def.children:
		var ch_def := ch_var as BTNodeDef
		var ch_res := _compile_node_recursive(ch_def)
		if ch_res.is_err():
			return ch_res
		runtime_node.add_child_node(ch_res.value as BTNode)

	return Result.ok(runtime_node)


static func _auto_layout_ast_if_needed(node: BTNodeDef, depth: int, cursor: Dictionary) -> void:
	if node == null:
		return
	if node.editor_pos == Vector2.ZERO:
		var row_idx := int(cursor["row"])
		node.editor_pos = Vector2(float(depth) * 185.0, float(row_idx) * 52.0)
	if node.children.is_empty():
		cursor["row"] = int(cursor["row"]) + 1
		return
	for ch_var: Variant in node.children:
		_auto_layout_ast_if_needed(ch_var as BTNodeDef, depth + 1, cursor)
#endregion
