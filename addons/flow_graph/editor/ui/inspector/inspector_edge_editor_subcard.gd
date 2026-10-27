@tool
extends RefCounted

## 检视器卡片 2 子组件：流出边手风琴规则编辑器、子节点执行序列表、脉冲发射与只读详情（Inspector Edge Editor Subcard）。[br]
##
## - `FSM` 转换规则：统一分区标题条 + 带语义摘要胶囊的可折叠转换项 + 四模式分段触发器（条件算子 / 脉冲事件 / 黑板公式 / 组合规则）+ 显式标注单位的「驻留 / 优先级」双栏；[br]
## - `BT` 子节点连接：带 `#1 / #2` 执行序徽章的紧凑单行列表（`WeightedSelector` 内联权重输入）。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const FlowOperatorScanner = preload(FlowGraphContracts.SCRIPT_OPERATOR_SCANNER)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const InspectorStyleKit = preload(FlowGraphContracts.SCRIPT_INSPECTOR_STYLE_KIT)

const BT_SINGLE_CHILD_KINDS: PackedStringArray = [
	"Root", "Decorator", "Inverter", "Cooldown", "Repeat", "Repeater",
	"TimeLimit", "Timeout", "Limiter", "ForceSuccess", "ForceFailure",
	"AlwaysSucceed", "AlwaysFail", "Service",
]


static func append_editable_edges(
	kit: InspectorStyleKit,
	parent_vbox: VBoxContainer,
	g: MermaidGraphModel,
	nid: String,
	nkind: String,
	is_interrupt: bool,
	selected_edge_key: String,
	ui_state: Dictionary,
	on_request_rebuild: Callable,
	on_select_node: Callable,
	on_edge_edit: Callable,
	on_edge_delete: Callable
) -> void:
	var eff_schema: StringName = g.resolve_effective_schema()
	var edges_list: Array[Dictionary] = []
	if eff_schema == MermaidGraphModel.SCHEMA_FSM and is_interrupt:
		var any_ed: Dictionary = g.find_edge("*", nid)
		if not any_ed.is_empty():
			edges_list.append(any_ed)
	for out_ed: Dictionary in g.find_outgoing_edges(nid):
		edges_list.append(out_ed)
	if edges_list.is_empty():
		return

	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var sec_title: String = FlowEditorI18n.t(&"insp.sec_fsm_edges")
	if eff_schema != MermaidGraphModel.SCHEMA_FSM:
		sec_title = FlowEditorI18n.t(&"insp.sec_bt_child_single") if BT_SINGLE_CHILD_KINDS.has(nkind) else FlowEditorI18n.t(&"insp.sec_bt_children")
	parent_vbox.add_child(kit.make_section_header(sec_title, str(edges_list.size()), t.accent))

	if eff_schema == MermaidGraphModel.SCHEMA_FSM:
		var ops: Dictionary = FlowOperatorScanner.get_cached()
		for idx: int in range(edges_list.size()):
			parent_vbox.add_child(_build_fsm_transition_item(
				kit, g, nid, edges_list[idx], idx, edges_list.size(),
				selected_edge_key, ops, ui_state, on_request_rebuild,
				on_select_node, on_edge_edit, on_edge_delete
			))
	else:
		var child_vbox: VBoxContainer = kit.make_vbox(4.0)
		for idx: int in range(edges_list.size()):
			child_vbox.add_child(_build_bt_child_row(
				kit, g, nkind, edges_list[idx], idx, selected_edge_key,
				on_select_node, on_edge_edit, on_edge_delete
			))
		parent_vbox.add_child(child_vbox)


#region FSM 转换规则手风琴卡片与四模式触发编辑

