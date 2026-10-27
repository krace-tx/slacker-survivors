@tool
class_name FsmGraphDef
extends Resource

## 状态机完整有向图抽象语法树资源（FSM Graph AST Definition Resource）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一承载状态节点表（[member states]）、转换边表（[member transitions]）与黑板 Schema（[member blackboard_schema]）；[br]
## 2. 提供编译期拓扑合法性校验 [method validate]（检查初始状态、悬空转换边、重复状态 ID）；[br]
## 3. 支持与纯 `Dictionary` / 标准图 IR 无损互转，同时服务于代码构建、`.tres` 资源与可视化画布绘制。

#region Exports
## 状态图唯一标识。
@export var graph_id: StringName = &"fsm_graph"

## 默认启动初始状态 ID。
@export var initial_state: StringName = &""

## 状态节点定义列表。
@export var states: Array[FsmStateDef] = []

## 状态转换有向边定义列表。
@export var transitions: Array[FsmTransitionDef] = []

## 黑板变量 Schema 声明列表（元素格式：`{"key": "hp_ratio", "type": "float", "default": 1.0}`）。
@export var blackboard_schema: Array[Dictionary] = []
#endregion


#region Validation & Lookup
## 查找指定 ID 的状态节点 AST 定义。
func find_state_def(state_id: StringName) -> FsmStateDef:
	for s: FsmStateDef in states:
		if s != null and s.state_id == state_id:
			return s
	return null


## 校验状态图 AST 的拓扑合法性。
func validate() -> FlowGraphResult:
	if states.is_empty():
		return FlowGraphResult.err_code("FSM.EmptyGraph", "FsmGraphDef '%s' has no states." % String(graph_id))

	var state_map: Dictionary = {}
	for s: FsmStateDef in states:
		if s == null or s.state_id.is_empty():
			return FlowGraphResult.err_code("FSM.InvalidStateDef", "FsmGraphDef contains an empty state_id.")
		if state_map.has(s.state_id):
			return FlowGraphResult.err_code("FSM.DuplicateState", "Duplicate state_id '%s' in FsmGraphDef." % String(s.state_id))
		state_map[s.state_id] = true

	if not initial_state.is_empty() and not state_map.has(initial_state):
		return FlowGraphResult.err_code(
			"FSM.UnknownInitialState",
			"Initial state '%s' does not exist in FsmGraphDef '%s'." % [String(initial_state), String(graph_id)]
		)

	for tr: FsmTransitionDef in transitions:
		if tr == null:
			continue
		if tr.from_state != FsmTransitionDef.ANY_STATE and not state_map.has(tr.from_state):
			return FlowGraphResult.err_code(
				"FSM.UnknownTransitionSource",
				"Transition source '%s' does not exist in FsmGraphDef." % String(tr.from_state)
			)
		if not state_map.has(tr.to_state):
			return FlowGraphResult.err_code(
				"FSM.UnknownTransitionTarget",
				"Transition target '%s' does not exist in FsmGraphDef." % String(tr.to_state)
			)

	return FlowGraphResult.ok(self)
#endregion


#region Serialization
func to_dict() -> Dictionary:
	var s_arr: Array[Dictionary] = []
	for s: FsmStateDef in states:
		if s != null:
			s_arr.append(s.to_dict())
	var t_arr: Array[Dictionary] = []
	for tr: FsmTransitionDef in transitions:
		if tr != null:
			t_arr.append(tr.to_dict())
	return {
		"graph_id": String(graph_id),
		"initial_state": String(initial_state),
		"states": s_arr,
		"transitions": t_arr,
		"blackboard_schema": blackboard_schema.duplicate(true),
	}


