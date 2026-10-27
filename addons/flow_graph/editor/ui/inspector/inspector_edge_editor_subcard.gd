@tool
extends RefCounted

## 检视器卡片 2 子组件：流出边条件/权重原位编辑、运行期脉冲发射与只读详情（Inspector Edge Editor Subcard）。[br]
##
## 负责 FSM 转换边条件（`condition_key`、`trigger_event`、`bb_expr`、`min_state_time`、`priority`）、BT `WeightedSelector` 抽样权重、运行期 `fire_event` 工具条及只读属性表渲染。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const FlowOperatorScanner = preload(FlowGraphContracts.SCRIPT_OPERATOR_SCANNER)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const InspectorStyleKit = preload(FlowGraphContracts.SCRIPT_INSPECTOR_STYLE_KIT)


static func append_editable_edges(
	kit: InspectorStyleKit,
	parent_vbox: VBoxContainer,
	g: MermaidGraphModel,
	nid: String,
	nkind: String,
	is_interrupt: bool,
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

	var ops: Dictionary = FlowOperatorScanner.get_cached()
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	parent_vbox.add_child(kit.make_label(FlowEditorI18n.t(&"insp.edges_header", [edges_list.size()]), kit.fs_sub, t.font_dim))

	for idx: int in range(edges_list.size()):
		var ed: Dictionary = edges_list[idx]
		var f_id: String = str(ed.get("from", ""))
		var t_id: String = str(ed.get("to", ""))
		var ep: Dictionary = ed.get("params", {}) as Dictionary
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", kit.sb_recessed)
		var evb: VBoxContainer = kit.make_vbox(4.0)
		box.add_child(evb)

		var h_row: HBoxContainer = kit.make_hbox(6.0)
		evb.add_child(h_row)
		var jump_target: String = t_id if f_id != "*" else nid
		var edge_caption: String = FlowEditorI18n.t(&"insp.edge_any_caption", [t_id]) if f_id == "*" else (("→ %s (%s)" % [str(g.find_node(t_id).get("title", t_id)), t_id]) if eff_schema == MermaidGraphModel.SCHEMA_FSM else ("#%d → %s" % [idx + 1, str(g.find_node(t_id).get("title", t_id))]))
		var nav_btn: Button = kit.make_action_button(edge_caption, null, false)
		nav_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_btn.pressed.connect(func() -> void: on_select_node.call(jump_target, true))
		h_row.add_child(nav_btn)

		var del_btn: Button = kit.make_mini_button("✕", FlowEditorI18n.t(&"insp.edge_del_tip"), t.error)
		del_btn.pressed.connect(func() -> void: on_edge_delete.call(f_id, t_id))
		h_row.add_child(del_btn)

		if eff_schema == MermaidGraphModel.SCHEMA_FSM:
			evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_cond"), kit.make_picker_input(str(ep.get("condition_key", "")), FlowEditorI18n.t(&"insp.ph_condition"), ops.get("conditions", PackedStringArray()) as PackedStringArray, func(v: String) -> void:
				_commit_fsm_edge_field(ed, f_id, t_id, "condition_key", v, on_edge_edit)
			, true), 62.0))
			evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_event"), kit.make_picker_input(str(ep.get("trigger_event", "")), FlowEditorI18n.t(&"insp.ph_event"), ops.get("events", PackedStringArray()) as PackedStringArray, func(v: String) -> void:
				_commit_fsm_edge_field(ed, f_id, t_id, "trigger_event", v, on_edge_edit)
			), 62.0))
			evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_bb_expr"), kit.make_line_edit(str(ep.get("bb_expr", "")), FlowEditorI18n.t(&"insp.ph_expr"), func(v: String) -> void:
				_commit_fsm_edge_field(ed, f_id, t_id, "bb_expr", v, on_edge_edit)
			), 62.0))
			var tp_row: HBoxContainer = kit.make_hbox(4.0)
			tp_row.add_child(kit.make_line_edit("%.2f" % float(ep.get("min_state_time", 0.0)), FlowEditorI18n.t(&"insp.ph_min_sec"), func(v: String) -> void:
				_commit_fsm_edge_field(ed, f_id, t_id, "min_state_time", maxf(0.0, float(InspectorStyleKit.parse_typed_literal(v, "float"))), on_edge_edit)
			))
			tp_row.add_child(kit.make_line_edit(str(int(ed.get("priority", 0))), FlowEditorI18n.t(&"insp.ph_priority"), func(v: String) -> void:
				on_edge_edit.call(f_id, t_id, {"priority": int(InspectorStyleKit.parse_typed_literal(v, "int"))})
			))
			evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_time_prio"), tp_row, 62.0))
		elif nkind == "WeightedSelector":
			var cur_w: float = float(ep.get("weight", 1.0))
			evb.add_child(kit.make_form_row(FlowEditorI18n.t(&"insp.edge_weight"), kit.make_line_edit("%.2f" % cur_w, FlowEditorI18n.t(&"insp.ph_weight"), func(v: String) -> void:
				var w_val: float = maxf(0.0, float(InspectorStyleKit.parse_typed_literal(v, "float")))
				on_edge_edit.call(f_id, t_id, {"label": "#%d (w=%.2f)" % [idx + 1, w_val], "params_patch": {"weight": w_val}})
			), 62.0))

		parent_vbox.add_child(box)


static func _commit_fsm_edge_field(ed: Dictionary, f_id: String, t_id: String, field: String, val: Variant, on_edge_edit: Callable) -> void:
	var next_ep: Dictionary = (ed.get("params", {}) as Dictionary).duplicate(true)
	next_ep[field] = val
	var parts: PackedStringArray = PackedStringArray()
	var ev_s: String = str(next_ep.get("trigger_event", "")).strip_edges()
	var ck_s: String = str(next_ep.get("condition_key", "")).strip_edges()
	var bb_s: String = str(next_ep.get("bb_expr", "")).strip_edges()
	var mt_v: float = float(next_ep.get("min_state_time", 0.0))
	if not ev_s.is_empty():
		parts.append("[⚡%s]" % ev_s)
	if not ck_s.is_empty():
		parts.append(ck_s)
	if not bb_s.is_empty():
		parts.append(bb_s)
	var synth_lbl: String = " ".join(parts)
	if mt_v > 0.0:
		synth_lbl = ("%s (%.2fs)" % [synth_lbl, mt_v]).strip_edges()
	on_edge_edit.call(f_id, t_id, {"label": synth_lbl, "params": next_ep})


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
		mb.custom_minimum_size = Vector2(roundf(24.0 * kit.s), roundf(24.0 * kit.s))
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
		vbox.add_child(kit.make_label(FlowEditorI18n.t(&"insp.ro_outgoing", [outgoing.size()]), kit.fs_sub, t.font_dim))
		for ed: Dictionary in outgoing:
			var tid: String = str(ed.get("to", ""))
			var btn: Button = kit.make_action_button("→ %s  %s" % [str(g.find_node(tid).get("title", tid)), str(ed.get("label", ""))], null, false)
			btn.pressed.connect(func() -> void: on_select_node.call(tid, true))
			vbox.add_child(btn)
