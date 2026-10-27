class_name GraphDebugBinding
extends RefCounted

## 单个运行期图算法实例的弱引用调试绑定器（Graph Debug Instance Binding）。[br]
##
## [b]核心职责：[/b][br]
## 1. 基于 `Object.get_instance_id()` 维护目标算法与宿主实体的弱引用句柄，并在 [method dispose] 时彻底断开信号与回调，杜绝 `RefCounted` 循环引用泄漏；[br]
## 2. 委托 [GraphDebugSerializer] 导出拓扑与帧快照，委托 [GraphDebugCommandExecutor] 执行下行调试指令与热重载；[br]
## 3. 内置零分配 $O(B)$ 行为树断点快筛（[method probe_breakpoints_fast]）与单步预算门禁，命中时自动暂停并通知 [GraphDebugBridge] 同步 `_paused_count`。


#region 常量与公开状态字段

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

#endregion


#region 私有回调与断点追踪状态

var _export_cb: Callable = Callable()
var _capture_cb: Callable = Callable()
var _command_cb: Callable = Callable()
var _export_method: StringName = &""
var _capture_method: StringName = &""
var _command_method: StringName = &""
var _custom_flow_signal: Signal = Signal()

var _on_edge_cb: Callable = Callable()
var _on_topology_cb: Callable = Callable()

var _discovered_edges: Dictionary = {}
var _bt_bp_key_by_id: Dictionary = {}    ## {int (node_id): String (breakpoint key)}
var _active_bp_bt_ids: Dictionary = {}   ## {int (node_id): bool}
var _prev_generic_active: Dictionary = {} ## {String (node_id): bool}
var _last_bt_tick_count: int = -1
var _breakpoint_hit_pending: bool = false
var _is_disposed: bool = false

#endregion


#region 初始化、基类自省与零泄漏销毁

func setup_standard(
	target: Object,
	owner: Object,
	title: String,
	edge_notify_cb: Callable,
	topo_notify_cb: Callable
) -> void:
	_setup_common_metadata(target, owner, title, edge_notify_cb, topo_notify_cb)

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
	_is_disposed = false
	memory_id = ctx.get_instance_id()
	secondary_id = tree.get_instance_id()
	owner_id = owner.get_instance_id() if is_instance_valid(owner) else 0
	recognized_kind = KIND_BT
	inheritance_chain = extract_inheritance_chain(tree)
	primary_class_name = inheritance_chain[0] if not inheritance_chain.is_empty() else "BTTree"
	display_title = title if not title.is_empty() else "%s (#%d)" % [primary_class_name, memory_id]
	_on_edge_cb = edge_notify_cb
	_on_topology_cb = topo_notify_cb


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
	_setup_common_metadata(target, owner, title, edge_notify_cb, topo_notify_cb)
	recognized_kind = KIND_CUSTOM
	_bind_weak_or_callable(export_cb, &"export")
	_bind_weak_or_callable(capture_cb, &"capture")
	_bind_weak_or_callable(command_cb, &"command")
	if not flow_signal.is_null():
		var sig_obj_id: int = flow_signal.get_object_id()
		if sig_obj_id != 0 and is_instance_id_valid(sig_obj_id) and not flow_signal.is_connected(_on_custom_flow_signal):
			_custom_flow_signal = flow_signal
			_custom_flow_signal.connect(_on_custom_flow_signal)


func _setup_common_metadata(
	target: Object,
	owner: Object,
	title: String,
	edge_notify_cb: Callable,
	topo_notify_cb: Callable
) -> void:
	_is_disposed = false
	memory_id = target.get_instance_id()
	owner_id = owner.get_instance_id() if is_instance_valid(owner) else 0
	inheritance_chain = extract_inheritance_chain(target)
	primary_class_name = inheritance_chain[0] if not inheritance_chain.is_empty() else target.get_class()
	display_title = title if not title.is_empty() else "%s (#%d)" % [primary_class_name, memory_id]
	_on_edge_cb = edge_notify_cb
	_on_topology_cb = topo_notify_cb


func _bind_weak_or_callable(cb: Callable, slot: StringName) -> void:
	if not cb.is_valid():
		return
	# 若回调直接指向被测实例自身的标准方法，仅保存方法名并通过 memory_id 弱调用，斩断 RefCounted 强引用环
	if cb.is_standard() and cb.get_object_id() == memory_id:
		match slot:
			&"export": _export_method = cb.get_method()
			&"capture": _capture_method = cb.get_method()
			&"command": _command_method = cb.get_method()
		return
	match slot:
		&"export": _export_cb = cb
		&"capture": _capture_cb = cb
		&"command": _command_cb = cb


