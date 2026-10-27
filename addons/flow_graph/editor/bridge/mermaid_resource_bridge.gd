@tool
extends RefCounted

## Mermaid Godot 资源零耦合鸭子类型桥接器（Duck-Typed Resource Bridge）。[br]
##
## [b]架构约束：[/b][br]
## 严禁 `preload` 或硬编码任何业务/框架类（如 `FsmGraphDef` / `BTGraphDef`）；[br]
## 仅通过标准协议方法 `has_method("to_mermaid_ir")` 与 `has_method("apply_mermaid_ir")` 进行读写，并通过 `ProjectSettings.get_global_class_list()` 动态反射创建新 `.tres` 资产。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)


#region 协议嗅探与读写接口

static func is_supported_resource(obj: Object) -> bool:
	if obj == null or not (obj is Resource):
		return false
	var has_fg: bool = obj.has_method("to_flow_graph_ir") and obj.has_method("apply_flow_graph_ir")
	var has_mg: bool = obj.has_method("to_mermaid_ir") and obj.has_method("apply_mermaid_ir")
	return has_fg or has_mg


static func load_resource_at_path(path: String, force_reload: bool = false) -> Dictionary:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty() or not ResourceLoader.exists(clean_path):
		return {"ok": false, "resource": null, "error": FlowEditorI18n.t(&"bridge.err_not_found", [clean_path])}
	var cache_mode: ResourceLoader.CacheMode = (
		ResourceLoader.CACHE_MODE_REPLACE if force_reload else ResourceLoader.CACHE_MODE_REUSE
	)
	var res: Resource = ResourceLoader.load(clean_path, "", cache_mode)
	if res == null:
		return {"ok": false, "resource": null, "error": FlowEditorI18n.t(&"bridge.err_load_failed", [clean_path])}
	if not is_supported_resource(res):
		return {
			"ok": false,
			"resource": null,
			"error": FlowEditorI18n.t(&"bridge.err_unsupported", [clean_path.get_file()]),
		}
	return {"ok": true, "resource": res, "error": ""}


static func read_ir(res: Resource) -> Dictionary:
	if not is_supported_resource(res):
		return {}
	var raw: Variant = res.call("to_flow_graph_ir") if res.has_method("to_flow_graph_ir") else res.call("to_mermaid_ir")
	if raw is Dictionary:
		return raw as Dictionary
	return {}


static func write_ir(res: Resource, graph: MermaidGraphModel) -> bool:
	if not is_supported_resource(res) or graph == null:
		return false
	var topo: Dictionary = graph.to_topology_dict()
	if res.has_method("apply_flow_graph_ir"):
		res.call("apply_flow_graph_ir", topo)
	else:
		res.call("apply_mermaid_ir", topo)
	return true

#endregion


#region 资源落盘保存与新建导出

static func save_resource(res: Resource, target_path: String = "") -> Dictionary:
	if not is_supported_resource(res):
		return {"ok": false, "path": "", "error": FlowEditorI18n.t(&"bridge.err_invalid_obj")}
	var save_path: String = target_path.strip_edges()
	if save_path.is_empty():
		save_path = res.resource_path
	if save_path.is_empty():
		return {"ok": false, "path": "", "error": FlowEditorI18n.t(&"bridge.err_no_save_path")}

	var err: Error = ResourceSaver.save(res, save_path)
	if err != OK:
		return {
			"ok": false,
			"path": save_path,
			"error": FlowEditorI18n.t(&"bridge.err_save_failed", [int(err), save_path]),
		}
	if res.resource_path != save_path:
		res.take_over_path(save_path)
	_notify_editor_filesystem()
	return {"ok": true, "path": save_path, "error": ""}


static func export_new_resource(graph: MermaidGraphModel, target_path: String) -> Dictionary:
	if graph == null or graph.nodes.is_empty():
		return {"ok": false, "resource": null, "path": target_path, "error": FlowEditorI18n.t(&"bridge.err_empty_graph")}

	var eff_schema: StringName = graph.resolve_effective_schema()
	var target_class: String = "FsmGraphDef" if eff_schema == MermaidGraphModel.SCHEMA_FSM else "BTGraphDef"
	var script_path: String = _find_global_class_script_path(target_class)
	if script_path.is_empty():
		return {
			"ok": false,
			"resource": null,
			"path": target_path,
			"error": FlowEditorI18n.t(&"bridge.err_class_missing", [target_class]),
		}

	var scr: GDScript = load(script_path) as GDScript
	if scr == null:
		return {
			"ok": false,
			"resource": null,
			"path": target_path,
			"error": FlowEditorI18n.t(&"bridge.err_script_load", [script_path]),
		}

	var new_obj: Variant = scr.new()
	if not (new_obj is Resource):
		return {
			"ok": false,
			"resource": null,
			"path": target_path,
			"error": FlowEditorI18n.t(&"bridge.err_instantiate", [target_class]),
		}
	var res: Resource = new_obj as Resource
	if graph.title.is_empty() or graph.title == "mermaid_graph":
		var stem: String = target_path.get_file().get_basename()
		if not stem.is_empty():
			graph.title = stem

	write_ir(res, graph)
	var save_res: Dictionary = save_resource(res, target_path)
	if not bool(save_res.get("ok", false)):
		return {
			"ok": false,
			"resource": null,
			"path": target_path,
			"error": str(save_res.get("error", "")),
		}
	return {"ok": true, "resource": res, "path": target_path, "error": ""}


static func _find_global_class_script_path(target_class: String) -> String:
	var list: Array = ProjectSettings.get_global_class_list()
	for entry_var: Variant in list:
		if entry_var is Dictionary:
			var entry: Dictionary = entry_var as Dictionary
			if str(entry.get("class", "")) == target_class:
				return str(entry.get("path", ""))
	return ""


static func _notify_editor_filesystem() -> void:
	if Engine.is_editor_hint():
		var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.scan()

#endregion
