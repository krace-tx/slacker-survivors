class_name GraphDebugBinding
extends RefCounted

## 单个运行期图算法实例的弱引用调试绑定器（Graph Debug Instance Binding）。[br]
##
## [b]核心职责：[/b][br]
## 1. 基于 `Object.get_instance_id()` 维护目标算法与宿主实体的弱引用句柄，杜绝循环引用泄漏；[br]
## 2. 委托 [GraphDebugSerializer] 导出拓扑与帧快照，委托 [GraphDebugCommandExecutor] 执行下行调试指令与热重载；[br]
## 3. 维护节点断点表 `breakpoint_nodes` 与单步预算门禁，命中时自动暂停并通知 [GraphDebugBridge] 同步 `_paused_count`。

#region 常量与字段
const KIND_FSM: StringName = &"StateMachine"
const KIND_BT: StringName = &"BTTree"
const KIND_DEBUGGABLE: StringName = &"BaseDebuggableGraph"
const KIND_CUSTOM: StringName = &"CustomBound"

var memory_id: int = 0
var secondary_id: int = 0
var owner_id: int = 0
var display_title: String = ""
var recognized_kind: StringName = KIND_CUSTOM
var primary_class_name: String = "Object"
var inheritance_chain: PackedStringArray = PackedStringArray()

var is_paused: bool = false
var step_budget: int = 0
var topology_dirty: bool = false
var breakpoint_nodes: Dictionary = {} ## {String: bool}
var last_hit_breakpoint: String = ""

var _export_cb: Callable = Callable()
var _capture_cb: Callable = Callable()
var _command_cb: Callable = Callable()
var _on_edge_Callback: Callable = Callable()
var _on_topology_Callback: Callable = Callable()

var _discovered_edges: Dictionary = {}
var _prev_bt_active_nodes: Dictionary = {}
var _last_bt_tick_count: int = -1
#endregion


#region 初始化与基类自省
func setup_standard(
	target: Object,
	owner: Object,
	title: String,
	edge_notify_cb: Callable,
	topo_notify_cb: Callable
) -> void:
	memory_id = target.get_instance_id()
	owner_id = owner.get_instance_id() if is_instance_valid(owner) else 0
	inheritance_chain = extract_inheritance_chain(target)
	primary_class_name = inheritance_chain[0] if not inheritance_chain.is_empty() else target.get_class()
	display_title = title if not title.is_empty() else "%s (#%d)" % [primary_class_name, memory_id]
	_on_edge_Callback = edge_notify_cb
	_on_topology_Callback = topo_notify_cb

	if target is StateMachine:
		recognized_kind = KIND_FSM
		var fsm: StateMachine = target as StateMachine
		if not fsm.state_changed.is_connected(_on_fsm_state_changed):
			fsm.state_changed.connect(_on_fsm_state_changed)
	elif target is BaseDebuggableGraph:
		recognized_kind = KIND_DEBUGGABLE
		var dbg: BaseDebuggableGraph = target as BaseDebuggableGraph
		if not dbg.edge_traversed.is_connected(_on_debuggable_edge):
			dbg.edge_traversed.connect(_on_debuggable_edge)
		if not dbg.topology_changed.is_connected(_on_debuggable_topology_changed):
			dbg.topology_changed.connect(_on_debuggable_topology_changed)
	else:
		recognized_kind = KIND_CUSTOM


func setup_bt(
	tree: BTTree,
	ctx: BTContext,
	owner: Object,
	title: String,
	edge_notify_cb: Callable,
	topo_notify_cb: Callable
) -> void:
	memory_id = ctx.get_instance_id()
	secondary_id = tree.get_instance_id()
	owner_id = owner.get_instance_id() if is_instance_valid(owner) else 0
	recognized_kind = KIND_BT
	inheritance_chain = extract_inheritance_chain(tree)
	primary_class_name = inheritance_chain[0] if not inheritance_chain.is_empty() else "BTTree"
	display_title = title if not title.is_empty() else "%s (#%d)" % [primary_class_name, memory_id]
	_on_edge_Callback = edge_notify_cb
	_on_topology_Callback = topo_notify_cb


func setup_custom(
	target: Object,
	owner: Object,
	title: String,
	export_cb: Callable,
	capture_cb: Callable,
	command_cb: Callable,
	flow_signal: Signal,
	edge_notify_cb: Callable,
	topo_notify_cb: Callable
) -> void:
	setup_standard(target, owner, title, edge_notify_cb, topo_notify_cb)
	recognized_kind = KIND_CUSTOM
	_export_cb = export_cb
	_capture_cb = capture_cb
	_command_cb = command_cb
	if not flow_signal.is_null():
		flow_signal.connect(_on_custom_flow_signal)


