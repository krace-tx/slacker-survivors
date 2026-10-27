@tool
extends RefCounted

## FlowGraph 资源零耦合协议桥接器（Duck-Typed Graph Resource Bridge）。[br]
##
## [b]架构职责与约束：[/b][br]
## 1. [b]零业务耦合[/b]：严禁静态 `preload` 任何具体图资源类；统一通过标准协议方法 `to_flow_graph_ir` / `apply_flow_graph_ir`（向下兼容 `to_mermaid_ir` / `apply_mermaid_ir`）执行读写；[br]
## 2. [b]协议反射发现[/b]：统一收敛全局类协议嗅探与继承链 Schema 推断逻辑，供资源新建导出与 [`MermaidResourceCatalog`](mermaid_resource_catalog.gd) 共享；[br]
## 3. [b]轻量文件系统同步[/b]：保存已有资源时优先走单文件增量刷新 `EditorFileSystem.update_file`，避免每次 `Ctrl+S` 触发全工程重扫卡顿。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)

const _DEFAULT_GRAPH_TITLES: PackedStringArray = ["", "mermaid_graph", "fsm_graph", "bt_graph"]


#region 协议嗅探与类反射发现

## 判断对象是否为实现标准图 IR 读写协议的 `Resource` 实例。
static func is_supported_resource(obj: Object) -> bool:
	if obj == null or not (obj is Resource):
		return false
	var has_fg: bool = (
		obj.has_method(FlowGraphContracts.METHOD_TO_FG_IR)
		and obj.has_method(FlowGraphContracts.METHOD_APPLY_FG_IR)
	)
	if has_fg:
		return true
	return (
		obj.has_method(FlowGraphContracts.METHOD_TO_MG_IR)
		and obj.has_method(FlowGraphContracts.METHOD_APPLY_MG_IR)
	)


## 在不实例化资源的前提下，沿脚本继承链判断 `scr` 是否声明了完整图 IR 读写协议。
static func is_supported_script(scr: Script) -> bool:
	if scr == null:
		return false
	var has_fg: bool = (
		script_has_method(scr, FlowGraphContracts.METHOD_TO_FG_IR)
		and script_has_method(scr, FlowGraphContracts.METHOD_APPLY_FG_IR)
	)
	if has_fg:
		return true
	return (
		script_has_method(scr, FlowGraphContracts.METHOD_TO_MG_IR)
		and script_has_method(scr, FlowGraphContracts.METHOD_APPLY_MG_IR)
	)


static func script_has_method(scr: Script, method_name: StringName) -> bool:
	var cur: Script = scr
	while cur != null:
		for md: Dictionary in cur.get_script_method_list():
			if StringName(str(md.get("name", ""))) == method_name:
				return true
		cur = cur.get_base_script()
	return false


## 扫描全局类表并返回全部支持图协议的资源类描述字典：`{String (class_name): {"path": String, "base": String, "schema": StringName}}`。[br]
## 采用「源码协议预筛 + 继承链二阶段传播」，避免对工程内无关普通 `Resource` 脚本执行无意义的 `load()`。
static func collect_protocol_descriptors() -> Dictionary:
	var by_name: Dictionary = {}
	for entry_var: Variant in ProjectSettings.get_global_class_list():
		if entry_var is Dictionary:
			var info: Dictionary = entry_var as Dictionary
			var cls_name: String = str(info.get("class", ""))
			if not cls_name.is_empty():
				by_name[cls_name] = info

	var verified_scripts: Dictionary = {} ## {String (class_name): Script}
	for cname_v: Variant in by_name.keys():
		var cname: String = str(cname_v)
		if not _extends_resource(cname, by_name):
			continue
		var spath: String = str((by_name[cname] as Dictionary).get("path", ""))
		if spath.is_empty() or not FileAccess.file_exists(spath):
			continue
		if not _may_declare_protocol_directly(spath):
			continue
		var scr: Script = load(spath) as Script
		if is_supported_script(scr):
			verified_scripts[cname] = scr

	var out: Dictionary = {}
	for cname_v: Variant in by_name.keys():
		var cname: String = str(cname_v)
		if not _extends_resource(cname, by_name):
			continue
		var matched_root: String = _find_verified_ancestor(cname, by_name, verified_scripts)
		if matched_root.is_empty():
			continue
		var info: Dictionary = by_name[cname] as Dictionary
		var spath: String = str(info.get("path", ""))
		var base_cls: String = str(info.get("base", ""))
		var root_scr: Script = verified_scripts.get(matched_root, null) as Script
		var own_scr: Script = verified_scripts.get(cname, null) as Script
		var resolved_schema: StringName = infer_schema_for_class(
			cname,
			by_name,
			own_scr if own_scr != null else root_scr
		)
		out[cname] = {
			"path": spath,
			"base": base_cls,
			"schema": resolved_schema,
		}
	return out


