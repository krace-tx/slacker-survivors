@tool
class_name BTCompiler
extends RefCounted

## 行为树抽象语法树（AST）解析编译器与算子注册表（Behavior Tree AST Compiler & Registry）。[br]
##
## [b]核心职责：[/b][br]
## 1. 维护动作/服务算子表（`_action_registry`）、条件算子表（`_condition_registry`）与效用评分算子表（`_utility_registry`）；[br]
## 2. 将 [BTGraphDef]（含 16 种标准节点与 `SubTree` 外部公共子树嵌套）校验并编译为无状态享元 [BTTree]；[br]
## 3. 将自身编译器绑定至产物 [BTTree]，支撑运行期零重启 `hot_reload_from_ir()`。

#region Constants & Private Registries
const _MAX_SUB_TREE_DEPTH: int = 8
const _SUB_TREE_ID_STRIDE: int = 10000
const _DEEP_SUB_TREE_BASE_SLOT: int = 100

var _action_registry: Dictionary = {}    ## {StringName: Callable}
var _condition_registry: Dictionary = {} ## {StringName: Callable}
var _utility_registry: Dictionary = {}   ## {StringName: Callable}
var _action_sources: Dictionary = {}     ## {StringName: Dictionary}
var _condition_sources: Dictionary = {}  ## {StringName: Dictionary}
var _utility_sources: Dictionary = {}    ## {StringName: Dictionary}
var _bypass_sub_cache: bool = false
var _deep_subtree_slot: int = 0
#endregion


#region Registration API
## 注册一个命名动作算子（`Callable(ctx: BTContext, params: Dictionary) -> int|bool`）。
func register_action(action_key: StringName, callable: Callable) -> BTCompiler:
	if not action_key.is_empty() and callable.is_valid():
		_action_registry[action_key] = callable
		var src: Dictionary = GraphDebugBridge.capture_caller_source()
		if not src.is_empty():
			_action_sources[action_key] = src
	return self


## 注册一个周期黑板服务算子（与动作表共享命名空间，供 `BTService` 节点调用）。
func register_service(service_key: StringName, callable: Callable) -> BTCompiler:
	return register_action(service_key, callable)


## 注册一个命名条件算子（`Callable(ctx: BTContext) -> bool`）。
func register_condition(condition_key: StringName, callable: Callable) -> BTCompiler:
	if not condition_key.is_empty() and callable.is_valid():
		_condition_registry[condition_key] = callable
		var src: Dictionary = GraphDebugBridge.capture_caller_source()
		if not src.is_empty():
			_condition_sources[condition_key] = src
	return self


## 注册一个命名效用评分算子（`Callable(ctx: BTContext) -> float|bool`，归一化区间 `[0.0, 1.0]`）。
func register_utility(utility_key: StringName, callable: Callable) -> BTCompiler:
	if not utility_key.is_empty() and callable.is_valid():
		_utility_registry[utility_key] = callable
		var src: Dictionary = GraphDebugBridge.capture_caller_source()
		if not src.is_empty():
			_utility_sources[utility_key] = src
	return self


func has_action(action_key: StringName) -> bool:
	return _action_registry.has(action_key)


func has_service(service_key: StringName) -> bool:
	return _action_registry.has(service_key)


func has_condition(condition_key: StringName) -> bool:
	return _condition_registry.has(condition_key)


func has_utility(utility_key: StringName) -> bool:
	return _utility_registry.has(utility_key)
#endregion


