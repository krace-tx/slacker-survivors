@tool
class_name BTGraphDef
extends Resource

## 整棵行为树的抽象语法树资源定义（Behavior Tree Graph AST Resource）。[br]
##
## 支持编译期结构校验 [method validate]、节点总数统计、黑板 Schema 声明以及与标准图 IR / JSON 的双向无损转换。

#region Constants & Exports
const _COMPOSITE_TYPES: Array[StringName] = [&"Selector", &"Sequence", &"Parallel", &"WeightedSelector"]
const _DECORATOR_TYPES: Array[StringName] = [
	&"Inverter", &"Cooldown", &"Repeater", &"TimeLimit", &"ForceSuccess", &"ForceFailure", &"Service",
]
const _KNOWN_KINDS: Array[String] = [
	"Root",
	"Selector", "WeightedSelector", "Sequence", "Parallel",
	"Inverter", "Cooldown", "Repeater", "TimeLimit", "ForceSuccess", "ForceFailure", "Service",
	"Condition", "Action", "Wait", "SubTree",
]

## 行为树唯一标识（如 `&"boss_ashen_warden_bt"`）。
@export var tree_id: StringName = &"bt_graph"

## 根节点 AST 描述子。
@export var root: BTNodeDef = null

## 黑板变量 Schema 声明列表（元素格式：`{"key": "hp_ratio", "type": "float", "default": 1.0}`）。
@export var blackboard_schema: Array[Dictionary] = []
#endregion


#region Validation & Traversal
func validate() -> FlowGraphResult:
	if root == null:
		return FlowGraphResult.err_code("BT.EmptyGraph", "BTGraphDef '%s' has no root node." % String(tree_id))
	var seen_ids: Dictionary = {}
	return _validate_node_recursive(root, seen_ids)


func count_nodes() -> int:
	return _count_recursive(root)


func flatten_nodes() -> Array[BTNodeDef]:
	var out: Array[BTNodeDef] = []
	_flatten_recursive(root, out)
	return out


func _validate_node_recursive(node: BTNodeDef, seen_ids: Dictionary) -> FlowGraphResult:
	if node.node_type.is_empty():
		return FlowGraphResult.err_code("BT.InvalidNodeType", "Node %d has empty node_type." % node.node_id)
	if seen_ids.has(node.node_id):
		return FlowGraphResult.err_code("BT.DuplicateNodeId", "Duplicate node_id %d in BTGraphDef." % node.node_id)
	seen_ids[node.node_id] = true

	var is_composite: bool = node.node_type in _COMPOSITE_TYPES
	var is_decorator: bool = node.node_type in _DECORATOR_TYPES
	if node.node_type == &"Root":
		if node != root:
			return FlowGraphResult.err_code(
				"BT.NestedRoot",
				"Root node '%s' (id=%d) can only be the top-level entry root." % [node.title, node.node_id]
			)
		if node.children.size() != 1:
			return FlowGraphResult.err_code(
				"BT.InvalidRootChildCount",
				"Root node '%s' (id=%d) must connect to exactly 1 child." % [node.title, node.node_id]
			)
	elif is_composite and node.children.is_empty():
		return FlowGraphResult.err_code(
			"BT.EmptyComposite",
			"Composite node '%s' (id=%d) must have at least 1 child." % [node.title, node.node_id]
		)
	if is_decorator and node.children.size() != 1:
		return FlowGraphResult.err_code(
			"BT.InvalidDecoratorChildCount",
			"Decorator node '%s' (id=%d) must have exactly 1 child." % [node.title, node.node_id]
		)

	for ch_var: Variant in node.children:
		var ch: BTNodeDef = ch_var as BTNodeDef
		if ch == null:
			return FlowGraphResult.err_code("BT.NullChild", "Node '%s' contains a null child." % node.title)
		var res: FlowGraphResult = _validate_node_recursive(ch, seen_ids)
		if res.is_err():
			return res
	return FlowGraphResult.ok(self)


