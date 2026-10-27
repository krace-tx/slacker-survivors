class_name FsmCompiler
extends RefCounted

## 有限/层次状态机（FSM / HFSM）AST 装配与无损热重载编译器。[br]
##
## 由 [StateMachine] 内部委托调用，负责：黑板 Schema 默认值注入、子状态图 `.tres` 递归加载防环挂载（最大深度 8），以及运行期 `hot_reload_from_ir` 状态保留与回退。

#region Constants
const MAX_SUB_GRAPH_DEPTH: int = 8
#endregion


#region AST Compilation & Hot-Reload
static func compile_into(
	fsm: StateMachine,
	graph_def: FsmGraphDef,
	depth: int = 0,
	visited_paths: Dictionary = {}
) -> FlowGraphResult:
	if graph_def == null:
		return FlowGraphResult.err_code("FSM.NullGraphDef", "Cannot compile null FsmGraphDef.")
	var val_res: FlowGraphResult = graph_def.validate()
	if val_res.is_err():
		return val_res

	fsm._set_compiled_ast(graph_def)
	FlowBlackboardExpr.apply_schema_defaults(graph_def.blackboard_schema, fsm.blackboard)

	var next_visited: Dictionary = visited_paths.duplicate()
	if not graph_def.resource_path.is_empty():
		next_visited[graph_def.resource_path] = true

	var states_dict: Dictionary = fsm._get_states_internal()
	var sources_dict: Dictionary = fsm._get_state_sources_internal()
	var ast_subs: Dictionary = fsm._get_ast_sub_machines_internal()

	for s_def: FsmStateDef in graph_def.states:
		if sources_dict.has(s_def.state_id):
			var src_info: Dictionary = sources_dict[s_def.state_id] as Dictionary
			s_def.debug_source_file = str(src_info.get("file", ""))
			s_def.debug_source_line = int(src_info.get("line", 0))
		if not states_dict.has(s_def.state_id):
			var placeholder := FsmLambdaState.new()
			placeholder.state_id = s_def.state_id
			placeholder.title = s_def.title
			placeholder.bind_context(fsm, fsm.get_actor())
			states_dict[s_def.state_id] = placeholder

		var st_inst: BaseFsmState = states_dict[s_def.state_id] as BaseFsmState
		var sub_path: String = s_def.sub_graph_path.strip_edges()
		if not sub_path.is_empty() and depth < MAX_SUB_GRAPH_DEPTH and not next_visited.has(sub_path) and ResourceLoader.exists(sub_path):
			var sub_res: FsmGraphDef = load(sub_path) as FsmGraphDef
			if sub_res != null and (graph_def.resource_path.is_empty() or sub_res.resource_path != graph_def.resource_path):
				var sub_fsm := StateMachine.new(fsm.get_actor(), sub_res.graph_id)
				sub_fsm.blackboard = fsm.blackboard
				sub_fsm._share_condition_registry(fsm._get_condition_registry_internal())
				var branch_visited: Dictionary = next_visited.duplicate()
				branch_visited[sub_path] = true
				if compile_into(sub_fsm, sub_res, depth + 1, branch_visited).is_ok():
					st_inst.sub_machine = sub_fsm
					ast_subs[s_def.state_id] = true
		elif sub_path.is_empty() and ast_subs.has(s_def.state_id):
			st_inst.sub_machine = null
			ast_subs.erase(s_def.state_id)

	var cond_reg: Dictionary = fsm._get_condition_registry_internal()
	for tr_def: FsmTransitionDef in graph_def.transitions:
		var direct_pred: Callable = cond_reg.get(tr_def.condition_key, Callable()) as Callable
		fsm._append_runtime_transition(tr_def, direct_pred, true)
	fsm._sort_runtime_transitions()
	return FlowGraphResult.ok(fsm)


static func hot_reload_into(fsm: StateMachine, ir: Dictionary) -> FlowGraphResult:
	var probe := FsmGraphDef.new()
	probe.apply_flow_graph_ir(ir)
	var val_res: FlowGraphResult = probe.validate()
	if val_res.is_err():
		return val_res

	var ast_def: FsmGraphDef = fsm.get_ast()
	if ast_def == null:
		ast_def = FsmGraphDef.new()
	ast_def.apply_flow_graph_ir(ir)

	var valid_ids: Dictionary = {}
	for s_def: FsmStateDef in ast_def.states:
		if s_def != null:
			valid_ids[s_def.state_id] = true

	var states_dict: Dictionary = fsm._get_states_internal()
	var ast_subs: Dictionary = fsm._get_ast_sub_machines_internal()
	for existing_key: Variant in states_dict.keys():
		var sid: StringName = existing_key as StringName
		if not valid_ids.has(sid):
			states_dict.erase(sid)
			ast_subs.erase(sid)

	var comp_res: FlowGraphResult = compile_into(fsm, ast_def, 0, {})
	if comp_res.is_err():
		return comp_res

	fsm._reconcile_active_state_after_reload()
	return FlowGraphResult.ok(fsm)
#endregion