static func from_dict(data: Dictionary) -> FsmGraphDef:
	var graph := FsmGraphDef.new()
	graph.graph_id = StringName(str(data.get("graph_id", "fsm_graph")))
	graph.initial_state = StringName(str(data.get("initial_state", "")))
	graph.blackboard_schema = _parse_schema_array(data.get("blackboard_schema", []))

	var raw_states: Variant = data.get("states", [])
	if raw_states is Array:
		for item: Variant in raw_states as Array:
			if item is Dictionary:
				graph.states.append(FsmStateDef.from_dict(item as Dictionary))

	var raw_trans: Variant = data.get("transitions", [])
	if raw_trans is Array:
		for item: Variant in raw_trans as Array:
			if item is Dictionary:
				graph.transitions.append(FsmTransitionDef.from_dict(item as Dictionary))

	return graph
#endregion


#region Canonical Mermaid IR Protocol (Zero Plugin Coupling)
## 导出为标准图中间表示字典（供可视化画布与调试器零耦合读取）。
func to_mermaid_ir() -> Dictionary:
	var nodes_out: Array[Dictionary] = []
	for s: FsmStateDef in states:
		if s == null or s.state_id.is_empty():
			continue
		var p_out: Dictionary = s.params.duplicate(true)
		if not s.action_key.is_empty():
			p_out["action_key"] = String(s.action_key)
		if not s.sub_graph_path.is_empty():
			p_out["sub_graph_path"] = s.sub_graph_path
		var src_out: Dictionary = {}
		if not s.debug_source_file.is_empty():
			src_out = {"file": s.debug_source_file, "line": s.debug_source_line}
		nodes_out.append({
			"id": String(s.state_id),
			"title": s.title if not s.title.is_empty() else String(s.state_id),
			"shape": "round",
			"kind": "State",
			"pos": [s.editor_pos.x, s.editor_pos.y],
			"params": p_out,
			"source": src_out,
		})

	var edges_out: Array[Dictionary] = []
	var order_i: int = 0
	for tr: FsmTransitionDef in transitions:
		if tr == null or tr.from_state.is_empty() or tr.to_state.is_empty():
			continue
		var lbl: String = _format_transition_label(tr)
		edges_out.append({
			"from": String(tr.from_state),
			"to": String(tr.to_state),
			"label": lbl,
			"priority": tr.priority,
			"order": order_i,
			"discovered": false,
			"params": {
				"condition_key": String(tr.condition_key),
				"trigger_event": String(tr.trigger_event),
				"bb_expr": tr.bb_expr,
				"min_state_time": tr.min_state_time,
				"description": tr.description,
			},
		})
		order_i += 1

	return {
		"schema": "fsm",
		"diagram_type": "stateDiagram-v2",
		"direction": "LR",
		"title": String(graph_id),
		"initial_node_id": String(initial_state),
		"blackboard_schema": blackboard_schema.duplicate(true),
		"nodes": nodes_out,
		"edges": edges_out,
	}


