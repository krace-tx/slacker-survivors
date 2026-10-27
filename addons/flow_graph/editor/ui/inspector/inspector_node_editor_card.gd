@tool
extends RefCounted

## 检视器卡片 2：焦点节点结构化属性编辑器、算子补全与断点控制台（Inspector Node Editor Card）。[br]
##
## 采用渐进式分区设计：「头部定位工具条」+「节点属性区（FSM 三态角色胶囊 / BT 三模式条件切换 / 带单位数值框）」+「流出边转换手风琴区」。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const FlowOperatorScanner = preload(FlowGraphContracts.SCRIPT_OPERATOR_SCANNER)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const InspectorStyleKit = preload(FlowGraphContracts.SCRIPT_INSPECTOR_STYLE_KIT)
const InspectorEdgeEditorSubcard = preload(FlowGraphContracts.SCRIPT_INSPECTOR_EDGE_SUBCARD)

const BT_ALL_KINDS: PackedStringArray = [
	"Selector", "UtilitySelector", "WeightedSelector", "Sequence", "Parallel",
	"Inverter", "Cooldown", "Repeater", "TimeLimit", "ForceSuccess", "ForceFailure", "Service",
	"Condition", "Action", "Wait", "SubTree",
]
const CMP_OPS: PackedStringArray = ["==", "!=", "<", "<=", ">", ">="]

signal node_selected_from_inspector(node_id: String, center_view: bool)
signal jump_code_requested(file_path: String, line_num: int)
signal force_node_requested(node_id: String, params: Dictionary)
signal node_edit_committed(node_id: String, patch: Dictionary)
signal node_rename_committed(old_id: String, new_id: String)
signal edge_edit_committed(from_id: String, to_id: String, patch: Dictionary)
signal edge_delete_committed(from_id: String, to_id: String)
signal breakpoint_toggle_requested(node_id: String)
signal live_fire_event_requested(event_name: String)
signal sub_graph_open_requested(sub_graph_path: String)
signal ui_rebuild_requested()

var _inspected_node_id: String = ""
var _chip_panel: PanelContainer = null
var _chip_lbl: Label = null
var _ui_state: Dictionary = {
	"cond_modes": {},
	"expanded_edges": {},
	"edge_modes": {},
}


#region 公开构建与实时徽章刷新

func clear_refs() -> void:
	_inspected_node_id = ""
	_chip_panel = null
	_chip_lbl = null


func reset_session_state() -> void:
	_ui_state = {
		"cond_modes": {},
		"expanded_edges": {},
		"edge_modes": {},
	}