static func _build_fsm_transition_item(
	kit: InspectorStyleKit,
	g: MermaidGraphModel,
	nid: String,
	ed: Dictionary,
	idx: int,
	total_count: int,
	selected_edge_key: String,
	ops: Dictionary,
	ui_state: Dictionary,
	on_request_rebuild: Callable,
	on_select_node: Callable,
	on_edge_edit: Callable,
	on_edge_delete: Callable
) -> PanelContainer:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var f_id: String = str(ed.get("from", ""))
	var t_id: String = str(ed.get("to", ""))
	var ekey: String = "%s->%s" % [f_id, t_id]
	var is_canvas_sel: bool = (not selected_edge_key.is_empty() and selected_edge_key == ekey)

	var exp_map: Dictionary = ui_state.get("expanded_edges", {}) as Dictionary
	var is_expanded: bool = true
	if is_canvas_sel:
		is_expanded = true
	elif exp_map.has(ekey):
		is_expanded = bool(exp_map[ekey])
	else:
		is_expanded = (total_count <= 2) or (idx == 0 and selected_edge_key.is_empty())

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", kit.sb_edge_item_active if is_canvas_sel else kit.sb_edge_item)
	var evb: VBoxContainer = kit.make_vbox(6.0)
	box.add_child(evb)

	# 顶部主干行：[▾/▸] + 目标状态名 + 实时语义规则胶囊 + [定位] + [× 删除]
	var h_row: HBoxContainer = kit.make_hbox(5.0)
	evb.add_child(h_row)

	var target_title: String = str(g.find_node(t_id).get("title", t_id))
	var jump_target: String = t_id if f_id != "*" else nid
	var head_caption: String = (
		FlowEditorI18n.t(&"insp.edge_any_caption", [t_id])
		if f_id == "*"
		else ("→ %s" % target_title if target_title == t_id else "→ %s (%s)" % [target_title, t_id])
	)

	var exp_btn := Button.new()
	exp_btn.text = "%s  %s" % ["▾" if is_expanded else "▸", head_caption]
	exp_btn.tooltip_text = FlowEditorI18n.t(&"insp.edge_expand_tip")
	exp_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	exp_btn.flat = true
	exp_btn.focus_mode = Control.FOCUS_NONE
	exp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	exp_btn.add_theme_font_size_override("font_size", kit.fs_sub)
	exp_btn.add_theme_color_override("font_color", t.cat_interrupt.lightened(0.2) if f_id == "*" else t.font_strong)
	exp_btn.add_theme_color_override("font_hover_color", t.accent.lightened(0.25))
	exp_btn.pressed.connect(func() -> void:
		var next_exp: Dictionary = ui_state.get("expanded_edges", {}) as Dictionary
		next_exp[ekey] = not is_expanded
		ui_state["expanded_edges"] = next_exp
		if on_request_rebuild.is_valid():
			on_request_rebuild.call()
	)
	h_row.add_child(exp_btn)

	var sum_info: Dictionary = _summarize_fsm_edge(ed)
	var sum_pill := PanelContainer.new()
	sum_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sum_lbl: Label = kit.make_label("", kit.fs_sub, Color.WHITE)
	sum_pill.add_child(sum_lbl)
	kit.apply_status_pill_theme(sum_pill, sum_lbl, str(sum_info["text"]), sum_info["color"] as Color)
	h_row.add_child(sum_pill)

	if f_id != "*":
		var loc_btn: Button = kit.make_mini_button("", FlowEditorI18n.t(&"insp.edge_locate_tip"), t.accent, InspectorStyleKit.IconFitView)
		loc_btn.pressed.connect(func() -> void: on_select_node.call(jump_target, true))
		h_row.add_child(loc_btn)

	var del_btn: Button = kit.make_mini_button("×", FlowEditorI18n.t(&"insp.edge_del_tip"), t.error)
	del_btn.pressed.connect(func() -> void: on_edge_delete.call(f_id, t_id))
	h_row.add_child(del_btn)

	if not is_expanded:
		return box

	var ep: Dictionary = ed.get("params", {}) as Dictionary
	var raw_lbl: String = str(ed.get("label", "")).strip_edges()
	var ck_s: String = str(ep.get("condition_key", "")).strip_edges()
	var ev_s: String = str(ep.get("trigger_event", "")).strip_edges()
	var bb_s: String = str(ep.get("bb_expr", "")).strip_edges()
	var mt_v: float = float(ep.get("min_state_time", 0.0))
	var prio_v: int = int(ed.get("priority", 0))
	if ck_s.is_empty() and ev_s.is_empty() and bb_s.is_empty() and mt_v <= 0.0 and not raw_lbl.is_empty():
		ck_s = raw_lbl

	var filled_cnt: int = (1 if not ck_s.is_empty() else 0) + (1 if not ev_s.is_empty() else 0) + (1 if not bb_s.is_empty() else 0)
	var auto_mode: int = 0
	if filled_cnt >= 2:
		auto_mode = 3
	elif not ev_s.is_empty():
		auto_mode = 1
	elif not bb_s.is_empty():
		auto_mode = 2

	var mode_map: Dictionary = ui_state.get("edge_modes", {}) as Dictionary
	var cur_mode: int = int(mode_map.get(ekey, auto_mode))
	var tab_labels := PackedStringArray([
		FlowEditorI18n.t(&"insp.edge_mode_cond"),
		FlowEditorI18n.t(&"insp.edge_mode_event"),
		FlowEditorI18n.t(&"insp.edge_mode_expr"),
		FlowEditorI18n.t(&"insp.edge_mode_all"),
	])
	var dots: Array[bool] = [not ck_s.is_empty(), not ev_s.is_empty(), not bb_s.is_empty(), filled_cnt >= 2]
	var on_mode_sel: Callable = func(next_m: int) -> void:
		var m_dict: Dictionary = ui_state.get("edge_modes", {}) as Dictionary
		m_dict[ekey] = next_m
		ui_state["edge_modes"] = m_dict
		if on_request_rebuild.is_valid():
			on_request_rebuild.call()
	evb.add_child(kit.make_segmented_tabs(tab_labels, cur_mode, on_mode_sel, dots))

	if cur_mode == 0 or cur_mode == 3:
		var on_ck_commit: Callable = func(v: String) -> void:
			_commit_fsm_edge_field(ed, f_id, t_id, "condition_key", v, on_edge_edit)
		var ck_ctrl: HBoxContainer = kit.make_picker_input(ck_s, FlowEditorI18n.t(&"insp.ph_condition"), ops.get("conditions", PackedStringArray()) as PackedStringArray, on_ck_commit, true)
		evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_cond"), ck_ctrl))
	if cur_mode == 1 or cur_mode == 3:
		var on_ev_commit: Callable = func(v: String) -> void:
			_commit_fsm_edge_field(ed, f_id, t_id, "trigger_event", v, on_edge_edit)
		var ev_ctrl: HBoxContainer = kit.make_picker_input(ev_s, FlowEditorI18n.t(&"insp.ph_event"), ops.get("events", PackedStringArray()) as PackedStringArray, on_ev_commit)
		evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_event"), ev_ctrl))
	if cur_mode == 2 or cur_mode == 3:
		var on_bb_commit: Callable = func(v: String) -> void:
			_commit_fsm_edge_field(ed, f_id, t_id, "bb_expr", v, on_edge_edit)
		var bb_ctrl: LineEdit = kit.make_line_edit(bb_s, FlowEditorI18n.t(&"insp.ph_expr"), on_bb_commit)
		evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_bb_expr"), bb_ctrl))

	# 显式带前缀与单位标签的「驻留 / 优先级」双栏，彻底告别无标注裸数字框
	var tp_row: HBoxContainer = kit.make_hbox(10.0)
	tp_row.add_child(kit.make_inline_labeled_edit(
		FlowEditorI18n.t(&"insp.edge_lbl_stay"),
		"%.2f" % mt_v,
		FlowEditorI18n.t(&"insp.ph_min_sec"),
		FlowEditorI18n.t(&"insp.unit_sec"),
		func(v: String) -> void:
			_commit_fsm_edge_field(ed, f_id, t_id, "min_state_time", maxf(0.0, float(InspectorStyleKit.parse_typed_literal(v, "float"))), on_edge_edit)
	))
	tp_row.add_child(kit.make_inline_labeled_edit(
		FlowEditorI18n.t(&"insp.edge_lbl_prio"),
		str(prio_v),
		FlowEditorI18n.t(&"insp.ph_priority"),
		"",
		func(v: String) -> void:
			on_edge_edit.call(f_id, t_id, {"priority": int(InspectorStyleKit.parse_typed_literal(v, "int"))})
	))
	evb.add_child(tp_row)
	return box


