@tool
extends RefCounted

## Mermaid 源码解析与元数据无损继承辅助器（Session Source Applier）。[br]
##
## 负责将编辑器文本解析为 [`MermaidGraphModel`](../model/mermaid_graph_model.gd)，并在未书写 pragma 时从旧图继承坐标、节点参数与边规则。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidCodec = preload(FlowGraphContracts.SCRIPT_CODEC)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)


## 解析 Mermaid 文本并生成新图与布局计划；返回 `{"ok": bool, "error": String, "graph": MermaidGraphModel, "plan": Dictionary}`。
static func parse_and_build(source: String, prev_graph: MermaidGraphModel) -> Dictionary:
	if source.strip_edges().is_empty():
		return {"ok": true, "error": "", "graph": MermaidGraphModel.new(), "plan": {}}

	var res: Dictionary = MermaidCodec.parse(source)
	if not bool(res.get("ok", false)):
		return {"ok": false, "error": str(res.get("error", ""))}

	var next_g: MermaidGraphModel = res["graph"] as MermaidGraphModel
	inherit_preserved_metadata(prev_graph, next_g)
	var next_plan: Dictionary = MermaidLayout.apply_layout(next_g, false)
	return {"ok": true, "error": "", "graph": next_g, "plan": next_plan}


## 从前序图模型继承未在纯文本中显式书写的坐标、标题、参数与边条件。
static func inherit_preserved_metadata(prev_g: MermaidGraphModel, next_g: MermaidGraphModel) -> void:
	if prev_g == null or next_g == null:
		return
	if next_g.title == "mermaid_graph" and not prev_g.title.is_empty():
		next_g.title = prev_g.title
	if next_g.blackboard_schema.is_empty() and not prev_g.blackboard_schema.is_empty():
		next_g.blackboard_schema = prev_g.blackboard_schema.duplicate(true)
	for nd: Dictionary in next_g.nodes:
		var old_nd: Dictionary = prev_g.find_node(str(nd.get("id", "")))
		if old_nd.is_empty():
			continue
		if not bool(nd.get("has_pos", false)) and bool(old_nd.get("has_pos", false)):
			nd["pos"] = old_nd.get("pos", Vector2.ZERO)
			nd["has_pos"] = true
		if (nd.get("params", {}) as Dictionary).is_empty() and not (old_nd.get("params", {}) as Dictionary).is_empty():
			nd["params"] = (old_nd["params"] as Dictionary).duplicate(true)
		if (nd.get("source", {}) as Dictionary).is_empty() and not (old_nd.get("source", {}) as Dictionary).is_empty():
			nd["source"] = (old_nd["source"] as Dictionary).duplicate(true)
	for ed: Dictionary in next_g.edges:
		if not (ed.get("params", {}) as Dictionary).is_empty():
			continue
		var old_ed: Dictionary = prev_g.find_edge(str(ed.get("from", "")), str(ed.get("to", "")))
		if not old_ed.is_empty():
			if int(ed.get("priority", 0)) == 0:
				ed["priority"] = int(old_ed.get("priority", 0))
			var new_lbl: String = str(ed.get("label", ""))
			if not (old_ed.get("params", {}) as Dictionary).is_empty() and (new_lbl.is_empty() or new_lbl == str(old_ed.get("label", ""))):
				ed["params"] = (old_ed["params"] as Dictionary).duplicate(true)
