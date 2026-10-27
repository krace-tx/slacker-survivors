@tool
extends RefCounted

## Mermaid 文本双向无损编解码器（Mermaid Parser & Deterministic Printer）。[br]
##
## 支持标准 `stateDiagram-v2` 与 `flowchart TD/LR` 语法、6 种括号形状语义识别，以及 `%% @mg_meta` / `%% @mg_bb` / `%% @mg` / `%% @mg_edge` / `%% @any` 无损参数与坐标还原。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)


#region 序列化：MermaidGraphModel -> Mermaid 源码

static func stringify(graph: MermaidGraphModel, include_pos_pragma: bool = true) -> String:
	if graph == null or (graph.nodes.is_empty() and graph.edges.is_empty()):
		return ""
	var lines: PackedStringArray = PackedStringArray()

	if graph.diagram_type == MermaidGraphModel.TYPE_STATE_V2:
		lines.append("stateDiagram-v2")
		if not graph.initial_node_id.is_empty():
			lines.append("    [*] --> %s" % graph.initial_node_id)
		for nd: Dictionary in graph.nodes:
			var nid: String = str(nd["id"])
			var ntitle: String = str(nd.get("title", nid)).replace("\"", "'")
			if ntitle != nid and not ntitle.is_empty():
				lines.append("    state \"%s\" as %s" % [ntitle, nid])
			else:
				lines.append("    state %s" % nid)
		for ed: Dictionary in graph.edges:
			if bool(ed.get("discovered", false)):
				continue
			var f: String = str(ed["from"])
			var t: String = str(ed["to"])
			var lbl: String = str(ed.get("label", "")).strip_edges()
			if f == "*":
				if lbl.is_empty():
					lines.append("    %%%% @any --> %s" % t)
				else:
					lines.append("    %%%% @any --> %s : %s" % [t, lbl])
			elif lbl.is_empty():
				lines.append("    %s --> %s" % [f, t])
			else:
				lines.append("    %s --> %s : %s" % [f, t, lbl])
	else:
		var dir_str: String = String(graph.direction) if not graph.direction.is_empty() else "LR"
		lines.append("flowchart %s" % dir_str)
		for nd: Dictionary in graph.nodes:
			var nid: String = str(nd["id"])
			var ntitle: String = str(nd.get("title", nid)).replace("\"", "'")
			var kind_s: String = str(nd.get("kind", ""))
			var shape: String = str(nd.get("shape", "rect"))
			if shape == "rect" and not kind_s.is_empty():
				shape = MermaidGraphModel.default_shape_for_kind(kind_s)
			lines.append("    %s%s" % [nid, _wrap_flowchart_shape(ntitle, shape)])
		for ed: Dictionary in graph.edges:
			var f: String = str(ed["from"])
			var t: String = str(ed["to"])
			var lbl: String = str(ed.get("label", "")).replace("\"", "'").strip_edges()
			if lbl.is_empty():
				lines.append("    %s --> %s" % [f, t])
			else:
				lines.append("    %s -->|\"%s\"| %s" % [f, lbl, t])

	if include_pos_pragma and not graph.nodes.is_empty():
		lines.append("")
		var eff_schema: String = String(graph.resolve_effective_schema())
		if not eff_schema.is_empty() or (not graph.title.is_empty() and graph.title != "mermaid_graph"):
			lines.append("    %%%% @mg_meta schema=%s title=%s" % [eff_schema, JSON.stringify(graph.title)])
		if not graph.blackboard_schema.is_empty():
			lines.append("    %%%% @mg_bb %s" % JSON.stringify(graph.blackboard_schema))
		for nd: Dictionary in graph.nodes:
			var nid: String = str(nd["id"])
			var kind: String = str(nd.get("kind", ""))
			var pos: Vector2 = nd.get("pos", Vector2.ZERO) as Vector2
			var n_params: Dictionary = nd.get("params", {}) as Dictionary
			var base_mg: String = "    %%%% @mg %s kind=%s pos=%d,%d" % [
				nid,
				kind if not kind.is_empty() else "Node",
				roundi(pos.x),
				roundi(pos.y),
			]
			if not n_params.is_empty():
				base_mg += " params=%s" % JSON.stringify(n_params)
			lines.append(base_mg)
		for ed: Dictionary in graph.edges:
			if bool(ed.get("discovered", false)):
				continue
			var prio: int = int(ed.get("priority", 0))
			var e_params: Dictionary = ed.get("params", {}) as Dictionary
			if prio != 0 or not e_params.is_empty():
				var edge_mg: String = "    %%%% @mg_edge %s->%s prio=%d" % [
					str(ed.get("from", "")),
					str(ed.get("to", "")),
					prio,
				]
				if not e_params.is_empty():
					edge_mg += " params=%s" % JSON.stringify(e_params)
				lines.append(edge_mg)

	return "\n".join(lines)