static func extract_inheritance_chain(target: Object) -> PackedStringArray:
	var chain := PackedStringArray()
	if not is_instance_valid(target):
		return chain
	var scr: Script = target.get_script() as Script
	while scr != null:
		var gname: StringName = scr.get_global_name()
		if not gname.is_empty():
			chain.append(String(gname))
		elif not scr.resource_path.is_empty():
			chain.append(scr.resource_path.get_file().get_basename())
		scr = scr.get_base_script()
	chain.append(target.get_class())
	return chain


func is_alive() -> bool:
	if memory_id == 0 or not is_instance_id_valid(memory_id):
		return false
	if recognized_kind == KIND_BT and (secondary_id == 0 or not is_instance_id_valid(secondary_id)):
		return false
	return true
#endregion


#region 暂停门禁、断点管理、命令委托与热重载
func set_paused_state(next_paused: bool) -> void:
	if is_paused == next_paused:
		return
	var was_paused: bool = is_paused
	is_paused = next_paused
	if not is_paused:
		last_hit_breakpoint = ""
	GraphDebugBridge.notify_binding_paused_changed(was_paused, is_paused)


func set_breakpoint(node_id: String, enabled: bool) -> void:
	if enabled:
		breakpoint_nodes[node_id] = true
		_prev_bt_active_nodes.erase(node_id)
		_prev_bt_active_nodes.erase("n" + node_id)
	else:
		breakpoint_nodes.erase(node_id)
		if last_hit_breakpoint == node_id:
			last_hit_breakpoint = ""


func clear_breakpoints() -> void:
	breakpoint_nodes.clear()
	last_hit_breakpoint = ""


func clear_discovered_edges() -> void:
	_discovered_edges.clear()


func evaluate_bt_breakpoints(tick_count: int, active_nodes: Dictionary) -> void:
	if tick_count == _last_bt_tick_count:
		return
	_last_bt_tick_count = tick_count
	var next_active: Dictionary = {}
	for nid_var: Variant in active_nodes.keys():
		var nid_str: String = str(nid_var)
		var n_info: Dictionary = active_nodes[nid_str] as Dictionary
		var n_state: String = str(n_info.get("state", ""))
		if n_state == "RUNNING" or n_state == "SUCCESS":
			next_active[nid_str] = true
			if not _prev_bt_active_nodes.has(nid_str):
				var raw_num: String = nid_str.trim_prefix("n")
				if bool(breakpoint_nodes.get(nid_str, false)):
					_trigger_breakpoint(nid_str)
				elif bool(breakpoint_nodes.get(raw_num, false)):
					_trigger_breakpoint(raw_num)
	_prev_bt_active_nodes = next_active


func _trigger_breakpoint(hit_id: String) -> void:
	last_hit_breakpoint = hit_id
	if not is_paused:
		is_paused = true
		step_budget = 0
		GraphDebugBridge.notify_binding_paused_from_breakpoint()


func execute_command(command: StringName, payload: Dictionary) -> bool:
	return GraphDebugCommandExecutor.execute(self, command, payload)


func hot_reload_ir(ir: Dictionary) -> bool:
	return GraphDebugCommandExecutor.hot_reload(self, ir)


func invoke_custom_command(command: StringName, payload: Dictionary) -> bool:
	return bool(_command_cb.call(command, payload)) if _command_cb.is_valid() else false


func consume_suspend_gate() -> bool:
	if not is_paused:
		return false
	if step_budget > 0:
		step_budget -= 1
		return false
	return true
#endregion


#region 元数据、拓扑导出与帧遥测采集
func get_descriptor_dict() -> Dictionary:
	var owner_name: String = ""
	if owner_id != 0 and is_instance_id_valid(owner_id):
		var owner_obj: Object = instance_from_id(owner_id)
		if owner_obj is Node:
			owner_name = String((owner_obj as Node).name)
		elif owner_obj != null:
			owner_name = owner_obj.get_class()
	return {
		"memory_id": memory_id, "secondary_id": secondary_id, "owner_id": owner_id,
		"owner_name": owner_name, "title": display_title, "kind": String(recognized_kind),
		"primary_class": primary_class_name, "inheritance_chain": Array(inheritance_chain),
		"source_resource_path": resolve_source_resource_path(),
	}