static func _summarize_fsm_edge(ed: Dictionary) -> Dictionary:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var ep: Dictionary = ed.get("params", {}) as Dictionary
	var ev_s: String = str(ep.get("trigger_event", "")).strip_edges()
	var ck_s: String = str(ep.get("condition_key", "")).strip_edges()
	var bb_s: String = str(ep.get("bb_expr", "")).strip_edges()
	var mt_v: float = float(ep.get("min_state_time", 0.0))
	var prio_v: int = int(ed.get("priority", 0))
	var raw_lbl: String = str(ed.get("label", "")).strip_edges()

	var parts: PackedStringArray = PackedStringArray()
	var col: Color = t.font_dim
	if not ev_s.is_empty():
		parts.append(FlowEditorI18n.t(&"insp.edge_summary_event", [ev_s]))
		col = t.warning
	if not ck_s.is_empty():
		parts.append(ck_s)
		if ev_s.is_empty():
			col = t.accent
	if not bb_s.is_empty():
		parts.append(bb_s if bb_s.length() <= 16 else (bb_s.substr(0, 14) + "…"))
		if parts.size() == 1:
			col = t.accent
	if parts.is_empty() and mt_v <= 0.0 and not raw_lbl.is_empty():
		parts.append(raw_lbl)
		col = t.accent
	if mt_v > 0.0:
		parts.append(FlowEditorI18n.t(&"insp.edge_summary_stay", [mt_v]) if parts.is_empty() else ("≥%.2fs" % mt_v))
		if col == t.font_dim:
			col = t.success
	if prio_v != 0:
		parts.append("P%d" % prio_v)
	if parts.is_empty():
		return {"text": FlowEditorI18n.t(&"insp.edge_summary_direct"), "color": t.font_faint}
	return {"text": " · ".join(parts), "color": col}