func _count_recursive(node: BTNodeDef) -> int:
	if node == null:
		return 0
	var total: int = 1
	for ch_var: Variant in node.children:
		total += _count_recursive(ch_var as BTNodeDef)
	return total


func _flatten_recursive(node: BTNodeDef, out: Array[BTNodeDef]) -> void:
	if node == null:
		return
	out.append(node)
	for ch_var: Variant in node.children:
		_flatten_recursive(ch_var as BTNodeDef, out)
#endregion


#region Serialization
func to_dict() -> Dictionary:
	return {
		"tree_id": String(tree_id),
		"root": root.to_dict() if root != null else {},
		"blackboard_schema": blackboard_schema.duplicate(true),
	}


static func from_dict(data: Dictionary) -> BTGraphDef:
	var graph := BTGraphDef.new()
	graph.tree_id = StringName(str(data.get("tree_id", "bt_graph")))
	graph.blackboard_schema = _parse_schema_array(data.get("blackboard_schema", []))
	var raw_root: Variant = data.get("root", null)
	if raw_root is Dictionary and not (raw_root as Dictionary).is_empty():
		graph.root = BTNodeDef.from_dict(raw_root as Dictionary)
	return graph
#endregion


#region Canonical Mermaid IR Protocol (Zero Plugin Coupling)
func to_mermaid_ir() -> Dictionary:
	var nodes_out: Array[Dictionary] = []
	var edges_out: Array[Dictionary] = []
	if root != null:
		_collect_mermaid_recursive(root, nodes_out, edges_out)
	return {
		"schema": "bt",
		"diagram_type": "flowchart",
		"direction": "LR",
		"title": String(tree_id),
		"initial_node_id": ("n%d" % root.node_id) if root != null else "",
		"blackboard_schema": blackboard_schema.duplicate(true),
		"nodes": nodes_out,
		"edges": edges_out,
	}