func build(
	kit: InspectorStyleKit,
	store: MermaidSessionStore,
	g: MermaidGraphModel,
	interrupt_set: Dictionary,
	selected_node_id: String,
	selected_edge_key: String,
	frame: Dictionary,
	catalog_paths: PackedStringArray
) -> PanelContainer:
	clear_refs()
	if g == null or g.nodes.is_empty():
		return _build_empty_quickstart_card(kit)

	var eff_node_id: String = selected_node_id
	if eff_node_id.is_empty() and not selected_edge_key.is_empty() and selected_edge_key.contains("->"):
		var ep_parts: PackedStringArray = selected_edge_key.split("->", false, 1)
		if ep_parts.size() == 2:
			eff_node_id = ep_parts[1] if ep_parts[0] == "*" else ep_parts[0]

	var nd: Dictionary = g.find_node(eff_node_id) if not eff_node_id.is_empty() else {}
	if nd.is_empty():
		return _build_unselected_hint_card(kit, store, g)

	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var nid: String = str(nd.get("id", ""))
	var ntitle: String = str(nd.get("title", nid))
	var nkind: String = str(nd.get("kind", "State"))
	var is_initial: bool = (nid == g.initial_node_id)
	var is_interrupt: bool = interrupt_set.has(nid)
	var params: Dictionary = nd.get("params", {}) as Dictionary
	var sub_path: String = str(params.get("sub_graph_path", nd.get("sub_graph_path", ""))).strip_edges()
	_inspected_node_id = nid

	var card: PanelContainer = kit.make_card(true)
	var vbox: VBoxContainer = kit.make_vbox(8.0)
	card.add_child(vbox)

	var hdr: HBoxContainer = kit.make_hbox(7.0)
	vbox.add_child(hdr)
	var accent_col: Color = CanvasThemePalette.resolve_accent_color(nkind, is_initial, is_interrupt, CanvasThemePalette.is_fsm_terminal(g, nid))
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(maxf(3.0, roundf(3.5 * kit.s)), roundf(24.0 * kit.s))
	bar.color = accent_col
	hdr.add_child(bar)

	var kind_ico: Texture2D = CanvasThemePalette.resolve_kind_icon(nkind, is_initial, is_interrupt, CanvasThemePalette.is_fsm_terminal(g, nid))
	if kind_ico != null:
		var k_rect: TextureRect = InspectorStyleKit.make_scaled_icon(kind_ico, roundi(17.0 * kit.s))
		k_rect.modulate = accent_col
		hdr.add_child(k_rect)

	var title_box: VBoxContainer = kit.make_vbox(1.0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_box)
	var n_lbl: Label = kit.make_label(ntitle, kit.fs_title, t.font_strong)
	n_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(n_lbl)
	var is_fsm_state: bool = (g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM and nkind == "State")
	var kind_disp: String = _resolve_fsm_variant_label(is_initial, is_interrupt, params) if is_fsm_state else FlowEditorI18n.kind_label(nkind)
	var id_lbl: Label = kit.make_label("%s  ·  %s" % [nid, kind_disp], kit.fs_sub, t.font_dim)
	id_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(id_lbl)

	var st_chip := PanelContainer.new()
	st_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st_lbl: Label = kit.make_label("", kit.fs_sub, Color.WHITE)
	st_chip.add_child(st_lbl)
	hdr.add_child(st_chip)
	_chip_panel = st_chip
	_chip_lbl = st_lbl

	if store.is_live_selected() or store.is_snapshot_selected():
		var active_nodes: Dictionary = frame.get("active_nodes", {}) as Dictionary if frame.get("active_nodes", {}) is Dictionary else {}
		refresh_live(kit, active_nodes)
	else:
		var badge_txt: String = FlowEditorI18n.t(&"insp.chip_initial") if is_initial else (FlowEditorI18n.t(&"insp.chip_interrupt") if is_interrupt else FlowEditorI18n.kind_label(nkind))
		kit.apply_status_pill_theme(st_chip, st_lbl, badge_txt, accent_col)

	var src: Dictionary = nd.get("source", {}) as Dictionary
	var src_file: String = str(src.get("file", ""))
	var src_line: int = maxi(1, int(src.get("line", 1)))
	var act_row := HFlowContainer.new()
	act_row.add_theme_constant_override("h_separation", roundi(5.0 * kit.s))
	act_row.add_theme_constant_override("v_separation", roundi(4.0 * kit.s))
	vbox.add_child(act_row)

	var focus_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.btn_center"), InspectorStyleKit.IconFitView, false)
	focus_btn.pressed.connect(func() -> void: node_selected_from_inspector.emit(nid, true))
	act_row.add_child(focus_btn)

	if not src_file.is_empty():
		var code_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.btn_jump_code"), InspectorStyleKit.IconCodeDsl, false)
		code_btn.pressed.connect(func() -> void: jump_code_requested.emit(src_file, src_line))
		act_row.add_child(code_btn)

	if not sub_path.is_empty():
		var sub_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.btn_open_sub"), InspectorStyleKit.IconResourceList, false)
		sub_btn.add_theme_color_override("icon_normal_color", t.accent)
		sub_btn.pressed.connect(func() -> void: sub_graph_open_requested.emit(sub_path))
		act_row.add_child(sub_btn)

	var has_bp: bool = store.has_breakpoint(nid)
	var bp_ico: Texture2D = InspectorStyleKit.IconStatusLive if has_bp else InspectorStyleKit.IconStatusOffline
	var bp_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.btn_bp_clear") if has_bp else FlowEditorI18n.t(&"insp.btn_bp_set"), bp_ico, false)
	bp_btn.add_theme_color_override("font_color", t.error if has_bp else t.font)
	bp_btn.add_theme_color_override("icon_normal_color", t.error if has_bp else t.font_dim)
	bp_btn.pressed.connect(func() -> void: breakpoint_toggle_requested.emit(nid))
	act_row.add_child(bp_btn)

	if store.is_live_selected():
		var force_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.btn_force"), InspectorStyleKit.IconBoltTrigger, true)
		var p_dup: Dictionary = params.duplicate(true)
		force_btn.pressed.connect(func() -> void: force_node_requested.emit(nid, p_dup))
		act_row.add_child(force_btn)
		if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM:
			InspectorEdgeEditorSubcard.append_live_fire_event_bar(kit, vbox, func(ev: String) -> void: live_fire_event_requested.emit(ev))

	var on_sel_fn: Callable = func(target_id: String, center: bool) -> void: node_selected_from_inspector.emit(target_id, center)
	var on_rebuild_fn: Callable = func() -> void: ui_rebuild_requested.emit()
	if store.is_editable_mode():
		_append_editable_node_form(kit, vbox, g, nid, ntitle, nkind, is_initial, is_interrupt, accent_col, params, catalog_paths, on_rebuild_fn)
		InspectorEdgeEditorSubcard.append_editable_edges(
			kit, vbox, g, nid, nkind, is_interrupt, selected_edge_key, _ui_state, on_rebuild_fn, on_sel_fn,
			func(f: String, to: String, p: Dictionary) -> void: edge_edit_committed.emit(f, to, p),
			func(f: String, to: String) -> void: edge_delete_committed.emit(f, to)
		)
	else:
		InspectorEdgeEditorSubcard.append_readonly_details(kit, vbox, g, nid, nkind, is_initial, params, src_file, src_line, on_sel_fn)

	return card