#region AST Compilation
## 将 [BTGraphDef] 抽象语法树校验并编译为享元 [BTTree]，返回 `FlowGraphResult.ok(BTTree)`。
func compile(graph_def: BTGraphDef, bypass_sub_cache: bool = false) -> FlowGraphResult:
	if graph_def == null:
		return FlowGraphResult.err_code("BT.NullGraphDef", "Cannot compile null BTGraphDef.")
	var val_res: FlowGraphResult = graph_def.validate()
	if val_res.is_err():
		return val_res

	_auto_layout_ast_if_needed(graph_def.root, 0, {"row": 0})
	var init_visited: Dictionary = {}
	if not graph_def.resource_path.is_empty():
		init_visited[graph_def.resource_path] = true

	var prev_bypass: bool = _bypass_sub_cache
	_bypass_sub_cache = bypass_sub_cache
	_deep_subtree_slot = 0
	var root_res: FlowGraphResult = _compile_node_recursive(graph_def.root, 0, init_visited)
	_bypass_sub_cache = prev_bypass
	if root_res.is_err():
		return root_res

	var root_node: BTNode = root_res.value as BTNode
	var tree := BTTree.new(graph_def.tree_id, root_node, graph_def)
	tree.bind_compiler(self)
	return FlowGraphResult.ok(tree)


func _compile_node_recursive(def: BTNodeDef, depth: int = 0, visited_paths: Dictionary = {}) -> FlowGraphResult:
	var ntype: StringName = def.node_type
	var nid: int = def.node_id
	var ntitle: String = def.title
	var p: Dictionary = def.params

	var runtime_node: BTNode = null
	match ntype:
		&"Root":
			runtime_node = BTRoot.new(nid, ntitle)
		&"Selector":
			var mem: bool = bool(p.get("memory", false))
			runtime_node = BTSelector.new(nid, ntitle, mem)
		&"WeightedSelector":
			var weights: Array[float] = _extract_child_weights(def)
			runtime_node = BTWeightedSelector.new(nid, ntitle, weights)
		&"UtilitySelector":
			var util_res: FlowGraphResult = _compile_utility_selector_node(def)
			if util_res.is_err():
				return util_res
			runtime_node = util_res.value as BTNode
		&"Sequence":
			var is_reactive: bool = bool(p.get("reactive", false))
			runtime_node = BTSequence.new(nid, ntitle, is_reactive)
		&"Parallel":
			var req_all: bool = bool(p.get("require_all_success", true))
			runtime_node = BTParallel.new(nid, ntitle, req_all)
		&"Inverter":
			runtime_node = BTInverter.new(nid, ntitle)
		&"Cooldown":
			var cd_sec: float = float(p.get("cooldown_sec", 1.0))
			var cd_jit: float = float(p.get("jitter_sec", 0.0))
			runtime_node = BTCooldown.new(nid, cd_sec, ntitle, cd_jit)
		&"Repeater":
			var rep_cnt: int = int(p.get("repeat_count", 3))
			var abt_fail: bool = bool(p.get("abort_on_failure", true))
			runtime_node = BTRepeater.new(nid, rep_cnt, abt_fail, ntitle)
		&"TimeLimit":
			var tl_sec: float = float(p.get("timeout_sec", 3.0))
			runtime_node = BTTimeLimit.new(nid, tl_sec, ntitle)
		&"ForceSuccess":
			runtime_node = BTForceStatus.new(nid, true, ntitle)
		&"ForceFailure":
			runtime_node = BTForceStatus.new(nid, false, ntitle)
		&"Service":
			var srv_key := StringName(str(p.get("service_key", p.get("action_key", ""))))
			var srv_cb: Callable = _action_registry.get(srv_key, Callable()) as Callable
			if not srv_key.is_empty() and not srv_cb.is_valid():
				return FlowGraphResult.err_code(
					"BT.UnregisteredService",
					"Service key '%s' (node_id=%d) is not registered in BTCompiler." % [String(srv_key), nid]
				)
			if def.debug_source_file.is_empty() and _action_sources.has(srv_key):
				var s_src: Dictionary = _action_sources[srv_key] as Dictionary
				def.debug_source_file = str(s_src.get("file", ""))
				def.debug_source_line = int(s_src.get("line", 0))
			var iv_sec: float = float(p.get("interval_sec", 0.25))
			var iv_jit: float = float(p.get("jitter_sec", 0.05))
			runtime_node = BTService.new(nid, srv_cb, iv_sec, iv_jit, ntitle, srv_key, p)
		&"Wait":
			var dur_sec: float = float(p.get("duration_sec", 0.5))
			var w_jit: float = float(p.get("jitter_sec", 0.0))
			runtime_node = BTWait.new(nid, dur_sec, ntitle, w_jit)
		&"Condition":
			var cond_res: FlowGraphResult = _compile_condition_node(def)
			if cond_res.is_err():
				return cond_res
			runtime_node = cond_res.value as BTNode
		&"Action":
			var act_key := StringName(str(p.get("action_key", "")))
			var act_cb: Callable = _action_registry.get(act_key, Callable()) as Callable
			if not act_cb.is_valid():
				return FlowGraphResult.err_code(
					"BT.UnregisteredAction",
					"Action key '%s' (node_id=%d) is not registered in BTCompiler." % [String(act_key), nid]
				)
			if def.debug_source_file.is_empty() and _action_sources.has(act_key):
				var a_src: Dictionary = _action_sources[act_key] as Dictionary
				def.debug_source_file = str(a_src.get("file", ""))
				def.debug_source_line = int(a_src.get("line", 0))
			runtime_node = BTAction.new(nid, ntitle, act_cb, act_key, p)
		&"SubTree":
			var sub_res: FlowGraphResult = compile_sub_tree_node(nid, ntitle, p, depth, visited_paths)
			if sub_res.is_err():
				return sub_res
			runtime_node = sub_res.value as BTNode
		_:
			return FlowGraphResult.err_code("BT.UnknownNodeType", "Unknown BT node_type '%s' (id=%d)." % [String(ntype), nid])

	for ch_var: Variant in def.children:
		var ch_def: BTNodeDef = ch_var as BTNodeDef
		var ch_res: FlowGraphResult = _compile_node_recursive(ch_def, depth, visited_paths)
		if ch_res.is_err():
			return ch_res
		runtime_node.add_child_node(ch_res.value as BTNode)

	return FlowGraphResult.ok(runtime_node)
