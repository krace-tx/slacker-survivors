@tool
extends ScrollContainer

## Mermaid 五卡片模块化交互检视面板门面（Modular 5-Card Inspector Facade）。[br]
##
## 协调编排 [`InspectorStyleKit`](../inspector/inspector_style_kit.gd) 与四类领域卡片（[`InspectorKpiCard`](../inspector/inspector_kpi_card.gd)、[`InspectorNodeEditorCard`](../inspector/inspector_node_editor_card.gd)、[`InspectorOutlineCard`](../inspector/inspector_outline_card.gd)、[`InspectorBlackboardCard`](../inspector/inspector_blackboard_card.gd)），对外维持单一清晰信号与 60ms 原位刷新接口。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const MermaidLayout = preload(FlowGraphContracts.SCRIPT_LAYOUT)
const InspectorStyleKit = preload(FlowGraphContracts.SCRIPT_INSPECTOR_STYLE_KIT)
const InspectorKpiCard = preload(FlowGraphContracts.SCRIPT_INSPECTOR_KPI_CARD)
const InspectorNodeEditorCard = preload(FlowGraphContracts.SCRIPT_INSPECTOR_NODE_CARD)
const InspectorOutlineCard = preload(FlowGraphContracts.SCRIPT_INSPECTOR_OUTLINE_CARD)
const InspectorBlackboardCard = preload(FlowGraphContracts.SCRIPT_INSPECTOR_BB_CARD)


#region 信号定义（兼容全部既有信号 + P0/P2/P3 编辑与调试信号）

signal node_selected_from_inspector(node_id: String, center_view: bool)
signal jump_code_requested(file_path: String, line_num: int)
signal force_node_requested(node_id: String, params: Dictionary)
signal switch_to_resource_requested(resource_path: String)
signal switch_to_live_requested(memory_id: int)
signal resolve_external_conflict_requested(resource_path: String, accept_disk: bool)

signal node_edit_committed(node_id: String, patch: Dictionary)
signal node_rename_committed(old_id: String, new_id: String)
signal edge_edit_committed(from_id: String, to_id: String, patch: Dictionary)
signal edge_delete_committed(from_id: String, to_id: String)
signal schema_edited(new_schema: Array[Dictionary])
signal breakpoint_toggle_requested(node_id: String)
signal live_var_edit_requested(var_key: String, raw_value: Variant, type_hint: String)
signal live_fire_event_requested(event_name: String)
signal sub_graph_open_requested(sub_graph_path: String)

#endregion


#region 子卡片组件与滚动容器引用

var _kit: InspectorStyleKit = InspectorStyleKit.new()
var _kpi_card: InspectorKpiCard = InspectorKpiCard.new()
var _node_card: InspectorNodeEditorCard = InspectorNodeEditorCard.new()
var _outline_card: InspectorOutlineCard = InspectorOutlineCard.new()
var _bb_card: InspectorBlackboardCard = InspectorBlackboardCard.new()

var _root_margin: MarginContainer = null
var _cards_vbox: VBoxContainer = null
var _catalog_paths: PackedStringArray = PackedStringArray()
var _last_store_ref: MermaidSessionStore = null
var _last_session_sig: String = ""
var _last_inspected_node_id: String = ""
var _last_selected_edge_key: String = ""
var _cards_wired: bool = false

#endregion


#region 生命周期与卡片信号转发装配

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ensure_containers()
	if _kit.sb_card == null:
		setup_metrics(1.0, 14)


func _ensure_containers() -> void:
	if not _cards_wired:
		_cards_wired = true
		_wire_card_signals()
	if _root_margin != null and is_instance_valid(_root_margin):
		return
	_root_margin = MarginContainer.new()
	_root_margin.name = "RootMargin"
	_root_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_root_margin)

	_cards_vbox = VBoxContainer.new()
	_cards_vbox.name = "CardsVBox"
	_cards_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_margin.add_child(_cards_vbox)


func _wire_card_signals() -> void:
	_kpi_card.resolve_external_conflict_requested.connect(func(p: String, acc: bool) -> void: resolve_external_conflict_requested.emit(p, acc))
	_kpi_card.switch_to_resource_requested.connect(func(p: String) -> void: switch_to_resource_requested.emit(p))
	_kpi_card.switch_to_live_requested.connect(func(mid: int) -> void: switch_to_live_requested.emit(mid))
	_kpi_card.diagnostic_node_clicked.connect(func(nid: String) -> void: node_selected_from_inspector.emit(nid, true))

	_node_card.node_selected_from_inspector.connect(func(nid: String, c: bool) -> void: node_selected_from_inspector.emit(nid, c))
	_node_card.jump_code_requested.connect(func(f: String, l: int) -> void: jump_code_requested.emit(f, l))
	_node_card.force_node_requested.connect(func(nid: String, p: Dictionary) -> void: force_node_requested.emit(nid, p))
	_node_card.node_edit_committed.connect(func(nid: String, patch: Dictionary) -> void: node_edit_committed.emit(nid, patch))
	_node_card.node_rename_committed.connect(func(o: String, n: String) -> void: node_rename_committed.emit(o, n))
	_node_card.edge_edit_committed.connect(func(f: String, t: String, patch: Dictionary) -> void: edge_edit_committed.emit(f, t, patch))
	_node_card.edge_delete_committed.connect(func(f: String, t: String) -> void: edge_delete_committed.emit(f, t))
	_node_card.breakpoint_toggle_requested.connect(func(nid: String) -> void: breakpoint_toggle_requested.emit(nid))
	_node_card.live_fire_event_requested.connect(func(ev: String) -> void: live_fire_event_requested.emit(ev))
	_node_card.sub_graph_open_requested.connect(func(sp: String) -> void: sub_graph_open_requested.emit(sp))
	_node_card.ui_rebuild_requested.connect(_on_local_ui_rebuild_requested)

	_outline_card.node_selected_from_inspector.connect(func(nid: String, c: bool) -> void: node_selected_from_inspector.emit(nid, c))
	_outline_card.schema_edited.connect(func(sc: Array[Dictionary]) -> void: schema_edited.emit(sc))
	_outline_card.ui_rebuild_requested.connect(_on_local_ui_rebuild_requested)

	_bb_card.live_var_edit_requested.connect(func(k: String, v: Variant, th: String) -> void: live_var_edit_requested.emit(k, v, th))