## 彻底断开所有目标信号与闭包引用（由 [GraphDebugBridge] 在注销或替换绑定时调用）。
func dispose() -> void:
	if _is_disposed:
		return
	_is_disposed = true

	if memory_id != 0 and is_instance_id_valid(memory_id):
		var target_obj: Object = instance_from_id(memory_id)
		if target_obj is StateMachine:
			var fsm: StateMachine = target_obj as StateMachine
			if fsm.state_changed.is_connected(_on_fsm_state_changed):
				fsm.state_changed.disconnect(_on_fsm_state_changed)
		elif target_obj is BaseDebuggableGraph:
			var dbg: BaseDebuggableGraph = target_obj as BaseDebuggableGraph
			if dbg.edge_traversed.is_connected(_on_debuggable_edge):
				dbg.edge_traversed.disconnect(_on_debuggable_edge)
			if dbg.topology_changed.is_connected(_on_debuggable_topology_changed):
				dbg.topology_changed.disconnect(_on_debuggable_topology_changed)

	if not _custom_flow_signal.is_null():
		var sig_obj_id: int = _custom_flow_signal.get_object_id()
		if sig_obj_id != 0 and is_instance_id_valid(sig_obj_id) and _custom_flow_signal.is_connected(_on_custom_flow_signal):
			_custom_flow_signal.disconnect(_on_custom_flow_signal)
		_custom_flow_signal = Signal()

	_export_cb = Callable()
	_capture_cb = Callable()
	_command_cb = Callable()
	_on_edge_cb = Callable()
	_on_topology_cb = Callable()
	_discovered_edges.clear()
	_bt_bp_key_by_id.clear()
	_active_bp_bt_ids.clear()
	_prev_generic_active.clear()


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
	if _is_disposed or memory_id == 0 or not is_instance_id_valid(memory_id):
		return false
	if recognized_kind == KIND_BT and (secondary_id == 0 or not is_instance_id_valid(secondary_id)):
		return false
	return true

#endregion


#region 暂停门禁、断点引擎、命令委托与热重载

func set_paused_state(next_paused: bool) -> void:
	if is_paused == next_paused:
		if not next_paused:
			last_hit_breakpoint = ""
			_breakpoint_hit_pending = false
		return
	var was_paused: bool = is_paused
	is_paused = next_paused
	if not is_paused:
		last_hit_breakpoint = ""
		_breakpoint_hit_pending = false
	GraphDebugBridge.notify_binding_paused_changed(was_paused, is_paused)


## 请求单步放行 1 个 Tick（同时清除上一帧残留的断点命中徽章，防止单步到非断点节点时误报）。
func request_step_once() -> void:
	set_paused_state(true)
	last_hit_breakpoint = ""
	_breakpoint_hit_pending = false
	step_budget += 1


func set_breakpoint(node_id: String, enabled: bool) -> void:
	var clean_id: String = node_id.strip_edges()
	if clean_id.is_empty():
		return
	var bt_nid: int = GraphDebugCommandExecutor.parse_bt_node_id(clean_id)
	var canonical_bt_key: String = ("n%d" % bt_nid) if bt_nid > 0 else clean_id

	if enabled:
		breakpoint_nodes[clean_id] = true
		if bt_nid > 0:
			_bt_bp_key_by_id[bt_nid] = clean_id
			_active_bp_bt_ids.erase(bt_nid)
		_prev_generic_active.erase(clean_id)
		_prev_generic_active.erase(canonical_bt_key)
	else:
		breakpoint_nodes.erase(clean_id)
		breakpoint_nodes.erase(canonical_bt_key)
		if bt_nid > 0:
			breakpoint_nodes.erase(str(bt_nid))
			_bt_bp_key_by_id.erase(bt_nid)
			_active_bp_bt_ids.erase(bt_nid)
		if last_hit_breakpoint == clean_id or last_hit_breakpoint == canonical_bt_key:
			last_hit_breakpoint = ""
			_breakpoint_hit_pending = false


func clear_breakpoints() -> void:
	breakpoint_nodes.clear()
	_bt_bp_key_by_id.clear()
	_active_bp_bt_ids.clear()
	_prev_generic_active.clear()
	last_hit_breakpoint = ""
	_breakpoint_hit_pending = false


func clear_discovered_edges() -> void:
	_discovered_edges.clear()


## 热重载成功后重置缓存的运行时发现边与旧节点激活掩码。
func reset_after_hot_reload() -> void:
	_discovered_edges.clear()
	_active_bp_bt_ids.clear()
	_prev_generic_active.clear()
	_last_bt_tick_count = -1
	topology_dirty = true


