@tool
extends RefCounted

## Mermaid 通用有向流转图中间表示模型（Domain-Agnostic Canonical Graph IR）。[br]
##
## 统一承载 `stateDiagram-v2` 与 `flowchart TD/LR` 的节点、有序有向边、黑板 Schema、执行参数、源码锚点、编辑原语及快照克隆，零外部依赖。


#region 常量与字段

const TYPE_STATE_V2: StringName = &"stateDiagram-v2"
const TYPE_FLOWCHART: StringName = &"flowchart"

const SCHEMA_GENERIC: StringName = &"generic"
const SCHEMA_FSM: StringName = &"fsm"
const SCHEMA_BT: StringName = &"bt"

const BT_ROOT_KIND: String = "Root"
const BT_COMPOSITE_KINDS: Array[String] = ["Selector", "WeightedSelector", "Sequence", "Parallel"]
const BT_DECORATOR_KINDS: Array[String] = [
	"Inverter", "Cooldown", "Repeater", "TimeLimit",
	"ForceSuccess", "ForceFailure", "Service", "Decorator",
]
const BT_LEAF_KINDS: Array[String] = ["Condition", "Action", "Wait", "SubTree"]

var schema: StringName = SCHEMA_GENERIC
## 当会话绑定至具体 `.tres` 资源或运行期实例时为 `true`，删空节点不会退回 `SCHEMA_GENERIC`；草稿会话为 `false`，删空节点后自动恢复全品类可选态。
var schema_locked: bool = false
var diagram_type: StringName = TYPE_FLOWCHART
var direction: StringName = &"LR"
var title: String = "mermaid_graph"
var initial_node_id: String = ""

## `Array[Dictionary]`: `{"key": String, "type": String, "default": Variant}`
var blackboard_schema: Array[Dictionary] = []

## `Array[Dictionary]`: `{"id": String, "title": String, "shape": String, "kind": String, "pos": Vector2, "has_pos": bool, "params": Dictionary, "source": Dictionary}`
var nodes: Array[Dictionary] = []

## `Array[Dictionary]`: `{"from": String, "to": String, "label": String, "priority": int, "order": int, "discovered": bool, "params": Dictionary}`
var edges: Array[Dictionary] = []

var _node_index_map: Dictionary = {} ## {String: int}

#endregion


#region 节点与边增删改查接口

func clear() -> void:
	nodes.clear()
	edges.clear()
	_node_index_map.clear()
	blackboard_schema.clear()
	initial_node_id = ""
	schema = SCHEMA_GENERIC
	schema_locked = false
	diagram_type = TYPE_FLOWCHART


func is_empty_generic() -> bool:
	return nodes.is_empty() and not schema_locked and schema == SCHEMA_GENERIC


func find_bt_root_id() -> String:
	for nd: Dictionary in nodes:
		if str(nd.get("kind", "")) == BT_ROOT_KIND:
			return str(nd.get("id", ""))
	return ""


func ensure_node(
	node_id: String,
	p_title: String = "",
	p_shape: String = "rect",
	p_kind: String = "",
	p_pos: Vector2 = Vector2.ZERO,
	p_has_pos: bool = false,
	p_params: Dictionary = {},
	p_source: Dictionary = {}
) -> Dictionary:
	var clean_id: String = node_id.strip_edges()
	if _node_index_map.has(clean_id):
		var idx: int = int(_node_index_map[clean_id])
		var existing: Dictionary = nodes[idx]
		if not p_title.is_empty() and str(existing.get("title", "")) == clean_id:
			existing["title"] = p_title
		if p_shape != "rect" and str(existing.get("shape", "rect")) == "rect":
			existing["shape"] = p_shape
			var prev_k: String = str(existing.get("kind", ""))
			if p_kind.is_empty() and prev_k in ["", "Action", "State", "Node"]:
				existing["kind"] = _infer_kind_from_shape(p_shape, diagram_type)
		if not p_kind.is_empty() and str(existing.get("kind", "")) in ["", "Action", "State", "Node"]:
			existing["kind"] = p_kind
		if p_has_pos:
			existing["pos"] = p_pos
			existing["has_pos"] = true
		if not p_params.is_empty():
			var merged: Dictionary = (existing.get("params", {}) as Dictionary).duplicate(true)
			for k: Variant in p_params.keys():
				merged[k] = p_params[k]
			existing["params"] = merged
		if not p_source.is_empty():
			existing["source"] = p_source.duplicate(true)
		return existing

	var resolved_title: String = p_title if not p_title.is_empty() else clean_id
	var resolved_shape: String = p_shape
	if resolved_shape == "rect" and not p_kind.is_empty():
		resolved_shape = default_shape_for_kind(p_kind)
	var resolved_kind: String = p_kind if not p_kind.is_empty() else _infer_kind_from_shape(resolved_shape, diagram_type)
	var entry: Dictionary = {
		"id": clean_id,
		"title": resolved_title,
		"shape": resolved_shape,
		"kind": resolved_kind,
		"pos": p_pos,
		"has_pos": p_has_pos,
		"params": p_params.duplicate(true),
		"source": p_source.duplicate(true),
	}
	_node_index_map[clean_id] = nodes.size()
	nodes.append(entry)
	return entry