static func _wrap_flowchart_shape(label: String, shape: String) -> String:
	match shape:
		"diamond":
			return "{\"%s\"}" % label
		"stadium":
			return "([\"%s\"])" % label
		"subroutine":
			return "[[\"%s\"]]" % label
		"hexagon":
			return "{{\"%s\"}}" % label
		"round":
			return "(\"%s\")" % label
		_:
			return "[\"%s\"]" % label

#endregion


#region 解析：Mermaid 源码 -> MermaidGraphModel

static func parse(source: String) -> Dictionary:
	var graph := MermaidGraphModel.new()
	if source.strip_edges().is_empty():
		return {"ok": true, "graph": graph, "plan": {}, "error": "", "line": 0}
	var raw_lines: PackedStringArray = source.replace("\r\n", "\n").split("\n")
	var header_found: bool = false

	for i: int in range(raw_lines.size()):
		var line_num: int = i + 1
		var trimmed: String = raw_lines[i].strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("```"):
			continue

		if trimmed.begins_with("%%"):
			_parse_pragma_comment(trimmed, graph)
			continue

		if not header_found:
			if trimmed.begins_with("stateDiagram"):
				graph.diagram_type = MermaidGraphModel.TYPE_STATE_V2
				if graph.schema == MermaidGraphModel.SCHEMA_GENERIC:
					graph.schema = MermaidGraphModel.SCHEMA_FSM
				graph.direction = &"LR"
				header_found = true
				continue
			if trimmed.begins_with("flowchart") or trimmed.begins_with("graph"):
				graph.diagram_type = MermaidGraphModel.TYPE_FLOWCHART
				if graph.schema == MermaidGraphModel.SCHEMA_GENERIC:
					graph.schema = MermaidGraphModel.SCHEMA_BT
				var parts: PackedStringArray = trimmed.split(" ", false)
				graph.direction = StringName(parts[1].to_upper()) if parts.size() >= 2 else &"LR"
				header_found = true
				continue
			return {
				"ok": false,
				"graph": graph,
				"plan": {},
				"error": FlowEditorI18n.t(&"codec.err_missing_header", [line_num]),
				"line": line_num,
			}

		if trimmed.begins_with("direction "):
			var dir_parts: PackedStringArray = trimmed.split(" ", false)
			if dir_parts.size() >= 2:
				graph.direction = StringName(dir_parts[1].to_upper())
			continue

		if graph.diagram_type == MermaidGraphModel.TYPE_STATE_V2:
			_parse_state_line(trimmed, graph)
		else:
			_parse_flowchart_line(trimmed, graph)

	if not header_found:
		return {"ok": false, "graph": graph, "plan": {}, "error": FlowEditorI18n.t(&"codec.err_empty_source"), "line": 1}

	var plan: Dictionary = MermaidLayout.apply_layout(graph, false)
	return {"ok": true, "graph": graph, "plan": plan, "error": "", "line": 0}