## 供 [GraphDebugBridge] 在 60ms IPC 节流窗口内零分配快速探测本帧是否新命中了断点。
func probe_breakpoints_fast() -> bool:
	if _breakpoint_hit_pending:
		return true
	if breakpoint_nodes.is_empty() or not is_alive():
		return false
	match recognized_kind:
		KIND_FSM:
			# FSM 断点已在 _on_fsm_state_changed 中同步拦截并置位 _breakpoint_hit_pending
			return _breakpoint_hit_pending
		KIND_BT:
			var ctx: BTContext = instance_from_id(memory_id) as BTContext
			if ctx != null:
				evaluate_bt_breakpoints_for_context(ctx)
			return _breakpoint_hit_pending
		_:
			# BaseDebuggableGraph / CustomBound 仅在配置了断点时采样 active_nodes
			var snap: Dictionary = _capture_raw_custom_or_debuggable()
			var active_map: Dictionary = snap.get("active_nodes", {}) as Dictionary if snap.get("active_nodes", null) is Dictionary else {}
			evaluate_generic_breakpoints(active_map)
			return _breakpoint_hit_pending


## 消费一次断点刚命中待推送标记（确保命中当帧强制穿透 60ms 节流推送至编辑器，随后恢复正常节流）。
func consume_breakpoint_hit_pending() -> bool:
	if not _breakpoint_hit_pending:
		return false
	_breakpoint_hit_pending = false
	return true


## 针对 [BTContext] 执行 $O(B)$ 零字符串分配断点边沿检测（新进入 `RUNNING` 或 `SUCCESS` 时触发挂起）。
func evaluate_bt_breakpoints_for_context(ctx: BTContext) -> void:
	if ctx == null or ctx.tick_count == _last_bt_tick_count:
		return
	_last_bt_tick_count = ctx.tick_count
	if _bt_bp_key_by_id.is_empty():
		return
	for nid_var: Variant in _bt_bp_key_by_id.keys():
		var nid: int = int(nid_var)
		var st: int = ctx.get_live_node_status(nid)
		var is_now_active: bool = (st == BTStatus.Status.RUNNING or st == BTStatus.Status.SUCCESS)
		var was_active: bool = _active_bp_bt_ids.has(nid)
		if is_now_active:
			_active_bp_bt_ids[nid] = true
			if not was_active:
				_trigger_breakpoint(str(_bt_bp_key_by_id[nid]))
		elif was_active:
			_active_bp_bt_ids.erase(nid)


## 兼容入口：由 [GraphDebugSerializer] 在导出 BT 帧时调用。
func evaluate_active_node_breakpoints(_tick_count: int, _active_nodes: Dictionary) -> void:
	if recognized_kind == KIND_BT and is_alive():
		evaluate_bt_breakpoints_for_context(instance_from_id(memory_id) as BTContext)


## 针对 `BaseDebuggableGraph` 与 `CustomBound` 图实例执行通用激活节点边沿断点检测。
func evaluate_generic_breakpoints(active_nodes: Dictionary) -> void:
	if breakpoint_nodes.is_empty():
		return
	var next_active: Dictionary = {}
	for nid_var: Variant in active_nodes.keys():
		var nid_str: String = str(nid_var)
		var n_val: Variant = active_nodes[nid_var]
		var n_state: String = str((n_val as Dictionary).get("state", "RUNNING")) if n_val is Dictionary else str(n_val)
		if n_state == "RUNNING" or n_state == "SUCCESS":
			next_active[nid_str] = true
			if not _prev_generic_active.has(nid_str) and bool(breakpoint_nodes.get(nid_str, false)):
				_trigger_breakpoint(nid_str)
	_prev_generic_active = next_active


func _trigger_breakpoint(hit_id: String) -> void:
	last_hit_breakpoint = hit_id
	_breakpoint_hit_pending = true
	if not is_paused:
		is_paused = true
		step_budget = 0
		GraphDebugBridge.notify_binding_paused_from_breakpoint()


func execute_command(command: StringName, payload: Dictionary) -> bool:
	return GraphDebugCommandExecutor.execute(self, command, payload)


func hot_reload_ir(ir: Dictionary) -> bool:
	return GraphDebugCommandExecutor.hot_reload(self, ir)


func invoke_custom_command(command: StringName, payload: Dictionary) -> bool:
	if not _command_method.is_empty() and is_alive():
		var target_obj: Object = instance_from_id(memory_id)
		if target_obj != null and target_obj.has_method(_command_method):
			return bool(target_obj.call(_command_method, command, payload))
	return bool(_command_cb.call(command, payload)) if _command_cb.is_valid() else false


func consume_suspend_gate() -> bool:
	if not is_paused:
		return false
	if step_budget > 0:
		step_budget -= 1
		last_hit_breakpoint = ""
		return false
	return true

#endregion


#region 元数据、子图引用解析、拓扑导出与帧遥测采集