## 依类名、继承链及脚本常量推断图种类（`fsm` / `bt` / `other`），确保自定义子类（如 `BossBrainDef extends BTGraphDef`）精准归类。
static func infer_schema_for_class(
	cname: String,
	by_name: Dictionary = {},
	scr: Script = null
) -> StringName:
	if scr != null:
		var cmap: Dictionary = scr.get_script_constant_map()
		for k: String in ["GRAPH_SCHEMA", "SCHEMA"]:
			if cmap.has(k):
				var sv: String = str(cmap[k]).to_lower()
				if sv == "fsm":
					return FlowGraphContracts.SCHEMA_FSM
				if sv == "bt":
					return FlowGraphContracts.SCHEMA_BT

	var cur: String = cname
	var guard: int = 0
	while not cur.is_empty() and guard < 32:
		var direct: StringName = infer_schema_by_name(cur)
		if direct != FlowGraphContracts.SCHEMA_OTHER:
			return direct
		if not by_name.has(cur):
			break
		cur = str((by_name[cur] as Dictionary).get("base", ""))
		guard += 1

	var s: Script = scr
	while s != null:
		var gname: String = String(s.get_global_name())
		if not gname.is_empty():
			var gs: StringName = infer_schema_by_name(gname)
			if gs != FlowGraphContracts.SCHEMA_OTHER:
				return gs
		if not s.resource_path.is_empty():
			var bs: StringName = infer_schema_by_name(s.resource_path.get_file().get_basename())
			if bs != FlowGraphContracts.SCHEMA_OTHER:
				return bs
		s = s.get_base_script()

	return FlowGraphContracts.SCHEMA_OTHER


static func infer_schema_by_name(name_token: String) -> StringName:
	var lower: String = name_token.to_lower()
	if lower.contains("fsm") or lower.contains("statemachine") or lower.contains("state_machine"):
		return FlowGraphContracts.SCHEMA_FSM
	if (
		lower.begins_with("bt")
		or lower.contains("_bt")
		or lower.contains("bt_")
		or lower.contains("behavior")
		or lower.contains("behaviour")
	):
		return FlowGraphContracts.SCHEMA_BT
	return FlowGraphContracts.SCHEMA_OTHER

#endregion


#region 资源加载与 IR 读写接口

static func load_resource_at_path(path: String, force_reload: bool = false) -> Dictionary:
	var clean_path: String = path.strip_edges()
	var exists_on_disk: bool = FileAccess.file_exists(clean_path) or ResourceLoader.exists(clean_path)
	if clean_path.is_empty() or not exists_on_disk:
		return {
			"ok": false,
			"resource": null,
			"error": FlowEditorI18n.t(&"bridge.err_not_found", [clean_path]),
		}
	var cache_mode: ResourceLoader.CacheMode = (
		ResourceLoader.CACHE_MODE_REPLACE if force_reload else ResourceLoader.CACHE_MODE_REUSE
	)
	var res: Resource = ResourceLoader.load(clean_path, "", cache_mode)
	if res == null:
		return {
			"ok": false,
			"resource": null,
			"error": FlowEditorI18n.t(&"bridge.err_load_failed", [clean_path]),
		}
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
	var raw: Variant = (
		res.call(FlowGraphContracts.METHOD_TO_FG_IR)
		if res.has_method(FlowGraphContracts.METHOD_TO_FG_IR)
		else res.call(FlowGraphContracts.METHOD_TO_MG_IR)
	)
	return raw as Dictionary if raw is Dictionary else {}


static func write_ir(res: Resource, graph: MermaidGraphModel) -> bool:
	if not is_supported_resource(res) or graph == null:
		return false
	var topo: Dictionary = graph.to_topology_dict()
	if res.has_method(FlowGraphContracts.METHOD_APPLY_FG_IR):
		res.call(FlowGraphContracts.METHOD_APPLY_FG_IR, topo)
	else:
		res.call(FlowGraphContracts.METHOD_APPLY_MG_IR, topo)
	return true