func refresh_live(kit: InspectorStyleKit, active_nodes: Dictionary) -> void:
	if _chip_panel == null or _chip_lbl == null or _inspected_node_id.is_empty():
		return
	if active_nodes.has(_inspected_node_id):
		var st_rec: Dictionary = active_nodes[_inspected_node_id] as Dictionary
		var st_name: String = str(st_rec.get("state", "RUNNING"))
		var st_disp: String = FlowEditorI18n.state_label(st_name)
		var bd_s: String = str(st_rec.get("badge", ""))
		kit.apply_status_pill_theme(_chip_panel, _chip_lbl, ("%s · %s" % [st_disp, bd_s]) if not bd_s.is_empty() else st_disp, InspectorStyleKit.resolve_state_color(st_name))
	else:
		kit.apply_status_pill_theme(_chip_panel, _chip_lbl, FlowEditorI18n.state_label("IDLE"), MermaidThemeService.tokens().font_faint)

#endregion


#region 结构化节点属性表单（消除角色四重冗余与空框堆叠）

func _append_editable_node_form(
	kit: InspectorStyleKit,
	parent_vbox: VBoxContainer,
	g: MermaidGraphModel,
	nid: String,
	ntitle: String,
	nkind: String,
	is_initial: bool,
	is_interrupt: bool,
	accent_col: Color,
	params: Dictionary,
	catalog_paths: PackedStringArray,
	on_request_rebuild: Callable
) -> void:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	parent_vbox.add_child(kit.make_section_header(FlowEditorI18n.t(&"insp.sec_props"), "", accent_col))

	var form_panel := PanelContainer.new()
	form_panel.add_theme_stylebox_override("panel", kit.sb_recessed)
	var fv: VBoxContainer = kit.make_vbox(6.0)
	form_panel.add_child(fv)
	parent_vbox.add_child(form_panel)

	var eff_schema: StringName = g.resolve_effective_schema()
	var ops: Dictionary = FlowOperatorScanner.get_cached()
	var sub_path: String = str(params.get("sub_graph_path", "")).strip_edges()
	var has_subgraph: bool = bool(params.get("submachine", false)) or not sub_path.is_empty()

	fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_node_id"), kit.make_line_edit(nid, FlowEditorI18n.t(&"insp.ph_node_id"), func(next_id: String) -> void:
		if not next_id.is_empty() and next_id != nid:
			node_rename_committed.emit(nid, next_id)
	)))
	fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_title"), kit.make_line_edit(ntitle, FlowEditorI18n.t(&"insp.ph_title"), func(next_t: String) -> void:
		node_edit_committed.emit(nid, {"title": next_t if not next_t.is_empty() else nid})
	)))

	if eff_schema == MermaidGraphModel.SCHEMA_FSM:
		# 用紧凑正交胶囊行统一收敛「默认入口 / 全局打断 / 嵌套子图」，彻底告别下拉框与底部双复选框的四重重复
		var role_row: HBoxContainer = kit.make_hbox(4.0)
		role_row.add_child(kit.make_toggle_chip(
			FlowEditorI18n.t(&"insp.role_initial"), is_initial, t.cat_entry,
			FlowEditorI18n.t(&"insp.role_initial_tip"),
			func() -> void: node_edit_committed.emit(nid, {"set_initial": not is_initial})
		))
		role_row.add_child(kit.make_toggle_chip(
			FlowEditorI18n.t(&"insp.role_interrupt"), is_interrupt, t.cat_interrupt,
			FlowEditorI18n.t(&"insp.role_interrupt_tip"),
			func() -> void: node_edit_committed.emit(nid, {"set_interrupt": not is_interrupt})
		))
		role_row.add_child(kit.make_toggle_chip(
			FlowEditorI18n.t(&"insp.role_subgraph"), has_subgraph, t.accent,
			FlowEditorI18n.t(&"insp.role_subgraph_tip"),
			func() -> void:
				if has_subgraph:
					node_edit_committed.emit(nid, {"params_patch": {"submachine": null, "sub_graph_path": null}})
				else:
					node_edit_committed.emit(nid, {"params_patch": {"submachine": true}})
		))
		fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_fsm_roles"), role_row))
	else:
		var kind_opts: PackedStringArray = (
			PackedStringArray([MermaidGraphModel.BT_ROOT_KIND])
			if nkind == MermaidGraphModel.BT_ROOT_KIND
			else BT_ALL_KINDS.duplicate()
		)
		if not kind_opts.has(nkind):
			kind_opts.append(nkind)
		var kind_labels := PackedStringArray()
		for ko: String in kind_opts:
			kind_labels.append(FlowEditorI18n.kind_label(ko))
		var on_kind_sel: Callable = func(chosen_k: String, _i: int) -> void:
			node_edit_committed.emit(nid, {"kind": chosen_k, "shape": MermaidGraphModel.default_shape_for_kind(chosen_k)})
		var kind_btn: OptionButton = kit.make_option_button(kind_opts, maxi(0, kind_opts.find(nkind)), on_kind_sel, kind_labels)
		if nkind == MermaidGraphModel.BT_ROOT_KIND:
			kind_btn.disabled = true
		fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_kind"), kind_btn))

	var show_subgraph_slot: bool = (nkind == "SubTree") or (eff_schema == MermaidGraphModel.SCHEMA_FSM and nkind == "State" and has_subgraph)
	if show_subgraph_slot:
		var open_sub_inline: Button = null
		if not sub_path.is_empty():
			open_sub_inline = kit.make_mini_button("", FlowEditorI18n.t(&"insp.btn_open_sub"), t.accent, InspectorStyleKit.IconOpenExternal)
			open_sub_inline.pressed.connect(func() -> void: sub_graph_open_requested.emit(sub_path))
		var on_sub_commit: Callable = func(v: String) -> void:
			_emit_param_patch(nid, "sub_graph_path", v if not v.is_empty() else null)
		var sub_ctrl: HBoxContainer = kit.make_picker_input(sub_path, FlowEditorI18n.t(&"insp.ph_subgraph"), catalog_paths, on_sub_commit, false, open_sub_inline)
		fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_subgraph"), sub_ctrl))

	var bb_keys: PackedStringArray = PackedStringArray()
	for bb_item: Dictionary in g.blackboard_schema:
		var bk: String = str(bb_item.get("key", "")).strip_edges()
		if not bk.is_empty():
			bb_keys.append(bk)

	match nkind:
		"State":
			var st_cands: PackedStringArray = (ops.get("states", PackedStringArray()) as PackedStringArray).duplicate()
			for ac: String in (ops.get("actions", PackedStringArray()) as PackedStringArray):
				if not st_cands.has(ac):
					st_cands.append(ac)
			fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_action"), kit.make_picker_input(str(params.get("action_key", nid)), FlowEditorI18n.t(&"insp.ph_action"), st_cands, func(v: String) -> void:
				_emit_param_patch(nid, "action_key", v if not v.is_empty() else null)
			)))
		"Action":
			fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_action"), kit.make_picker_input(str(params.get("action_key", "")), FlowEditorI18n.t(&"insp.ph_action"), ops.get("actions", PackedStringArray()) as PackedStringArray, func(v: String) -> void:
				_emit_param_patch(nid, "action_key", v)
			)))
		"Condition":
			_append_bt_condition_fields(kit, fv, nid, params, ops, bb_keys, on_request_rebuild)
		"Service":
			fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_service"), kit.make_picker_input(str(params.get("service_key", params.get("action_key", ""))), FlowEditorI18n.t(&"insp.ph_service"), ops.get("actions", PackedStringArray()) as PackedStringArray, func(v: String) -> void:
				_emit_param_patch(nid, "service_key", v)
			)))
			_add_float_row(kit, fv, nid, FlowEditorI18n.t(&"insp.lbl_interval"), "interval_sec", float(params.get("interval_sec", 0.25)))
			_add_float_row(kit, fv, nid, FlowEditorI18n.t(&"insp.lbl_jitter"), "jitter_sec", float(params.get("jitter_sec", 0.05)))
		"Cooldown":
			_add_float_row(kit, fv, nid, FlowEditorI18n.t(&"insp.lbl_cooldown"), "cooldown_sec", float(params.get("cooldown_sec", 1.0)))
			_add_float_row(kit, fv, nid, FlowEditorI18n.t(&"insp.lbl_jitter"), "jitter_sec", float(params.get("jitter_sec", 0.0)))
		"Wait":
			_add_float_row(kit, fv, nid, FlowEditorI18n.t(&"insp.lbl_duration"), "duration_sec", float(params.get("duration_sec", 0.5)))
			_add_float_row(kit, fv, nid, FlowEditorI18n.t(&"insp.lbl_jitter"), "jitter_sec", float(params.get("jitter_sec", 0.0)))
		"Repeater":
			fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_repeat"), kit.make_unit_line_edit(
				str(int(params.get("repeat_count", 3))), FlowEditorI18n.t(&"insp.ph_repeat"), FlowEditorI18n.t(&"insp.unit_times"),
				func(v: String) -> void: _emit_param_patch(nid, "repeat_count", int(InspectorStyleKit.parse_typed_literal(v, "int")))
			)))
			fv.add_child(kit.make_check_box(FlowEditorI18n.t(&"insp.chk_abort_fail"), bool(params.get("abort_on_failure", true)), func(on: bool) -> void: _emit_param_patch(nid, "abort_on_failure", on)))
		"TimeLimit":
			_add_float_row(kit, fv, nid, FlowEditorI18n.t(&"insp.lbl_timeout"), "timeout_sec", float(params.get("timeout_sec", 3.0)))
		"Selector":
			fv.add_child(kit.make_check_box(FlowEditorI18n.t(&"insp.chk_memory"), bool(params.get("memory", false)), func(on: bool) -> void: _emit_param_patch(nid, "memory", on)))
		"UtilitySelector":
			var u_row: HBoxContainer = kit.make_hbox(8.0)
			u_row.add_child(kit.make_inline_labeled_edit(
				FlowEditorI18n.t(&"insp.lbl_momentum"),
				"%.2f" % float(params.get("momentum", 0.10)),
				FlowEditorI18n.t(&"insp.ph_momentum"),
				"",
				func(v: String) -> void:
					_emit_param_patch(nid, "momentum", maxf(0.0, float(InspectorStyleKit.parse_typed_literal(v, "float"))))
			))
			u_row.add_child(kit.make_inline_labeled_edit(
				FlowEditorI18n.t(&"insp.lbl_min_score"),
				"%.2f" % float(params.get("min_score", 0.01)),
				FlowEditorI18n.t(&"insp.ph_min_score"),
				"",
				func(v: String) -> void:
					_emit_param_patch(nid, "min_score", maxf(0.0, float(InspectorStyleKit.parse_typed_literal(v, "float"))))
			))
			fv.add_child(u_row)
			fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_top_k"), kit.make_line_edit(
				str(maxi(1, int(params.get("top_k", 1)))),
				FlowEditorI18n.t(&"insp.ph_top_k"),
				func(v: String) -> void:
					_emit_param_patch(nid, "top_k", maxi(1, int(InspectorStyleKit.parse_typed_literal(v, "int"))))
			)))
			fv.add_child(kit.make_check_box(FlowEditorI18n.t(&"insp.chk_memory"), bool(params.get("memory", false)), func(on: bool) -> void: _emit_param_patch(nid, "memory", on)))
		"Sequence":
			fv.add_child(kit.make_check_box(FlowEditorI18n.t(&"insp.chk_reactive"), bool(params.get("reactive", false)), func(on: bool) -> void: _emit_param_patch(nid, "reactive", on)))
		"Parallel":
			fv.add_child(kit.make_check_box(FlowEditorI18n.t(&"insp.chk_req_all"), bool(params.get("require_all_success", true)), func(on: bool) -> void: _emit_param_patch(nid, "require_all_success", on)))