func get_descriptor_dict() -> Dictionary:
	var owner_name: String = ""
	if owner_id != 0 and is_instance_id_valid(owner_id):
		var owner_obj: Object = instance_from_id(owner_id)
		if owner_obj is Node:
			owner_name = String((owner_obj as Node).name)
		elif owner_obj != null:
			owner_name = owner_obj.get_class()
	return {
		"memory_id": memory_id,
		"secondary_id": secondary_id,
		"owner_id": owner_id,
		"owner_name": owner_name,
		"title": display_title,
		"kind": String(recognized_kind),
		"primary_class": primary_class_name,
		"inheritance_chain": Array(inheritance_chain),
		"source_resource_path": resolve_source_resource_path(),
	}


func resolve_source_resource_path() -> String:
	var ast_res: Resource = _resolve_ast_resource()
	if ast_res == null:
		return ""
	var rpath: String = ast_res.resource_path
	if (rpath.begins_with("res://") or rpath.begins_with("user://")) and not rpath.contains("::"):
		return rpath
	return ""


## 检查当前实例是否嵌套引用了指定路径的子图资源（用于保存公共子图时自动触发父图重编译）。
func references_sub_resource_path(target_path: String) -> bool:
	if target_path.is_empty() or not is_alive():
		return false
	return GraphDebugSerializer.ast_references_sub_graph(_resolve_ast_resource(), target_path)


func _resolve_ast_resource() -> Resource:
	if not is_alive():
		return null
	for oid: int in [secondary_id, memory_id]:
		if oid == 0 or not is_instance_id_valid(oid):
			continue
		var obj: Object = instance_from_id(oid)
		if obj != null and obj.has_method(&"get_ast"):
			var ast_v: Variant = obj.call(&"get_ast")
			if ast_v is Resource:
				return ast_v as Resource
	return null


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
			return ast.to_flow_graph_ir() if (ast != null and ast.root != null) else {}
		KIND_DEBUGGABLE:
			return (instance_from_id(memory_id) as BaseDebuggableGraph)._export_graph_dict()
		_:
			if not _export_method.is_empty():
				var target_obj: Object = instance_from_id(memory_id)
				if target_obj != null and target_obj.has_method(_export_method):
					var m_res: Variant = target_obj.call(_export_method)
					return m_res as Dictionary if m_res is Dictionary else {}
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
				instance_from_id(secondary_id) as BTTree,
				instance_from_id(memory_id) as BTContext,
				self
			)
		_:
			frame = _capture_raw_custom_or_debuggable()
			var active_map: Dictionary = frame.get("active_nodes", {}) as Dictionary if frame.get("active_nodes", null) is Dictionary else {}
			evaluate_generic_breakpoints(active_map)

	frame["memory_id"] = memory_id
	frame["paused"] = is_paused
	frame["breakpoints"] = breakpoint_nodes.keys()
	frame["hit_breakpoint"] = last_hit_breakpoint
	return frame


func _capture_raw_custom_or_debuggable() -> Dictionary:
	if recognized_kind == KIND_DEBUGGABLE:
		var dbg: BaseDebuggableGraph = instance_from_id(memory_id) as BaseDebuggableGraph
		return dbg._capture_frame_dict().duplicate(true) if dbg != null else {"active_nodes": {}, "active_edges": [], "vars": {}}
	if not _capture_method.is_empty():
		var target_obj: Object = instance_from_id(memory_id)
		if target_obj != null and target_obj.has_method(_capture_method):
			var m_raw: Variant = target_obj.call(_capture_method)
			if m_raw is Dictionary:
				return (m_raw as Dictionary).duplicate(true)
	var raw: Variant = _capture_cb.call() if _capture_cb.is_valid() else null
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {"active_nodes": {}, "active_edges": [], "vars": {}}

#endregion


#region 信号响应钩子

func _on_fsm_state_changed(new_state: StringName, prev_state: StringName, _msg: Dictionary) -> void:
	if _is_disposed:
		return
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
				if _on_topology_cb.is_valid():
					_on_topology_cb.call(memory_id)
	if _on_edge_cb.is_valid():
		_on_edge_cb.call(memory_id, from_s, to_s, "")


func _on_debuggable_edge(from_node_id: StringName, to_node_id: StringName, edge_label: String) -> void:
	if not _is_disposed and _on_edge_cb.is_valid():
		_on_edge_cb.call(memory_id, String(from_node_id), String(to_node_id), edge_label)


func _on_debuggable_topology_changed() -> void:
	if _is_disposed:
		return
	topology_dirty = true
	if _on_topology_cb.is_valid():
		_on_topology_cb.call(memory_id)


func _on_custom_flow_signal(arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
	if not _is_disposed and _on_edge_cb.is_valid() and arg1 != null and arg2 != null:
		var lbl: String = str(arg3) if arg3 != null else ""
		_on_edge_cb.call(memory_id, str(arg1), str(arg2), lbl)

#endregion