#endregion


#region 资源落盘保存与新建导出

static func save_resource(res: Resource, target_path: String = "") -> Dictionary:
	if not is_supported_resource(res):
		return {"ok": false, "path": "", "error": FlowEditorI18n.t(&"bridge.err_invalid_obj")}
	var raw_path: String = target_path.strip_edges()
	if raw_path.is_empty():
		raw_path = res.resource_path.strip_edges()
	var save_path: String = _normalize_save_path(raw_path)
	if save_path.is_empty():
		return {"ok": false, "path": "", "error": FlowEditorI18n.t(&"bridge.err_no_save_path")}

	var ensure_err: Error = _ensure_parent_directory(save_path)
	if ensure_err != OK:
		return {
			"ok": false,
			"path": save_path,
			"error": FlowEditorI18n.t(&"bridge.err_save_failed", [int(ensure_err), save_path]),
		}

	var existed_before: bool = FileAccess.file_exists(save_path)
	var err: Error = ResourceSaver.save(res, save_path)
	if err != OK:
		return {
			"ok": false,
			"path": save_path,
			"error": FlowEditorI18n.t(&"bridge.err_save_failed", [int(err), save_path]),
		}
	if res.resource_path != save_path:
		res.take_over_path(save_path)
	_notify_editor_filesystem(save_path, existed_before)
	return {"ok": true, "path": save_path, "error": ""}


static func export_new_resource(
	graph: MermaidGraphModel,
	target_path: String,
	preferred_class: String = ""
) -> Dictionary:
	if graph == null or graph.nodes.is_empty():
		return {
			"ok": false,
			"resource": null,
			"path": target_path,
			"error": FlowEditorI18n.t(&"bridge.err_empty_graph"),
		}

	var save_path: String = _normalize_save_path(target_path)
	if save_path.is_empty():
		return {
			"ok": false,
			"resource": null,
			"path": target_path,
			"error": FlowEditorI18n.t(&"bridge.err_no_save_path"),
		}

	var eff_schema: StringName = graph.resolve_effective_schema()
	var resolved: Dictionary = _resolve_export_script_info(eff_schema, preferred_class.strip_edges())
	var target_label: String = str(resolved.get("class_label", ""))
	var script_path: String = str(resolved.get("script_path", ""))
	if script_path.is_empty():
		return {
			"ok": false,
			"resource": null,
			"path": save_path,
			"error": FlowEditorI18n.t(&"bridge.err_class_missing", [target_label]),
		}

	var scr: GDScript = load(script_path) as GDScript
	if scr == null or not scr.can_instantiate():
		return {
			"ok": false,
			"resource": null,
			"path": save_path,
			"error": FlowEditorI18n.t(&"bridge.err_script_load", [script_path]),
		}

	var new_obj: Variant = scr.new()
	if not (new_obj is Resource) or not is_supported_resource(new_obj as Object):
		return {
			"ok": false,
			"resource": null,
			"path": save_path,
			"error": FlowEditorI18n.t(&"bridge.err_instantiate", [target_label]),
		}

	var res: Resource = new_obj as Resource
	var prev_title: String = graph.title
	var title_mutated: bool = false
	if _DEFAULT_GRAPH_TITLES.has(graph.title.strip_edges()):
		var stem: String = save_path.get_file().get_basename()
		if not stem.is_empty():
			graph.title = stem
			title_mutated = true

	write_ir(res, graph)
	var save_res: Dictionary = save_resource(res, save_path)
	if not bool(save_res.get("ok", false)):
		if title_mutated:
			graph.title = prev_title
		return {
			"ok": false,
			"resource": null,
			"path": save_path,
			"error": str(save_res.get("error", "")),
		}
	var final_path: String = str(save_res.get("path", save_path))
	return {"ok": true, "resource": res, "path": final_path, "error": ""}

#endregion


#region 内部辅助实现