func resolve_source_resource_path() -> String:
	if not is_alive():
		return ""
	for oid: int in [secondary_id, memory_id]:
		if oid == 0 or not is_instance_id_valid(oid):
			continue
		var obj: Object = instance_from_id(oid)
		if obj == null or not obj.has_method(&"get_ast"):
			continue
		var ast_v: Variant = obj.call(&"get_ast")
		if ast_v is Resource:
			var rpath: String = (ast_v as Resource).resource_path
			if (rpath.begins_with("res://") or rpath.begins_with("user://")) and not rpath.contains("::"):
				return rpath
	return ""


func export_topology_dict() -> Dictionary:
	topology_dirty = false
	if not is_alive():
		return {}
	match recognized_kind:
		KIND_FSM:
			return GraphDebugSerializer.export_fsm_topology(instance_from_id(memory_id) as StateMachine, _discovered_edges)
		KIND_BT:
			var tree: BTTree = instance_from_id(secondary_id) as BTTree
			var ast: BTGraphDef = tree.get_ast() if tree != null else null
			return ast.to_mermaid_ir() if (ast != null and ast.root != null) else {}
		KIND_DEBUGGABLE:
			return (instance_from_id(memory_id) as BaseDebuggableGraph)._export_graph_dict()
		_:
			var res: Variant = _export_cb.call() if _export_cb.is_valid() else null
			return res as Dictionary if res is Dictionary else {}


func capture_frame_dict() -> Dictionary:
	if not is_alive():
		return {}
	var frame: Dictionary = {}
	match recognized_kind:
		KIND_FSM:
			frame = GraphDebugSerializer.capture_fsm_frame(instance_from_id(memory_id) as StateMachine)
		KIND_BT:
			frame = GraphDebugSerializer.capture_bt_frame(
				instance_from_id(secondary_id) as BTTree, instance_from_id(memory_id) as BTContext, self
			)
		KIND_DEBUGGABLE:
			frame = (instance_from_id(memory_id) as BaseDebuggableGraph)._capture_frame_dict().duplicate(true)
		_:
			var raw: Variant = _capture_cb.call() if _capture_cb.is_valid() else null
			frame = (raw as Dictionary).duplicate(true) if raw is Dictionary else {"active_nodes": {}, "active_edges": [], "vars": {}}

	frame["memory_id"] = memory_id
	frame["paused"] = is_paused
	frame["breakpoints"] = breakpoint_nodes.keys()
	frame["hit_breakpoint"] = last_hit_breakpoint
	return frame
#endregion


#region 信号响应钩子
func _on_fsm_state_changed(new_state: StringName, prev_state: StringName, _msg: Dictionary) -> void:
	var to_s: String = String(new_state)
	var hit_bp: bool = false
	if not to_s.is_empty() and bool(breakpoint_nodes.get(to_s, false)):
		_trigger_breakpoint(to_s)
		hit_bp = true
	if prev_state.is_empty() or new_state.is_empty():
		if hit_bp:
			GraphDebugBridge.push_frame(memory_id, true)
		return
	var from_s: String = String(prev_state)
	var pair_key: String = "%s->%s" % [from_s, to_s]
	if is_alive():
		var fsm: StateMachine = instance_from_id(memory_id) as StateMachine
		if fsm != null and fsm.get_ast() != null:
			var declared: bool = false
			for tr: FsmTransitionDef in fsm.get_ast().transitions:
				if tr != null and String(tr.from_state) == from_s and String(tr.to_state) == to_s:
					declared = true
					break
			if not declared and not _discovered_edges.has(pair_key):
				_discovered_edges[pair_key] = ""
				topology_dirty = true
				if _on_topology_Callback.is_valid():
					_on_topology_Callback.call(memory_id)
	if _on_edge_Callback.is_valid():
		_on_edge_Callback.call(memory_id, from_s, to_s, "")


func _on_debuggable_edge(from_node_id: StringName, to_node_id: StringName, edge_label: String) -> void:
	if _on_edge_Callback.is_valid():
		_on_edge_Callback.call(memory_id, String(from_node_id), String(to_node_id), edge_label)


func _on_debuggable_topology_changed() -> void:
	topology_dirty = true
	if _on_topology_Callback.is_valid():
		_on_topology_Callback.call(memory_id)


func _on_custom_flow_signal(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
	if _on_edge_Callback.is_valid() and arg1 != null and arg2 != null:
		var lbl: String = str(arg3) if arg3 != null else ""
		_on_edge_Callback.call(memory_id, str(arg1), str(arg2), lbl)
#endregion