func _append_bt_condition_fields(
	kit: InspectorStyleKit,
	fv: VBoxContainer,
	nid: String,
	params: Dictionary,
	ops: Dictionary,
	bb_keys: PackedStringArray,
	on_request_rebuild: Callable
) -> void:
	var ck_s: String = str(params.get("condition_key", "")).strip_edges()
	var bb_s: String = str(params.get("bb_key", "")).strip_edges()
	var ex_s: String = str(params.get("expr", "")).strip_edges()
	var auto_m: int = 2 if not ex_s.is_empty() else (1 if not bb_s.is_empty() else 0)
	var cm_map: Dictionary = _ui_state.get("cond_modes", {}) as Dictionary
	var cur_m: int = int(cm_map.get(nid, auto_m))

	var mode_labels := PackedStringArray([
		FlowEditorI18n.t(&"insp.cond_mode_key"),
		FlowEditorI18n.t(&"insp.cond_mode_bb"),
		FlowEditorI18n.t(&"insp.cond_mode_expr"),
	])
	var dots: Array[bool] = [not ck_s.is_empty(), not bb_s.is_empty(), not ex_s.is_empty()]
	var on_cond_tab: Callable = func(next_m: int) -> void:
		var next_map: Dictionary = _ui_state.get("cond_modes", {}) as Dictionary
		next_map[nid] = next_m
		_ui_state["cond_modes"] = next_map
		if on_request_rebuild.is_valid():
			on_request_rebuild.call()
	fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_cond_mode"), kit.make_segmented_tabs(mode_labels, cur_m, on_cond_tab, dots)))

	if cur_m == 0:
		var on_ck_commit: Callable = func(v: String) -> void:
			node_edit_committed.emit(nid, {"params_patch": {"condition_key": v if not v.is_empty() else null, "bb_key": null, "expr": null}})
		var ck_ctrl: HBoxContainer = kit.make_picker_input(ck_s, FlowEditorI18n.t(&"insp.ph_condition"), ops.get("conditions", PackedStringArray()) as PackedStringArray, on_ck_commit, true)
		fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_condition"), ck_ctrl))
	elif cur_m == 1:
		fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_bb_key"), kit.make_picker_input(bb_s, FlowEditorI18n.t(&"insp.ph_bb_key"), bb_keys, func(v: String) -> void:
			node_edit_committed.emit(nid, {"params_patch": {"bb_key": v if not v.is_empty() else null, "condition_key": null, "expr": null}})
		)))
		var cmp_row: HBoxContainer = kit.make_hbox(4.0)
		cmp_row.add_child(kit.make_option_button(CMP_OPS, maxi(0, CMP_OPS.find(str(params.get("op", "==")))), func(op_s: String, _i: int) -> void: _emit_param_patch(nid, "op", op_s)))
		var cur_val_s: String = "" if params.get("value", null) == null else str(params.get("value", ""))
		cmp_row.add_child(kit.make_line_edit(cur_val_s, FlowEditorI18n.t(&"insp.ph_cmp_val"), func(vs: String) -> void:
			_emit_param_patch(nid, "value", null if vs.is_empty() else InspectorStyleKit.parse_typed_literal(vs))
		))
		fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_cmp"), cmp_row))
	else:
		fv.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.lbl_expr"), kit.make_line_edit(ex_s, FlowEditorI18n.t(&"insp.ph_expr"), func(v: String) -> void:
			node_edit_committed.emit(nid, {"params_patch": {"expr": v if not v.is_empty() else null, "condition_key": null, "bb_key": null}})
		)))