#endregion


#region Specialized Node Compilation Helpers
func _compile_condition_node(def: BTNodeDef) -> FlowGraphResult:
	var nid: int = def.node_id
	var p: Dictionary = def.params
	var expr_str: String = str(p.get("expr", "")).strip_edges()
	var raw_cond_str: String = str(p.get("condition_key", "")).strip_edges()
	var bb_key := StringName(str(p.get("bb_key", p.get("key", ""))))
	var op := StringName(str(p.get("op", "==")))
	var cmp_val: Variant = p.get("value", null)

	var cond_reg_ref: Dictionary = _condition_registry
	var lookup_cb: Callable = func(k: StringName) -> Callable:
		return cond_reg_ref.get(k, Callable()) as Callable

	var is_compound_cond: bool = (
		raw_cond_str.contains("&&")
		or raw_cond_str.contains("||")
		or raw_cond_str.contains("<=")
		or raw_cond_str.contains(">=")
		or raw_cond_str.contains("==")
		or raw_cond_str.contains("!=")
		or raw_cond_str.contains("<")
		or raw_cond_str.contains(">")
	)
	if is_compound_cond and expr_str.is_empty():
		expr_str = raw_cond_str
		raw_cond_str = ""

	var negate: bool = false
	var cond_cb: Callable = Callable()
	if not raw_cond_str.is_empty():
		while raw_cond_str.begins_with("!"):
			negate = not negate
			raw_cond_str = raw_cond_str.substr(1).strip_edges()
		var cond_key := StringName(raw_cond_str)
		cond_cb = _condition_registry.get(cond_key, Callable()) as Callable
		if not cond_cb.is_valid() and bb_key == &"" and expr_str.is_empty():
			return FlowGraphResult.err_code(
				"BT.UnregisteredCondition",
				"Condition key '%s' (node_id=%d) is not registered in BTCompiler." % [String(cond_key), nid]
			)
		if def.debug_source_file.is_empty() and _condition_sources.has(cond_key):
			var c_src: Dictionary = _condition_sources[cond_key] as Dictionary
			def.debug_source_file = str(c_src.get("file", ""))
			def.debug_source_line = int(c_src.get("line", 0))

	var cond_node := BTCondition.new(def.node_id, def.title, cond_cb, bb_key, op, cmp_val, expr_str, negate, lookup_cb)
	return FlowGraphResult.ok(cond_node)