static func _parse_pragma_comment(comment_line: String, graph: MermaidGraphModel) -> void:
	var body: String = comment_line.trim_prefix("%%").strip_edges()
	if body.begins_with("@any -->"):
		var rest_any: String = body.substr(8).strip_edges()
		var colon_i: int = rest_any.find(":")
		var to_any: String = rest_any.substr(0, colon_i).strip_edges() if colon_i > 0 else rest_any
		var lbl_any: String = rest_any.substr(colon_i + 1).strip_edges() if colon_i > 0 else ""
		if not to_any.is_empty():
			graph.add_edge("*", to_any, lbl_any)
		return

	if body.begins_with("@mg_bb "):
		var raw_bb: String = body.substr(7).strip_edges()
		var parsed_bb: Variant = JSON.parse_string(raw_bb)
		if parsed_bb is Array:
			graph.blackboard_schema.clear()
			for bb_v: Variant in parsed_bb as Array:
				if bb_v is Dictionary:
					graph.blackboard_schema.append((bb_v as Dictionary).duplicate(true))
		return

	if body.begins_with("@mg_meta "):
		var meta_rest: String = body.substr(9).strip_edges()
		var bb_idx: int = meta_rest.find("bb_schema=")
		if bb_idx >= 0:
			var raw_meta_bb: String = meta_rest.substr(bb_idx + 10).strip_edges()
			meta_rest = meta_rest.substr(0, bb_idx).strip_edges()
			var parsed_meta_bb: Variant = JSON.parse_string(raw_meta_bb)
			if parsed_meta_bb is Array:
				graph.blackboard_schema.clear()
				for mbb_v: Variant in parsed_meta_bb as Array:
					if mbb_v is Dictionary:
						graph.blackboard_schema.append((mbb_v as Dictionary).duplicate(true))
		var title_idx: int = meta_rest.find("title=")
		if title_idx >= 0:
			var raw_title_str: String = meta_rest.substr(title_idx + 6).strip_edges()
			meta_rest = meta_rest.substr(0, title_idx).strip_edges()
			var parsed_t: Variant = JSON.parse_string(raw_title_str)
			if parsed_t is String:
				graph.title = parsed_t as String
			elif not raw_title_str.is_empty():
				graph.title = raw_title_str.trim_prefix("\"").trim_suffix("\"")
		for tok: String in meta_rest.split(" ", false):
			if tok.begins_with("schema="):
				var sv: String = tok.substr(7).strip_edges()
				if not sv.is_empty():
					graph.schema = StringName(sv)
		return

	if body.begins_with("@mg_edge "):
		var edge_rest: String = body.substr(9).strip_edges()
		var ep_dict: Dictionary = {}
		var ep_idx: int = edge_rest.find(" params=")
		if ep_idx >= 0:
			var raw_ep: String = edge_rest.substr(ep_idx + 8).strip_edges()
			edge_rest = edge_rest.substr(0, ep_idx).strip_edges()
			var parsed_ep: Variant = JSON.parse_string(raw_ep)
			if parsed_ep is Dictionary:
				ep_dict = parsed_ep as Dictionary
		var e_tokens: PackedStringArray = edge_rest.split(" ", false)
		if e_tokens.is_empty():
			return
		var pair_tok: String = e_tokens[0]
		var arrow_pos: int = pair_tok.find("->")
		if arrow_pos <= 0:
			return
		var f_id: String = pair_tok.substr(0, arrow_pos).strip_edges()
		var t_id: String = pair_tok.substr(arrow_pos + 2).strip_edges()
		var prio_val: int = 0
		for idx: int in range(1, e_tokens.size()):
			var ekv: String = e_tokens[idx]
			if ekv.begins_with("prio="):
				prio_val = int(ekv.substr(5))
		graph.add_edge(f_id, t_id, "", prio_val, false, ep_dict)
		return

	if not body.begins_with("@mg "):
		return

	var node_rest: String = body.substr(4).strip_edges()
	var np_dict: Dictionary = {}
	var np_idx: int = node_rest.find(" params=")
	if np_idx >= 0:
		var raw_np: String = node_rest.substr(np_idx + 8).strip_edges()
		node_rest = node_rest.substr(0, np_idx).strip_edges()
		var parsed_np: Variant = JSON.parse_string(raw_np)
		if parsed_np is Dictionary:
			np_dict = parsed_np as Dictionary

	var tokens: PackedStringArray = node_rest.split(" ", false)
	if tokens.is_empty():
		return
	var nid: String = tokens[0]
	var nd: Dictionary = graph.ensure_node(nid)
	for idx: int in range(1, tokens.size()):
		var kv: String = tokens[idx]
		var eq: int = kv.find("=")
		if eq <= 0:
			continue
		var k: String = kv.substr(0, eq)
		var v: String = kv.substr(eq + 1)
		if k == "kind":
			nd["kind"] = v
			if str(nd.get("shape", "rect")) == "rect":
				nd["shape"] = MermaidGraphModel.default_shape_for_kind(v)
		elif k == "pos":
			var xy: PackedStringArray = v.split(",")
			if xy.size() >= 2:
				nd["pos"] = Vector2(float(xy[0]), float(xy[1]))
				nd["has_pos"] = true
	if not np_dict.is_empty():
		var merged_p: Dictionary = (nd.get("params", {}) as Dictionary).duplicate(true)
		for pk: Variant in np_dict.keys():
			merged_p[pk] = np_dict[pk]
		nd["params"] = merged_p