func apply_mermaid_ir(ir: Dictionary) -> void:
	var raw_title: String = str(ir.get("title", "")).strip_edges()
	if not raw_title.is_empty() and raw_title != "mermaid_graph":
		tree_id = StringName(raw_title)
	if ir.has("blackboard_schema"):
		blackboard_schema = _parse_schema_array(ir.get("blackboard_schema", []))

	var raw_nodes: Variant = ir.get("nodes", [])
	if not (raw_nodes is Array) or (raw_nodes as Array).is_empty():
		root = null
		emit_changed()
		return

	var def_by_key: Dictionary = {}
	var key_order: Array[String] = []
	var used_int_ids: Dictionary = {}
	var next_auto_id: int = 1

	for item: Variant in raw_nodes as Array:
		if not (item is Dictionary):
			continue
		var nd: Dictionary = item as Dictionary
		var str_id: String = str(nd.get("id", "")).strip_edges()
		if str_id.is_empty() or def_by_key.has(str_id):
			continue

		var parsed_id: int = int(str_id.substr(1)) if (str_id.begins_with("n") and str_id.substr(1).is_valid_int()) else 0
		while parsed_id <= 0 or used_int_ids.has(parsed_id):
			parsed_id = next_auto_id
			next_auto_id += 1
		used_int_ids[parsed_id] = true

		var p_dict: Dictionary = (nd.get("params", {}) as Dictionary).duplicate(true) if nd.get("params", {}) is Dictionary else {}
		var ntitle: String = str(nd.get("title", str_id))
		var ntype: StringName = _resolve_bt_node_type(str(nd.get("kind", "")), str(nd.get("shape", "rect")), ntitle, p_dict)
		_fill_default_node_params(ntype, str_id, parsed_id, p_dict)

		var pos_vec := Vector2.ZERO
		var raw_pos: Variant = nd.get("pos", Vector2.ZERO)
		if raw_pos is Vector2:
			pos_vec = raw_pos as Vector2
		elif raw_pos is Array and (raw_pos as Array).size() >= 2:
			var pa: Array = raw_pos as Array
			pos_vec = Vector2(float(pa[0]), float(pa[1]))

		var b_def := BTNodeDef.create(parsed_id, ntype, ntitle, p_dict, pos_vec)
		var raw_src: Variant = nd.get("source", {})
		if raw_src is Dictionary:
			b_def.debug_source_file = str((raw_src as Dictionary).get("file", ""))
			b_def.debug_source_line = int((raw_src as Dictionary).get("line", 0))

		def_by_key[str_id] = b_def
		key_order.append(str_id)

	if key_order.is_empty():
		root = null
		emit_changed()
		return

	var adj: Dictionary = {}
	var in_deg: Dictionary = {}
	for k: String in key_order:
		adj[k] = []
		in_deg[k] = 0

	var raw_edges: Variant = ir.get("edges", [])
	if raw_edges is Array:
		var sorted_edges: Array[Dictionary] = []
		for e_item: Variant in raw_edges as Array:
			if e_item is Dictionary and not bool((e_item as Dictionary).get("discovered", false)):
				sorted_edges.append(e_item as Dictionary)
		sorted_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", a.get("priority", 0))) < int(b.get("order", b.get("priority", 0)))
		)
		for ed: Dictionary in sorted_edges:
			var f_key: String = str(ed.get("from", "")).strip_edges()
			var t_key: String = str(ed.get("to", "")).strip_edges()
			if def_by_key.has(f_key) and def_by_key.has(t_key) and f_key != t_key:
				(adj[f_key] as Array).append(t_key)
				in_deg[t_key] = int(in_deg[t_key]) + 1
				var ep: Variant = ed.get("params", {})
				if ep is Dictionary and (ep as Dictionary).has("weight"):
					var child_def: BTNodeDef = def_by_key[t_key] as BTNodeDef
					child_def.params["weight"] = float((ep as Dictionary).get("weight", 1.0))

	var root_key: String = str(ir.get("initial_node_id", "")).strip_edges()
	for k_r: String in key_order:
		if (def_by_key[k_r] as BTNodeDef).node_type == &"Root":
			root_key = k_r
			break
	if not def_by_key.has(root_key):
		root_key = ""
		for k: String in key_order:
			if int(in_deg[k]) == 0:
				root_key = k
				break
		if root_key.is_empty():
			root_key = key_order[0]

	var visited: Dictionary = {}
	_wire_bt_children_recursive(root_key, def_by_key, adj, visited)
	root = def_by_key[root_key] as BTNodeDef
	emit_changed()


static func from_mermaid_ir(ir: Dictionary) -> BTGraphDef:
	var g := BTGraphDef.new()
	g.apply_mermaid_ir(ir)
	return g


static func _collect_mermaid_recursive(node_def: BTNodeDef, nodes_out: Array[Dictionary], edges_out: Array[Dictionary]) -> void:
	if node_def == null:
		return
	var nid_str: String = "n%d" % node_def.node_id
	var ntype: String = String(node_def.node_type)
	var src_out: Dictionary = {"file": node_def.debug_source_file, "line": node_def.debug_source_line} if not node_def.debug_source_file.is_empty() else {}
	nodes_out.append({
		"id": nid_str, "title": node_def.title if not node_def.title.is_empty() else ntype,
		"shape": _shape_for_type(ntype), "kind": ntype, "pos": [node_def.editor_pos.x, node_def.editor_pos.y],
		"params": node_def.params.duplicate(true), "source": src_out,
	})

	var parent_weights: Array = node_def.params.get("weights", []) as Array if node_def.params.get("weights", []) is Array else []
	var child_order: int = 0
	for ch_var: Variant in node_def.children:
		var ch_def: BTNodeDef = ch_var as BTNodeDef
		if ch_def == null:
			continue
		var edge_params: Dictionary = {}
		var lbl: String = "#%d" % (child_order + 1) if node_def.children.size() > 1 else ""
		if node_def.node_type == &"WeightedSelector" or ch_def.params.has("weight"):
			var w_val: float = float(ch_def.params.get("weight", 1.0))
			if not ch_def.params.has("weight") and child_order < parent_weights.size():
				w_val = float(parent_weights[child_order])
			edge_params["weight"] = w_val
			if node_def.node_type == &"WeightedSelector":
				lbl = "#%d (w=%.2f)" % [child_order + 1, w_val]
		edges_out.append({
			"from": nid_str, "to": "n%d" % ch_def.node_id, "label": lbl, "priority": child_order,
			"order": edges_out.size(), "discovered": false, "params": edge_params,
		})
		child_order += 1
		_collect_mermaid_recursive(ch_def, nodes_out, edges_out)