static func _commit_fsm_edge_field(ed: Dictionary, f_id: String, t_id: String, field: String, val: Variant, on_edge_edit: Callable) -> void:
	var next_ep: Dictionary = (ed.get("params", {}) as Dictionary).duplicate(true)
	next_ep[field] = val
	var parts: PackedStringArray = PackedStringArray()
	var ev_s: String = str(next_ep.get("trigger_event", "")).strip_edges()
	var ck_s: String = str(next_ep.get("condition_key", "")).strip_edges()
	var bb_s: String = str(next_ep.get("bb_expr", "")).strip_edges()
	var mt_v: float = float(next_ep.get("min_state_time", 0.0))
	if not ev_s.is_empty():
		parts.append("[@%s]" % ev_s)
	if not ck_s.is_empty():
		parts.append(ck_s)
	if not bb_s.is_empty():
		parts.append(bb_s)
	var synth_lbl: String = " ".join(parts)
	if mt_v > 0.0:
		synth_lbl = ("%s (%.2fs)" % [synth_lbl, mt_v]).strip_edges()
	on_edge_edit.call(f_id, t_id, {"label": synth_lbl, "params": next_ep})

#endregion


#region BT 有序子节点列表、运行期脉冲发射与只读详情

static func _build_bt_child_row(
	kit: InspectorStyleKit,
	g: MermaidGraphModel,
	parent_kind: String,
	ed: Dictionary,
	idx: int,
	selected_edge_key: String,
	on_select_node: Callable,
	on_edge_edit: Callable,
	on_edge_delete: Callable
) -> PanelContainer:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var f_id: String = str(ed.get("from", ""))
	var t_id: String = str(ed.get("to", ""))
	var ekey: String = "%s->%s" % [f_id, t_id]
	var child_nd: Dictionary = g.find_node(t_id)
	var child_title: String = str(child_nd.get("title", t_id))
	var child_kind: String = str(child_nd.get("kind", "Action"))
	var child_col: Color = CanvasThemePalette.resolve_accent_color(child_kind, false, false, false)

	var row_box := PanelContainer.new()
	row_box.add_theme_stylebox_override("panel", kit.sb_edge_item_active if selected_edge_key == ekey else kit.sb_row_idle)
	var hb: HBoxContainer = kit.make_hbox(6.0)
	row_box.add_child(hb)

	var ord_pill := PanelContainer.new()
	ord_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ord_lbl: Label = kit.make_label("#%d" % [idx + 1], kit.fs_sub, t.accent)
	ord_pill.add_theme_stylebox_override("panel", kit.sb_unit_tag)
	ord_pill.add_child(ord_lbl)
	hb.add_child(ord_pill)

	var c_ico: Texture2D = CanvasThemePalette.resolve_kind_icon(child_kind, false, false, false)
	if c_ico != null:
		var ico_r: TextureRect = InspectorStyleKit.make_scaled_icon(c_ico, roundi(14.0 * kit.s))
		ico_r.modulate = child_col
		hb.add_child(ico_r)

	var jump_btn := Button.new()
	jump_btn.text = child_title if child_title == t_id else "%s (%s)" % [child_title, t_id]
	jump_btn.tooltip_text = FlowEditorI18n.t(&"insp.edge_locate_tip")
	jump_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	jump_btn.flat = true
	jump_btn.focus_mode = Control.FOCUS_NONE
	jump_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jump_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	jump_btn.add_theme_font_size_override("font_size", kit.fs_sub)
	jump_btn.add_theme_color_override("font_color", t.font_strong)
	jump_btn.add_theme_color_override("font_hover_color", t.accent.lightened(0.25))
	jump_btn.pressed.connect(func() -> void: on_select_node.call(t_id, true))
	hb.add_child(jump_btn)

	if parent_kind == "WeightedSelector":
		var ep: Dictionary = ed.get("params", {}) as Dictionary
		var cur_w: float = float(ep.get("weight", 1.0))
		var w_box: HBoxContainer = kit.make_inline_labeled_edit(
			FlowEditorI18n.t(&"insp.edge_weight"),
			"%.2f" % cur_w,
			FlowEditorI18n.t(&"insp.ph_weight"),
			"",
			func(v: String) -> void:
				var w_val: float = maxf(0.0, float(InspectorStyleKit.parse_typed_literal(v, "float")))
				on_edge_edit.call(f_id, t_id, {"label": "#%d (w=%.2f)" % [idx + 1, w_val], "params_patch": {"weight": w_val}})
		)
		w_box.size_flags_horizontal = Control.SIZE_SHRINK_END
		hb.add_child(w_box)

	var del_btn: Button = kit.make_mini_button("×", FlowEditorI18n.t(&"insp.edge_del_tip"), t.error)
	del_btn.pressed.connect(func() -> void: on_edge_delete.call(f_id, t_id))
	hb.add_child(del_btn)
	return row_box