static func _parse_state_line(line: String, graph: MermaidGraphModel) -> void:
	if line.begins_with("state "):
		var rest: String = line.substr(6).strip_edges()
		var as_idx: int = rest.rfind(" as ")
		if as_idx > 0:
			var raw_title: String = rest.substr(0, as_idx).strip_edges().trim_prefix("\"").trim_suffix("\"")
			var sid: String = rest.substr(as_idx + 4).strip_edges()
			graph.ensure_node(sid, raw_title, "round", "State")
		else:
			var clean_sid: String = rest.trim_prefix("\"").trim_suffix("\"")
			graph.ensure_node(clean_sid, clean_sid, "round", "State")
		return

	var arrow_idx: int = line.find("-->")
	if arrow_idx > 0:
		var left: String = line.substr(0, arrow_idx).strip_edges()
		var right_full: String = line.substr(arrow_idx + 3).strip_edges()
		var to_id: String = right_full
		var lbl: String = ""
		var colon_idx: int = right_full.find(":")
		if colon_idx > 0:
			to_id = right_full.substr(0, colon_idx).strip_edges()
			lbl = right_full.substr(colon_idx + 1).strip_edges()
		if left == "[*]" and to_id != "[*]":
			graph.initial_node_id = to_id
			graph.ensure_node(to_id, to_id, "round", "State")
		elif to_id != "[*]" and left != "[*]":
			graph.ensure_node(left, left, "round", "State")
			graph.ensure_node(to_id, to_id, "round", "State")
			graph.add_edge(left, to_id, lbl)
		return

	var c_idx: int = line.find(":")
	if c_idx > 0:
		var s_id: String = line.substr(0, c_idx).strip_edges()
		var desc: String = line.substr(c_idx + 1).strip_edges()
		graph.ensure_node(s_id, desc, "round", "State")


static func _parse_flowchart_line(line: String, graph: MermaidGraphModel) -> void:
	var arrow_idx: int = line.find("-->")
	if arrow_idx < 0:
		_parse_flowchart_node_token(line, graph)
		return

	var left_part: String = line.substr(0, arrow_idx).strip_edges()
	var right_rest: String = line.substr(arrow_idx + 3).strip_edges()
	var edge_label: String = ""
	if right_rest.begins_with("|"):
		var close_pipe: int = right_rest.find("|", 1)
		if close_pipe > 0:
			edge_label = right_rest.substr(1, close_pipe - 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			right_rest = right_rest.substr(close_pipe + 1).strip_edges()

	var from_id: String = _parse_flowchart_node_token(left_part, graph)
	var to_id: String = _parse_flowchart_node_token(right_rest, graph)
	if not from_id.is_empty() and not to_id.is_empty():
		graph.add_edge(from_id, to_id, edge_label)


static func _parse_flowchart_node_token(token: String, graph: MermaidGraphModel) -> String:
	var s: String = token.strip_edges()
	if s.is_empty():
		return ""

	var markers: Array[Array] = [
		["([", "])", "stadium"],
		["[[", "]]", "subroutine"],
		["{{", "}}", "hexagon"],
		["{", "}", "diamond"],
		["(", ")", "round"],
		["[", "]", "rect"],
	]
	for pair: Array in markers:
		var open_tok: String = str(pair[0])
		var close_tok: String = str(pair[1])
		var shape_name: String = str(pair[2])
		var open_pos: int = s.find(open_tok)
		if open_pos > 0 and s.ends_with(close_tok):
			var nid: String = s.substr(0, open_pos).strip_edges()
			var inner: String = s.substr(
				open_pos + open_tok.length(),
				s.length() - open_pos - open_tok.length() - close_tok.length()
			).strip_edges()
			inner = inner.trim_prefix("\"").trim_suffix("\"")
			graph.ensure_node(nid, inner, shape_name)
			return nid

	graph.ensure_node(s)
	return s

#endregion