## 加载外部 `.tres` 公共子树并以 `nid * 10000` 偏移编译内部根节点（供编译器与 `BTBuilder` 共用）。
func compile_sub_tree_node(
	nid: int,
	ntitle: String,
	p: Dictionary,
	depth: int = 0,
	visited_paths: Dictionary = {}
) -> FlowGraphResult:
	if depth >= _MAX_SUB_TREE_DEPTH:
		return FlowGraphResult.err_code("BT.SubTreeMaxDepth", "SubTree nesting exceeded max depth %d (node_id=%d)." % [_MAX_SUB_TREE_DEPTH, nid])

	var sub_path: String = str(p.get("sub_graph_path", "")).strip_edges()
	var sub_graph: BTGraphDef = p.get("sub_graph", null) as BTGraphDef
	if sub_graph == null:
		if sub_path.is_empty():
			return FlowGraphResult.err_code("BT.EmptySubTreePath", "SubTree node %d has empty sub_graph_path." % nid)
		if visited_paths.has(sub_path):
			return FlowGraphResult.err_code("BT.SubTreeCycle", "Cyclic SubTree reference detected at '%s'." % sub_path)
		if not ResourceLoader.exists(sub_path):
			return FlowGraphResult.err_code("BT.MissingSubTree", "SubTree resource not found: '%s'." % sub_path)
		var cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REPLACE if _bypass_sub_cache else ResourceLoader.CACHE_MODE_REUSE
		sub_graph = ResourceLoader.load(sub_path, "", cache_mode) as BTGraphDef

	if sub_graph == null:
		return FlowGraphResult.err_code("BT.InvalidSubTreeResource", "Resource '%s' is not a valid BTGraphDef." % sub_path)
	var sub_val: FlowGraphResult = sub_graph.validate()
	if sub_val.is_err():
		return sub_val

	var cloned_root_def: BTNodeDef = BTNodeDef.from_dict(sub_graph.root.to_dict())
	var id_offset: int = 0
	if depth == 0 and nid > 0 and nid < _DEEP_SUB_TREE_BASE_SLOT:
		id_offset = nid * _SUB_TREE_ID_STRIDE
	else:
		_deep_subtree_slot += 1
		id_offset = (_DEEP_SUB_TREE_BASE_SLOT + _deep_subtree_slot) * _SUB_TREE_ID_STRIDE
	_offset_node_ids_recursive(cloned_root_def, id_offset)

	var next_visited: Dictionary = visited_paths.duplicate()
	if not sub_path.is_empty():
		next_visited[sub_path] = true
	if not sub_graph.resource_path.is_empty():
		next_visited[sub_graph.resource_path] = true

	var sub_rt_res: FlowGraphResult = _compile_node_recursive(cloned_root_def, depth + 1, next_visited)
	if sub_rt_res.is_err():
		return sub_rt_res

	var sub_node := BTSubTree.new(nid, ntitle, sub_rt_res.value as BTNode, sub_path, sub_graph.blackboard_schema)
	return FlowGraphResult.ok(sub_node)