static func _resolve_export_script_info(eff_schema: StringName, preferred_class: String) -> Dictionary:
	var target_schema: StringName = (
		FlowGraphContracts.SCHEMA_FSM
		if eff_schema == MermaidGraphModel.SCHEMA_FSM
		else FlowGraphContracts.SCHEMA_BT
	)
	var descriptors: Dictionary = collect_protocol_descriptors()

	if not preferred_class.is_empty():
		if descriptors.has(preferred_class):
			var p_desc: Dictionary = descriptors[preferred_class] as Dictionary
			return {
				"class_label": preferred_class,
				"script_path": str(p_desc.get("path", "")),
			}
		return {"class_label": preferred_class, "script_path": ""}

	# 优先选择直接继承自 Resource 的协议基类（如 FsmGraphDef / BTGraphDef 或自定义根协议类），避免误选特化业务子类
	var root_candidates: Array[String] = []
	var sub_candidates: Array[String] = []
	for cname_v: Variant in descriptors.keys():
		var cname: String = str(cname_v)
		var desc: Dictionary = descriptors[cname] as Dictionary
		if (desc.get("schema", FlowGraphContracts.SCHEMA_OTHER) as StringName) != target_schema:
			continue
		if str(desc.get("base", "")) == "Resource":
			root_candidates.append(cname)
		else:
			sub_candidates.append(cname)
	root_candidates.sort()
	sub_candidates.sort()

	var chosen: String = ""
	if not root_candidates.is_empty():
		chosen = root_candidates[0]
	elif not sub_candidates.is_empty():
		chosen = sub_candidates[0]
	if not chosen.is_empty():
		var c_desc: Dictionary = descriptors[chosen] as Dictionary
		return {"class_label": chosen, "script_path": str(c_desc.get("path", ""))}

	# 兜底：若工程首次打开尚未生成 global_script_class_cache，回退至内置运行时 AST 脚本路径
	var fallback_path: String = (
		FlowGraphContracts.SCRIPT_RUNTIME_FSM_DEF
		if target_schema == FlowGraphContracts.SCHEMA_FSM
		else FlowGraphContracts.SCRIPT_RUNTIME_BT_DEF
	)
	var fallback_label: String = (
		"FsmGraphDef" if target_schema == FlowGraphContracts.SCHEMA_FSM else "BTGraphDef"
	)
	if FileAccess.file_exists(fallback_path) or ResourceLoader.exists(fallback_path):
		return {"class_label": fallback_label, "script_path": fallback_path}
	return {"class_label": fallback_label, "script_path": ""}


static func _extends_resource(cname: String, by_name: Dictionary) -> bool:
	var cur: String = cname
	var guard: int = 0
	while by_name.has(cur) and guard < 32:
		cur = str((by_name[cur] as Dictionary).get("base", ""))
		guard += 1
	if cur.is_empty() or not ClassDB.class_exists(cur):
		return false
	return cur == "Resource" or ClassDB.is_parent_class(cur, "Resource")


static func _may_declare_protocol_directly(script_path: String) -> bool:
	if not script_path.ends_with(".gd"):
		return true
	var src: String = FileAccess.get_file_as_string(script_path)
	if src.is_empty():
		return false
	if src.contains(String(FlowGraphContracts.METHOD_TO_FG_IR)) or src.contains(String(FlowGraphContracts.METHOD_TO_MG_IR)):
		return true
	return src.contains("extends \"") or src.contains("extends '")


static func _find_verified_ancestor(cname: String, by_name: Dictionary, verified_scripts: Dictionary) -> String:
	var cur: String = cname
	var guard: int = 0
	while not cur.is_empty() and guard < 32:
		if verified_scripts.has(cur):
			return cur
		if not by_name.has(cur):
			break
		cur = str((by_name[cur] as Dictionary).get("base", ""))
		guard += 1
	return ""


static func _normalize_save_path(raw_path: String) -> String:
	var clean: String = raw_path.strip_edges()
	if clean.is_empty():
		return ""
	if clean.get_extension().is_empty():
		clean += ".tres"
	return clean


static func _ensure_parent_directory(save_path: String) -> Error:
	var base_dir: String = save_path.get_base_dir()
	if base_dir.is_empty() or base_dir == "res://" or base_dir == "user://":
		return OK
	var abs_dir: String = ProjectSettings.globalize_path(base_dir)
	if DirAccess.dir_exists_absolute(abs_dir):
		return OK
	return DirAccess.make_dir_recursive_absolute(abs_dir)


static func _notify_editor_filesystem(save_path: String, existed_before: bool) -> void:
	if not Engine.is_editor_hint() or not save_path.begins_with("res://"):
		return
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs == null:
		return
	if existed_before and not fs.get_file_type(save_path).is_empty():
		fs.update_file(save_path)
	elif not fs.is_scanning():
		fs.scan()

#endregion
