class_name FsmGraphDef
extends Resource

## 状态机完整有向图抽象语法树资源（FSM Graph AST Definition Resource）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一承载状态节点表（[member states]）与有向转换边表（[member transitions]）；[br]
## 2. 提供编译期拓扑合法性校验 [method validate]（检查初始状态、悬空转换边、重复状态 ID）；[br]
## 3. 支持与纯 `Dictionary` / JSON 无损互转，同时服务于代码构建、`.tres` 资源与可视化状态图绘制。

#region Exports
## 状态图唯一标识。
@export var graph_id: StringName = &"fsm_graph"

## 默认启动初始状态 ID。
@export var initial_state: StringName = &""

## 状态节点定义列表。
@export var states: Array[FsmStateDef] = []

## 状态转换有向边定义列表。
@export var transitions: Array[FsmTransitionDef] = []
#endregion


#region Validation & Lookup
## 查找指定 ID 的状态节点 AST 定义。
func find_state_def(state_id: StringName) -> FsmStateDef:
	for s: FsmStateDef in states:
		if s != null and s.state_id == state_id:
			return s
	return null


## 校验状态图 AST 的拓扑合法性。
func validate() -> Result:
	if states.is_empty():
		return Result.err_code("FSM.EmptyGraph", "FsmGraphDef '%s' has no states." % String(graph_id))

	var state_map: Dictionary = {}
	for s: FsmStateDef in states:
		if s == null or s.state_id.is_empty():
			return Result.err_code("FSM.InvalidStateDef", "FsmGraphDef contains an empty state_id.")
		if state_map.has(s.state_id):
			return Result.err_code("FSM.DuplicateState", "Duplicate state_id '%s' in FsmGraphDef." % String(s.state_id))
		state_map[s.state_id] = true

	if not initial_state.is_empty() and not state_map.has(initial_state):
		return Result.err_code(
			"FSM.UnknownInitialState",
			"Initial state '%s' does not exist in FsmGraphDef '%s'." % [String(initial_state), String(graph_id)]
		)

	for tr: FsmTransitionDef in transitions:
		if tr == null:
			continue
		if tr.from_state != FsmTransitionDef.ANY_STATE and not state_map.has(tr.from_state):
			return Result.err_code(
				"FSM.UnknownTransitionSource",
				"Transition source '%s' does not exist in FsmGraphDef." % String(tr.from_state)
			)
		if not state_map.has(tr.to_state):
			return Result.err_code(
				"FSM.UnknownTransitionTarget",
				"Transition target '%s' does not exist in FsmGraphDef." % String(tr.to_state)
			)

	return Result.ok(self)
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
	}


static func from_dict(data: Dictionary) -> FsmGraphDef:
	var graph := FsmGraphDef.new()
	graph.graph_id = StringName(str(data.get("graph_id", "fsm_graph")))
	graph.initial_state = StringName(str(data.get("initial_state", "")))

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