func find_node(node_id: String) -> Dictionary:
	if not _node_index_map.has(node_id):
		return {}
	return nodes[int(_node_index_map[node_id])]


func find_incoming_edges(node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in edges:
		if str(e.get("to", "")) == node_id:
			out.append(e)
	return out


func find_outgoing_edges(node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in edges:
		if str(e.get("from", "")) == node_id:
			out.append(e)
	return out


func set_node_pos(node_id: String, new_pos: Vector2) -> void:
	if _node_index_map.has(node_id):
		var entry: Dictionary = nodes[int(_node_index_map[node_id])]
		entry["pos"] = new_pos
		entry["has_pos"] = true


func generate_unique_node_id(prefix: String = "n") -> String:
	var clean_p: String = prefix.strip_edges()
	if clean_p.is_empty():
		clean_p = "n"
	var seq: int = 1
	while true:
		var candidate: String = "%s%d" % [clean_p, seq]
		if not _node_index_map.has(candidate):
			return candidate
		seq += 1
	return "%s1" % clean_p


func remove_node(node_id: String) -> bool:
	var clean_id: String = node_id.strip_edges()
	if not _node_index_map.has(clean_id):
		return false
	var idx: int = int(_node_index_map[clean_id])
	nodes.remove_at(idx)
	_rebuild_node_index_map()

	for i: int in range(edges.size() - 1, -1, -1):
		var ed: Dictionary = edges[i]
		if str(ed.get("from", "")) == clean_id or str(ed.get("to", "")) == clean_id:
			edges.remove_at(i)
	_refresh_edge_orders()

	if nodes.is_empty() and not schema_locked:
		schema = SCHEMA_GENERIC
		diagram_type = TYPE_FLOWCHART
		initial_node_id = ""
	elif initial_node_id == clean_id:
		var bt_root_id: String = find_bt_root_id() if resolve_effective_schema() == SCHEMA_BT else ""
		initial_node_id = bt_root_id if not bt_root_id.is_empty() else (str(nodes[0]["id"]) if not nodes.is_empty() else "")
	return true


func rename_node(old_id: String, new_id: String) -> bool:
	var clean_old: String = old_id.strip_edges()
	var clean_new: String = new_id.strip_edges()
	if clean_old.is_empty() or clean_new.is_empty() or clean_new == "*" or clean_new == "[*]":
		return false
	if clean_new.contains(" ") or clean_new.contains("\t") or clean_new.contains("->"):
		return false
	if not _node_index_map.has(clean_old) or _node_index_map.has(clean_new):
		return false

	var nd: Dictionary = nodes[int(_node_index_map[clean_old])]
	nd["id"] = clean_new
	if str(nd.get("title", "")) == clean_old:
		nd["title"] = clean_new
	_rebuild_node_index_map()

	for ed: Dictionary in edges:
		if str(ed.get("from", "")) == clean_old:
			ed["from"] = clean_new
		if str(ed.get("to", "")) == clean_old:
			ed["to"] = clean_new
	if initial_node_id == clean_old:
		initial_node_id = clean_new
	return true


func duplicate_node(node_id: String, offset: Vector2 = Vector2(48, 48)) -> String:
	var src: Dictionary = find_node(node_id.strip_edges())
	if src.is_empty():
		return ""
	var src_id: String = str(src["id"])
	var prefix: String = "n"
	if resolve_effective_schema() != SCHEMA_BT and not (src_id.begins_with("n") and src_id.substr(1).is_valid_int()):
		var us_idx: int = src_id.rfind("_")
		var stem: String = src_id.substr(0, us_idx) if (us_idx > 0 and src_id.substr(us_idx + 1).is_valid_int()) else src_id
		prefix = "%s_" % stem
	var new_id: String = generate_unique_node_id(prefix)
	var src_pos: Vector2 = src.get("pos", Vector2.ZERO) as Vector2
	var cloned_params: Dictionary = (src.get("params", {}) as Dictionary).duplicate(true)
	ensure_node(
		new_id,
		str(src.get("title", src_id)),
		str(src.get("shape", "rect")),
		str(src.get("kind", "")),
		src_pos + offset,
		true,
		cloned_params
	)
	return new_id


func update_node_fields(node_id: String, patch: Dictionary) -> bool:
	var clean_id: String = node_id.strip_edges()
	if not _node_index_map.has(clean_id):
		return false
	var entry: Dictionary = nodes[int(_node_index_map[clean_id])]
	if patch.has("title"):
		entry["title"] = str(patch["title"])
	if patch.has("kind"):
		var next_k: String = str(patch["kind"])
		entry["kind"] = next_k
		if not patch.has("shape"):
			entry["shape"] = default_shape_for_kind(next_k)
	if patch.has("shape"):
		entry["shape"] = str(patch["shape"])
	if patch.has("pos") and patch["pos"] is Vector2:
		entry["pos"] = patch["pos"] as Vector2
		entry["has_pos"] = true
	if patch.has("params") and patch["params"] is Dictionary:
		var incoming_p: Dictionary = patch["params"] as Dictionary
		if bool(patch.get("merge_params", false)):
			var merged_p: Dictionary = (entry.get("params", {}) as Dictionary).duplicate(true)
			for pk: Variant in incoming_p.keys():
				merged_p[pk] = incoming_p[pk]
			entry["params"] = merged_p
		else:
			entry["params"] = incoming_p.duplicate(true)
	if patch.has("params_patch") and patch["params_patch"] is Dictionary:
		var patch_p: Dictionary = patch["params_patch"] as Dictionary
		var base_p: Dictionary = (entry.get("params", {}) as Dictionary).duplicate(true)
		for pk2: Variant in patch_p.keys():
			if patch_p[pk2] == null:
				base_p.erase(pk2)
			else:
				base_p[pk2] = patch_p[pk2]
		entry["params"] = base_p
	return true


func add_edge(
	from_id: String,
	to_id: String,
	label: String = "",
	priority: int = 0,
	discovered: bool = false,
	p_params: Dictionary = {}
) -> void:
	var f: String = from_id.strip_edges()
	var t: String = to_id.strip_edges()
	if f.is_empty() or t.is_empty():
		return
	for e: Dictionary in edges:
		if str(e.get("from", "")) == f and str(e.get("to", "")) == t:
			if not label.is_empty():
				e["label"] = label
			if priority != 0:
				e["priority"] = priority
			if not discovered:
				e["discovered"] = false
			if not p_params.is_empty():
				var em: Dictionary = (e.get("params", {}) as Dictionary).duplicate(true)
				for ek: Variant in p_params.keys():
					em[ek] = p_params[ek]
				e["params"] = em
			return
	if f != "*":
		ensure_node(f)
	ensure_node(t)
	edges.append({
		"from": f,
		"to": t,
		"label": label,
		"priority": priority,
		"order": edges.size(),
		"discovered": discovered,
		"params": p_params.duplicate(true),
	})


func remove_edge(from_id: String, to_id: String) -> void:
	for i: int in range(edges.size() - 1, -1, -1):
		var e: Dictionary = edges[i]
		if str(e.get("from", "")) == from_id and str(e.get("to", "")) == to_id:
			edges.remove_at(i)
	_refresh_edge_orders()


func find_edge(from_id: String, to_id: String) -> Dictionary:
	var f: String = from_id.strip_edges()
	var t: String = to_id.strip_edges()
	for e: Dictionary in edges:
		if str(e.get("from", "")) == f and str(e.get("to", "")) == t:
			return e
	return {}


func update_edge_fields(from_id: String, to_id: String, patch: Dictionary) -> bool:
	var ed: Dictionary = find_edge(from_id, to_id)
	if ed.is_empty():
		return false
	if patch.has("label"):
		ed["label"] = str(patch["label"])
	if patch.has("priority"):
		ed["priority"] = int(patch["priority"])
	if patch.has("order"):
		ed["order"] = int(patch["order"])
	if patch.has("discovered"):
		ed["discovered"] = bool(patch["discovered"])
	if patch.has("params") and patch["params"] is Dictionary:
		var incoming_ep: Dictionary = patch["params"] as Dictionary
		if bool(patch.get("merge_params", false)):
			var merged_ep: Dictionary = (ed.get("params", {}) as Dictionary).duplicate(true)
			for epk: Variant in incoming_ep.keys():
				merged_ep[epk] = incoming_ep[epk]
			ed["params"] = merged_ep
		else:
			ed["params"] = incoming_ep.duplicate(true)
	if patch.has("params_patch") and patch["params_patch"] is Dictionary:
		var patch_ep: Dictionary = patch["params_patch"] as Dictionary
		var base_ep: Dictionary = (ed.get("params", {}) as Dictionary).duplicate(true)
		for epk2: Variant in patch_ep.keys():
			if patch_ep[epk2] == null:
				base_ep.erase(epk2)
			else:
				base_ep[epk2] = patch_ep[epk2]
		ed["params"] = base_ep
	return true


## 在 `SCHEMA_BT` 模式下按子节点坐标重排所有多分支父节点的出边评估顺序（纵向 `TD` 按 `pos.x`，横向 `LR` 按 `pos.y`）。
func reorder_bt_children_by_position(is_vertical_flow: bool) -> bool:
	return reorder_bt_children_by_layout("", is_vertical_flow)


func reorder_bt_children_by_layout(parent_id: String = "", is_vertical: bool = false) -> bool:
	if resolve_effective_schema() != SCHEMA_BT or edges.size() < 2:
		return false

	var slots_by_parent: Dictionary = {}
	for i: int in range(edges.size()):
		var ed: Dictionary = edges[i]
		if bool(ed.get("discovered", false)):
			continue
		var p_id: String = str(ed.get("from", ""))
		if p_id == "*" or (not parent_id.is_empty() and p_id != parent_id):
			continue
		if not slots_by_parent.has(p_id):
			slots_by_parent[p_id] = []
		(slots_by_parent[p_id] as Array).append(i)

	var changed: bool = false
	for p_var: Variant in slots_by_parent.keys():
		var slot_indices: Array = slots_by_parent[p_var] as Array
		if slot_indices.size() < 2:
			continue
		var wrapped: Array[Dictionary] = []
		for rank_i: int in range(slot_indices.size()):
			var e_idx: int = int(slot_indices[rank_i])
			var ed_item: Dictionary = edges[e_idx]
			var child_nd: Dictionary = find_node(str(ed_item.get("to", "")))
			var cpos: Vector2 = child_nd.get("pos", Vector2.ZERO) as Vector2
			wrapped.append({
				"orig_rank": rank_i,
				"edge": ed_item,
				"primary": cpos.x if is_vertical else cpos.y,
				"secondary": cpos.y if is_vertical else cpos.x,
			})

		wrapped.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa: float = float(a["primary"])
			var pb: float = float(b["primary"])
			if not is_equal_approx(pa, pb):
				return pa < pb
			var sa: float = float(a["secondary"])
			var sb: float = float(b["secondary"])
			if not is_equal_approx(sa, sb):
				return sa < sb
			return int(a["orig_rank"]) < int(b["orig_rank"])
		)

		var group_changed: bool = false
		for k: int in range(wrapped.size()):
			if int(wrapped[k]["orig_rank"]) != k:
				group_changed = true
				break
		if not group_changed:
			continue

		changed = true
		for k2: int in range(wrapped.size()):
			var sorted_ed: Dictionary = wrapped[k2]["edge"] as Dictionary
			sorted_ed["priority"] = k2
			var cur_lbl: String = str(sorted_ed.get("label", "")).strip_edges()
			if cur_lbl.begins_with("#") and cur_lbl.substr(1).is_valid_int():
				sorted_ed["label"] = "#%d" % (k2 + 1)
			edges[int(slot_indices[k2])] = sorted_ed

	if changed:
		_refresh_edge_orders()
	return changed


func resolve_effective_schema() -> StringName:
	if schema == SCHEMA_FSM or schema == SCHEMA_BT:
		return schema
	if nodes.is_empty() and not schema_locked:
		return SCHEMA_GENERIC
	if diagram_type == TYPE_STATE_V2:
		return SCHEMA_FSM
	for nd: Dictionary in nodes:
		var k: String = str(nd.get("kind", ""))
		if k == BT_ROOT_KIND or BT_COMPOSITE_KINDS.has(k) or BT_DECORATOR_KINDS.has(k) or BT_LEAF_KINDS.has(k):
			return SCHEMA_BT
	return SCHEMA_BT if diagram_type == TYPE_FLOWCHART else SCHEMA_GENERIC


static func default_shape_for_kind(kind: String) -> String:
	match kind:
		"Selector", "WeightedSelector":
			return "diamond"
		"Sequence":
			return "stadium"
		"Parallel", "SubTree":
			return "subroutine"
		"Inverter", "Cooldown", "Repeater", "TimeLimit", "ForceSuccess", "ForceFailure", "Service", "Decorator":
			return "hexagon"
		"Condition", "State", "Root":
			return "round"
		"Action", "Wait":
			return "rect"
		_:
			return "rect"


static func _infer_kind_from_shape(shape: String, diag_type: StringName = TYPE_FLOWCHART) -> String:
	match shape:
		"diamond":
			return "Selector"
		"stadium":
			return "Sequence"
		"subroutine":
			return "Parallel"
		"hexagon":
			return "Decorator"
		"round":
			return "State" if diag_type == TYPE_STATE_V2 else "Condition"
		_:
			return "State" if diag_type == TYPE_STATE_V2 else "Action"


func _rebuild_node_index_map() -> void:
	_node_index_map.clear()
	for i: int in range(nodes.size()):
		_node_index_map[str(nodes[i]["id"])] = i


func _refresh_edge_orders() -> void:
	for i: int in range(edges.size()):
		edges[i]["order"] = i

#endregion


#region 标准图中间表示字典与快照互转 (Canonical IR & Snapshot Serialization)

func load_from_topology_dict(data: Dictionary) -> void:
	clear()
	diagram_type = StringName(str(data.get("diagram_type", "flowchart")))
	var raw_schema: String = str(data.get("schema", ""))
	if not raw_schema.is_empty():
		schema = StringName(raw_schema)
	else:
		schema = SCHEMA_FSM if diagram_type == TYPE_STATE_V2 else SCHEMA_BT
	direction = StringName(str(data.get("direction", "LR")))
	title = str(data.get("title", "mermaid_graph"))
	initial_node_id = str(data.get("initial_node_id", ""))

	var raw_bb: Variant = data.get("blackboard_schema", [])
	if raw_bb is Array:
		for bb_item: Variant in raw_bb as Array:
			if bb_item is Dictionary:
				blackboard_schema.append((bb_item as Dictionary).duplicate(true))

	var raw_nodes: Variant = data.get("nodes", [])
	if raw_nodes is Array:
		for item: Variant in raw_nodes as Array:
			if item is Dictionary:
				var nd: Dictionary = item as Dictionary
				var pos_vec: Vector2 = Vector2.ZERO
				var has_p: bool = bool(nd.get("has_pos", false))
				var raw_pos: Variant = nd.get("pos", [])
				if raw_pos is Array and (raw_pos as Array).size() >= 2:
					var pa: Array = raw_pos as Array
					pos_vec = Vector2(float(pa[0]), float(pa[1]))
					if not nd.has("has_pos"):
						has_p = pos_vec != Vector2.ZERO
				elif raw_pos is Vector2:
					pos_vec = raw_pos as Vector2
					if not nd.has("has_pos"):
						has_p = pos_vec != Vector2.ZERO
				var p_dict: Dictionary = nd.get("params", {}) as Dictionary if nd.get("params", {}) is Dictionary else {}
				var s_dict: Dictionary = nd.get("source", {}) as Dictionary if nd.get("source", {}) is Dictionary else {}
				ensure_node(
					str(nd.get("id", "")),
					str(nd.get("title", "")),
					str(nd.get("shape", "rect")),
					str(nd.get("kind", "")),
					pos_vec,
					has_p,
					p_dict,
					s_dict
				)

	var raw_edges: Variant = data.get("edges", [])
	if raw_edges is Array:
		for item: Variant in raw_edges as Array:
			if item is Dictionary:
				var ed: Dictionary = item as Dictionary
				var ep_dict: Dictionary = ed.get("params", {}) as Dictionary if ed.get("params", {}) is Dictionary else {}
				add_edge(
					str(ed.get("from", "")),
					str(ed.get("to", "")),
					str(ed.get("label", "")),
					int(ed.get("priority", 0)),
					bool(ed.get("discovered", false)),
					ep_dict
				)
		_refresh_edge_orders()


func to_topology_dict() -> Dictionary:
	var bb_out: Array[Dictionary] = []
	for bb_entry: Dictionary in blackboard_schema:
		bb_out.append(bb_entry.duplicate(true))

	var nodes_out: Array[Dictionary] = []
	for nd: Dictionary in nodes:
		var pos_v: Vector2 = nd.get("pos", Vector2.ZERO) as Vector2
		nodes_out.append({
			"id": str(nd.get("id", "")),
			"title": str(nd.get("title", "")),
			"shape": str(nd.get("shape", "rect")),
			"kind": str(nd.get("kind", "")),
			"pos": [pos_v.x, pos_v.y],
			"params": (nd.get("params", {}) as Dictionary).duplicate(true),
			"source": (nd.get("source", {}) as Dictionary).duplicate(true),
		})

	var edges_out: Array[Dictionary] = []
	for i: int in range(edges.size()):
		var ed: Dictionary = edges[i]
		edges_out.append({
			"from": str(ed.get("from", "")),
			"to": str(ed.get("to", "")),
			"label": str(ed.get("label", "")),
			"priority": int(ed.get("priority", 0)),
			"order": int(ed.get("order", i)),
			"discovered": bool(ed.get("discovered", false)),
			"params": (ed.get("params", {}) as Dictionary).duplicate(true),
		})

	return {
		"schema": String(resolve_effective_schema()),
		"diagram_type": String(diagram_type),
		"direction": String(direction),
		"title": title,
		"initial_node_id": initial_node_id,
		"blackboard_schema": bb_out,
		"nodes": nodes_out,
		"edges": edges_out,
	}


func to_snapshot_dict() -> Dictionary:
	var snap: Dictionary = to_topology_dict()
	snap["raw_schema"] = String(schema)
	snap["raw_diagram_type"] = String(diagram_type)
	snap["schema_locked"] = schema_locked
	var snap_nodes: Array = snap["nodes"] as Array
	for i: int in range(mini(snap_nodes.size(), nodes.size())):
		(snap_nodes[i] as Dictionary)["has_pos"] = bool(nodes[i].get("has_pos", false))
	return snap


func restore_snapshot_dict(snap: Dictionary) -> void:
	load_from_topology_dict(snap)
	if snap.has("raw_schema"):
		schema = StringName(str(snap["raw_schema"]))
	if snap.has("raw_diagram_type"):
		diagram_type = StringName(str(snap["raw_diagram_type"]))
	if snap.has("schema_locked"):
		schema_locked = bool(snap["schema_locked"])
	if nodes.is_empty() and not schema_locked:
		schema = SCHEMA_GENERIC
		diagram_type = TYPE_FLOWCHART
		initial_node_id = ""

#endregion