func _add_float_row(kit: InspectorStyleKit, fv: VBoxContainer, nid: String, label_s: String, p_key: String, cur_val: float) -> void:
	fv.add_child(kit.make_form_row(label_s, kit.make_unit_line_edit(
		"%.2f" % cur_val, FlowEditorI18n.t(&"insp.ph_seconds"), FlowEditorI18n.t(&"insp.unit_sec"),
		func(v: String) -> void: _emit_param_patch(nid, p_key, maxf(0.0, float(InspectorStyleKit.parse_typed_literal(v, "float"))))
	)))


func _emit_param_patch(nid: String, key: String, val: Variant) -> void:
	node_edit_committed.emit(nid, {"params_patch": {key: val}})


static func _resolve_fsm_variant_key(is_initial: bool, is_interrupt: bool, params: Dictionary) -> String:
	var sub_p: String = str(params.get("sub_graph_path", "")).strip_edges()
	if not sub_p.is_empty() or bool(params.get("submachine", false)):
		return "State:subgraph"
	if is_interrupt:
		return "State:interrupt"
	if is_initial:
		return "State:initial"
	return "State"


static func _resolve_fsm_variant_label(is_initial: bool, is_interrupt: bool, params: Dictionary) -> String:
	match _resolve_fsm_variant_key(is_initial, is_interrupt, params):
		"State:subgraph": return FlowEditorI18n.t(&"insp.fsm_kind_subgraph")
		"State:interrupt": return FlowEditorI18n.t(&"insp.fsm_kind_interrupt")
		"State:initial": return FlowEditorI18n.t(&"insp.fsm_kind_initial")
		_: return FlowEditorI18n.t(&"insp.fsm_kind_standard")