func _on_local_ui_rebuild_requested() -> void:
	if _last_store_ref != null:
		rebuild_inspector(_last_store_ref, _last_inspected_node_id, _last_selected_edge_key)

#endregion


#region 公开度量、构建与实时遥测 API

func set_catalog_paths(paths: PackedStringArray) -> void:
	_catalog_paths = paths.duplicate()


func get_last_lint_issues() -> Array[Dictionary]:
	return _kpi_card.last_lint_issues.duplicate(true)


func setup_metrics(ui_scale: float, base_font_size: int) -> void:
	_ensure_containers()
	_kit.setup(ui_scale, base_font_size)
	add_theme_stylebox_override("panel", _kit.sb_panel_bg)
	var pad: int = roundi(10.0 * _kit.s)
	_root_margin.add_theme_constant_override("margin_left", pad)
	_root_margin.add_theme_constant_override("margin_right", pad)
	_root_margin.add_theme_constant_override("margin_top", pad)
	_root_margin.add_theme_constant_override("margin_bottom", pad)
	_cards_vbox.add_theme_constant_override("separation", pad)


func rebuild_inspector(store: MermaidSessionStore, selected_node_id: String = "", selected_edge_key: String = "") -> void:
	_ensure_containers()
	if _kit.sb_card == null:
		setup_metrics(1.0, 14)

	_last_store_ref = store
	var next_sig: String = "%s::%s" % [String(store.active_mode), store.active_key] if store != null else ""
	var same_session: bool = (next_sig == _last_session_sig)
	if not same_session:
		_node_card.reset_session_state()
	var same_node: bool = same_session and (selected_node_id == _last_inspected_node_id)
	var saved_scroll: int = scroll_vertical if same_session else 0
	var restore_edit_idx: int = -1
	if same_node and get_viewport() != null:
		var f_owner: Control = get_viewport().gui_get_focus_owner()
		if f_owner is LineEdit and _cards_vbox.is_ancestor_of(f_owner):
			var old_edits: Array[Node] = _cards_vbox.find_children("*", "LineEdit", true, false)
			restore_edit_idx = old_edits.find(f_owner)
	_last_session_sig = next_sig
	_last_inspected_node_id = selected_node_id
	_last_selected_edge_key = selected_edge_key

	_kpi_card.clear_refs()
	_node_card.clear_refs()
	_outline_card.clear_refs()
	_bb_card.clear_refs()
	for child: Node in _cards_vbox.get_children():
		_cards_vbox.remove_child(child)
		child.free()

	if store == null:
		return

	var g: MermaidGraphModel = store.get_active_graph()
	var plan: Dictionary = store.get_active_plan()
	if plan.is_empty() and g != null and not g.nodes.is_empty():
		plan = MermaidLayout.analyze_topology(g)
	var interrupt_set: Dictionary = plan.get("interrupt_set", {}) as Dictionary
	var frame: Dictionary = store.get_active_display_frame()

	_cards_vbox.add_child(_kpi_card.build(_kit, store, g, frame))
	_cards_vbox.add_child(_node_card.build(_kit, store, g, interrupt_set, selected_node_id, selected_edge_key, frame, _catalog_paths))

	if g != null and not g.nodes.is_empty():
		_cards_vbox.add_child(_outline_card.build_outline_card(_kit, store, g, interrupt_set, selected_node_id, frame))

	if store.is_editable_mode() and g != null:
		_cards_vbox.add_child(_outline_card.build_schema_card(_kit, g))

	if store.is_live_selected() or store.is_snapshot_selected():
		_cards_vbox.add_child(_bb_card.build(_kit, store, frame))

	if same_session and saved_scroll > 0:
		set_deferred("scroll_vertical", saved_scroll)
	else:
		scroll_vertical = 0

	if restore_edit_idx >= 0:
		var next_edits: Array[Node] = _cards_vbox.find_children("*", "LineEdit", true, false)
		if restore_edit_idx < next_edits.size():
			var next_le: LineEdit = next_edits[restore_edit_idx] as LineEdit
			next_le.grab_focus()
			next_le.select_all()


func refresh_live_telemetry(store: MermaidSessionStore, frame: Dictionary) -> void:
	if store == null or (not store.is_live_selected() and not store.is_snapshot_selected()):
		return
	var g: MermaidGraphModel = store.get_active_graph()
	var active_nodes: Dictionary = frame.get("active_nodes", {}) as Dictionary if frame.get("active_nodes", {}) is Dictionary else {}
	_kpi_card.refresh_live(_kit, store, g, frame)
	_node_card.refresh_live(_kit, active_nodes)
	_outline_card.refresh_live(active_nodes)
	_bb_card.refresh_live(store, frame)


func update_live_telemetry(store: MermaidSessionStore, frame: Dictionary) -> void:
	refresh_live_telemetry(store, frame)

#endregion