static func append_live_fire_event_bar(kit: InspectorStyleKit, parent_vbox: VBoxContainer, on_fire_event: Callable) -> void:
	var ops: Dictionary = FlowOperatorScanner.get_cached()
	var ev_cands: PackedStringArray = ops.get("events", PackedStringArray()) as PackedStringArray
	var row: HBoxContainer = kit.make_hbox(4.0)
	var ed: LineEdit = kit.make_line_edit("", FlowEditorI18n.t(&"insp.ph_event"))
	row.add_child(ed)
	if not ev_cands.is_empty():
		var mb := MenuButton.new()
		mb.text = "▾"
		mb.focus_mode = Control.FOCUS_NONE
		mb.custom_minimum_size = Vector2(roundf(23.0 * kit.s), roundf(24.0 * kit.s))
		var pop: PopupMenu = mb.get_popup()
		for i: int in range(ev_cands.size()):
			pop.add_item(ev_cands[i], i)
		pop.id_pressed.connect(func(idx: int) -> void: ed.text = ev_cands[idx])
		row.add_child(mb)
	var send_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.btn_fire_event"), InspectorStyleKit.IconBoltTrigger, true)
	var trigger_fn: Callable = func() -> void:
		var ev_name: String = ed.text.strip_edges()
		if not ev_name.is_empty():
			on_fire_event.call(ev_name)
	ed.text_submitted.connect(func(_t: String) -> void: trigger_fn.call())
	send_btn.pressed.connect(trigger_fn)
	row.add_child(send_btn)
	parent_vbox.add_child(row)


static func append_readonly_details(
	kit: InspectorStyleKit,
	vbox: VBoxContainer,
	g: MermaidGraphModel,
	nid: String,
	nkind: String,
	is_initial: bool,
	params: Dictionary,
	src_file: String,
	src_line: int,
	on_select_node: Callable
) -> void:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	vbox.add_child(kit.make_section_header(FlowEditorI18n.t(&"insp.sec_props"), "", t.accent))
	var prop_panel := PanelContainer.new()
	prop_panel.add_theme_stylebox_override("panel", kit.sb_recessed)
	var pv: VBoxContainer = kit.make_vbox(5.0)
	prop_panel.add_child(pv)
	vbox.add_child(prop_panel)
	pv.add_child(kit.make_kv_row(FlowEditorI18n.t(&"insp.ro_role"), "%s%s" % [FlowEditorI18n.kind_label(nkind), FlowEditorI18n.t(&"insp.ro_role_initial") if is_initial else ""], t.font))
	for pk_v: Variant in params.keys():
		var fmt: Dictionary = InspectorStyleKit.format_watch_value(params[pk_v])
		pv.add_child(kit.make_kv_row(FlowEditorI18n.t(&"insp.ro_param_fmt", [str(pk_v)]), str(fmt["text"]), fmt["color"] as Color))
	if not src_file.is_empty():
		pv.add_child(kit.make_kv_row(FlowEditorI18n.t(&"insp.ro_source"), FlowEditorI18n.t(&"insp.ro_source_fmt", [src_file.get_file(), src_line]), t.accent))

	var outgoing: Array[Dictionary] = g.find_outgoing_edges(nid)
	if not outgoing.is_empty():
		vbox.add_child(kit.make_section_header(FlowEditorI18n.t(&"insp.sec_fsm_edges") if g.resolve_effective_schema() == MermaidGraphModel.SCHEMA_FSM else FlowEditorI18n.t(&"insp.sec_bt_children"), str(outgoing.size()), t.accent))
		for ed: Dictionary in outgoing:
			var tid: String = str(ed.get("to", ""))
			var btn: Button = kit.make_action_button("→ %s  %s" % [str(g.find_node(tid).get("title", tid)), str(ed.get("label", ""))], null, false)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(func() -> void: on_select_node.call(tid, true))
			vbox.add_child(btn)

#endregion