static func _extract_child_weights(def: BTNodeDef) -> Array[float]:
	var out: Array[float] = []
	var fallback_arr: Array = def.params.get("weights", []) as Array if def.params.get("weights", []) is Array else []
	for i: int in range(def.children.size()):
		var ch_def: BTNodeDef = def.children[i] as BTNodeDef
		if ch_def != null and ch_def.params.has("weight"):
			out.append(maxf(0.0, float(ch_def.params.get("weight", 1.0))))
		elif i < fallback_arr.size():
			out.append(maxf(0.0, float(fallback_arr[i])))
		else:
			out.append(1.0)
	return out


func _compile_utility_selector_node(def: BTNodeDef) -> FlowGraphResult:
	var nid: int = def.node_id
	var p: Dictionary = def.params
	var specs: Array[Dictionary] = _extract_child_utility_specs(def)
	for sp: Dictionary in specs:
		var err_res: FlowGraphResult = _validate_utility_spec_keys(sp, nid)
		if err_res.is_err():
			return err_res

	var util_reg_ref: Dictionary = _utility_registry
	var cond_reg_ref: Dictionary = _condition_registry
	var lookup_cb: Callable = func(k: StringName) -> Callable:
		if util_reg_ref.has(k):
			return util_reg_ref[k] as Callable
		return cond_reg_ref.get(k, Callable()) as Callable

	var rt := BTUtilitySelector.new(
		nid,
		def.title,
		specs,
		float(p.get("momentum", 0.10)),
		float(p.get("min_score", 0.01)),
		int(p.get("top_k", 1)),
		bool(p.get("memory", false)),
		lookup_cb
	)
	return FlowGraphResult.ok(rt)


func _validate_utility_spec_keys(spec: Dictionary, nid: int) -> FlowGraphResult:
	var s: Dictionary = FlowUtilityScorer.unwrap_spec(spec)
	var u_key_raw: String = str(s.get("utility_key", "")).strip_edges()
	if not u_key_raw.is_empty():
		var u_key := StringName(u_key_raw)
		if not _utility_registry.has(u_key) and not _condition_registry.has(u_key):
			return FlowGraphResult.err_code(
				"BT.UnregisteredUtility",
				"Utility key '%s' (node_id=%d) is not registered in BTCompiler." % [u_key_raw, nid]
			)
	var raw_cons: Variant = s.get("considerations", null)
	if raw_cons is Array:
		for item: Variant in raw_cons as Array:
			if item is Dictionary:
				var sub_res: FlowGraphResult = _validate_utility_spec_keys(item as Dictionary, nid)
				if sub_res.is_err():
					return sub_res
	return FlowGraphResult.ok(true)


static func _extract_child_utility_specs(def: BTNodeDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fallback_arr: Array = def.params.get("utility_specs", []) as Array if def.params.get("utility_specs", []) is Array else []
	for i: int in range(def.children.size()):
		var ch_def: BTNodeDef = def.children[i] as BTNodeDef
		if ch_def != null and ch_def.params.has("utility") and ch_def.params["utility"] is Dictionary:
			out.append((ch_def.params["utility"] as Dictionary).duplicate(true))
		elif i < fallback_arr.size() and fallback_arr[i] is Dictionary:
			out.append((fallback_arr[i] as Dictionary).duplicate(true))
		else:
			out.append({})
	return out


static func _offset_node_ids_recursive(node: BTNodeDef, offset: int) -> void:
	if node == null:
		return
	node.node_id += offset
	for ch_var: Variant in node.children:
		_offset_node_ids_recursive(ch_var as BTNodeDef, offset)


static func _auto_layout_ast_if_needed(node: BTNodeDef, depth: int, cursor: Dictionary) -> void:
	if node == null:
		return
	if node.editor_pos == Vector2.ZERO:
		var row_idx: int = int(cursor["row"])
		node.editor_pos = Vector2(float(depth) * 185.0, float(row_idx) * 52.0)
	if node.children.is_empty():
		cursor["row"] = int(cursor["row"]) + 1
		return
	for ch_var: Variant in node.children:
		_auto_layout_ast_if_needed(ch_var as BTNodeDef, depth + 1, cursor)
#endregion