static func _wire_bt_children_recursive(cur_key: String, def_by_key: Dictionary, adj: Dictionary, visited: Dictionary) -> void:
	if visited.has(cur_key):
		return
	visited[cur_key] = true
	var parent_def: BTNodeDef = def_by_key[cur_key] as BTNodeDef
	parent_def.children.clear()
	var child_keys: Array = adj.get(cur_key, []) as Array
	for ck_var: Variant in child_keys:
		var ck: String = str(ck_var)
		if not visited.has(ck) and def_by_key.has(ck):
			parent_def.children.append(def_by_key[ck] as BTNodeDef)
			_wire_bt_children_recursive(ck, def_by_key, adj, visited)


static func _shape_for_type(ntype: String) -> String:
	match ntype:
		"Root": return "round"
		"Selector", "WeightedSelector": return "diamond"
		"Sequence": return "stadium"
		"Parallel", "SubTree": return "subroutine"
		"Cooldown", "Inverter", "Repeater", "TimeLimit", "ForceSuccess", "ForceFailure", "Service": return "hexagon"
		"Condition": return "round"
		_: return "rect"


static func _fill_default_node_params(ntype: StringName, str_id: String, parsed_id: int, p_dict: Dictionary) -> void:
	if ntype == &"Action" and not p_dict.has("action_key"):
		var is_auto_nid: bool = str_id.begins_with("n") and str_id.substr(1).is_valid_int()
		p_dict["action_key"] = "action_%d" % parsed_id if is_auto_nid else str_id
	elif ntype == &"Cooldown" and not p_dict.has("cooldown_sec"):
		p_dict["cooldown_sec"] = 1.0
	elif ntype == &"Wait" and not p_dict.has("duration_sec"):
		p_dict["duration_sec"] = 0.5
	elif ntype == &"Repeater" and not p_dict.has("repeat_count"):
		p_dict["repeat_count"] = 3
	elif ntype == &"TimeLimit" and not p_dict.has("timeout_sec"):
		p_dict["timeout_sec"] = 3.0
	elif ntype == &"Service" and not p_dict.has("interval_sec"):
		p_dict["interval_sec"] = 0.25


static func _resolve_bt_node_type(kind: String, shape: String, title: String, params: Dictionary) -> StringName:
	if kind in _KNOWN_KINDS:
		if kind == "Action" and (params.has("duration_sec") or title.to_lower().begins_with("wait(")):
			return &"Wait"
		return StringName(kind)
	if kind == "Decorator" or shape == "hexagon":
		if params.has("cooldown_sec") or title.to_lower().find("cooldown") >= 0 or title.find("冷却") >= 0:
			return &"Cooldown"
		if params.has("repeat_count"):
			return &"Repeater"
		if params.has("timeout_sec"):
			return &"TimeLimit"
		if params.has("service_key") or params.has("interval_sec"):
			return &"Service"
		return &"Inverter"
	match shape:
		"diamond": return &"WeightedSelector" if params.has("weights") else &"Selector"
		"stadium": return &"Sequence"
		"subroutine": return &"SubTree" if params.has("sub_graph_path") else &"Parallel"
		"round": return &"Condition"
		_:
			return &"Wait" if (params.has("duration_sec") or title.to_lower().begins_with("wait(")) else &"Action"


static func _parse_schema_array(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Dictionary:
				out.append((entry as Dictionary).duplicate(true))
	return out


func to_flow_graph_ir() -> Dictionary:
	return to_mermaid_ir()


func apply_flow_graph_ir(ir: Dictionary) -> void:
	apply_mermaid_ir(ir)
#endregion