## 从标准图中间表示字典反向写回当前 `FsmGraphDef` 资源（供画布直编或 Mermaid 导出 `.tres` 使用）。
func apply_mermaid_ir(ir: Dictionary) -> void:
	var raw_title: String = str(ir.get("title", "")).strip_edges()
	if not raw_title.is_empty() and raw_title != "mermaid_graph":
		graph_id = StringName(raw_title)

	if ir.has("blackboard_schema"):
		blackboard_schema = _parse_schema_array(ir.get("blackboard_schema", []))

	var next_states: Array[FsmStateDef] = []
	var raw_nodes: Variant = ir.get("nodes", [])
	if raw_nodes is Array:
		for item: Variant in raw_nodes as Array:
			if not (item is Dictionary):
				continue
			var nd: Dictionary = item as Dictionary
			var sid := StringName(str(nd.get("id", "")).strip_edges())
			if sid.is_empty():
				continue
			var stitle: String = str(nd.get("title", String(sid)))
			var pos_vec := Vector2.ZERO
			var raw_pos: Variant = nd.get("pos", Vector2.ZERO)
			if raw_pos is Vector2:
				pos_vec = raw_pos as Vector2
			elif raw_pos is Array and (raw_pos as Array).size() >= 2:
				var pa: Array = raw_pos as Array
				pos_vec = Vector2(float(pa[0]), float(pa[1]))

			var p_dict: Dictionary = (nd.get("params", {}) as Dictionary).duplicate(true) if nd.get("params", {}) is Dictionary else {}
			var act_key := StringName(str(p_dict.get("action_key", String(sid))))
			var sub_path: String = str(p_dict.get("sub_graph_path", "")).strip_edges()
			p_dict.erase("action_key")
			p_dict.erase("sub_graph_path")

			var s_def := FsmStateDef.create(sid, stitle, pos_vec, p_dict, sub_path)
			s_def.action_key = act_key if not act_key.is_empty() else sid
			var raw_src: Variant = nd.get("source", {})
			if raw_src is Dictionary:
				s_def.debug_source_file = str((raw_src as Dictionary).get("file", ""))
				s_def.debug_source_line = int((raw_src as Dictionary).get("line", 0))
			next_states.append(s_def)

	states = next_states
	var init_str: String = str(ir.get("initial_node_id", "")).strip_edges()
	if not init_str.is_empty():
		initial_state = StringName(init_str)
	elif not states.is_empty():
		initial_state = states[0].state_id
	else:
		initial_state = &""

	var next_trans: Array[FsmTransitionDef] = []
	var raw_edges: Variant = ir.get("edges", [])
	if raw_edges is Array:
		for item: Variant in raw_edges as Array:
			if not (item is Dictionary):
				continue
			var ed: Dictionary = item as Dictionary
			if bool(ed.get("discovered", false)):
				continue
			var f_id := StringName(str(ed.get("from", "")).strip_edges())
			var t_id := StringName(str(ed.get("to", "")).strip_edges())
			if f_id.is_empty() or t_id.is_empty():
				continue
			var lbl: String = str(ed.get("label", "")).strip_edges()
			var prio: int = int(ed.get("priority", 0))
			var ep: Dictionary = ed.get("params", {}) as Dictionary if ed.get("params", {}) is Dictionary else {}

			var cond_key := StringName(str(ep.get("condition_key", "")).strip_edges())
			var trig_ev := StringName(str(ep.get("trigger_event", "")).strip_edges())
			var bb_ex: String = str(ep.get("bb_expr", "")).strip_edges()
			var min_t: float = float(ep.get("min_state_time", 0.0))
			var desc: String = str(ep.get("description", ""))

			if ep.is_empty() and not lbl.is_empty():
				if lbl.begins_with("[⚡") and lbl.ends_with("]") and lbl.length() > 3:
					trig_ev = StringName(lbl.substr(2, lbl.length() - 3).strip_edges())
				elif lbl.ends_with("s") and lbl.trim_suffix("s").is_valid_float():
					min_t = float(lbl.trim_suffix("s"))
				elif lbl.is_valid_identifier() or (lbl.begins_with("!") and lbl.substr(1).is_valid_identifier()):
					cond_key = StringName(lbl)
				else:
					desc = lbl

			next_trans.append(FsmTransitionDef.create(f_id, t_id, cond_key, prio, min_t, desc, trig_ev, bb_ex))

	transitions = next_trans
	emit_changed()


func to_flow_graph_ir() -> Dictionary:
	return to_mermaid_ir()


func apply_flow_graph_ir(ir: Dictionary) -> void:
	apply_mermaid_ir(ir)


static func from_mermaid_ir(ir: Dictionary) -> FsmGraphDef:
	var g := FsmGraphDef.new()
	g.apply_mermaid_ir(ir)
	return g


static func _format_transition_label(tr: FsmTransitionDef) -> String:
	var lbl: String = tr.description
	if lbl.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		if not tr.trigger_event.is_empty():
			parts.append("[⚡%s]" % String(tr.trigger_event))
		if not tr.condition_key.is_empty():
			parts.append(String(tr.condition_key))
		if not tr.bb_expr.is_empty():
			parts.append(tr.bb_expr)
		lbl = " ".join(parts)
	if tr.min_state_time > 0.0 and lbl.find("s") < 0:
		lbl = ("%s (%.2fs)" % [lbl, tr.min_state_time]).strip_edges()
	return lbl


static func _parse_schema_array(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Dictionary:
				out.append((entry as Dictionary).duplicate(true))
	return out
#endregion