func _build_unselected_hint_card(kit: InspectorStyleKit, store: MermaidSessionStore, g: MermaidGraphModel) -> PanelContainer:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var card: PanelContainer = kit.make_card(false)
	var vbox: VBoxContainer = kit.make_vbox(6.0)
	card.add_child(vbox)
	vbox.add_child(kit.make_section_header(FlowEditorI18n.t(&"insp.unselected_title"), "", t.accent))
	var tip: Label = kit.make_label(FlowEditorI18n.t(&"insp.unselected_tip"), kit.fs_sub, t.font_dim)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tip)
	if store.is_live_selected() and g != null and g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM:
		InspectorEdgeEditorSubcard.append_live_fire_event_bar(kit, vbox, func(ev: String) -> void: live_fire_event_requested.emit(ev))
	return card


func _build_empty_quickstart_card(kit: InspectorStyleKit) -> PanelContainer:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var card: PanelContainer = kit.make_card(false)
	var vbox: VBoxContainer = kit.make_vbox(6.0)
	card.add_child(vbox)
	vbox.add_child(kit.make_section_header(FlowEditorI18n.t(&"insp.quick_title"), "", t.accent))
	var hint: Label = kit.make_label(FlowEditorI18n.t(&"insp.quick_body"), kit.fs_sub, t.font_dim)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	return card

#endregion
