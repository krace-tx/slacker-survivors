@tool
extends RefCounted

## 检视器卡片 1：紧凑会话状态条、冲突解决、蓝图↔运行互切与静态拓扑诊断（Inspector Session Header & Linter Card）。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const FlowGraphLinter = preload(FlowGraphContracts.SCRIPT_LINTER)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const InspectorStyleKit = preload(FlowGraphContracts.SCRIPT_INSPECTOR_STYLE_KIT)

signal resolve_external_conflict_requested(resource_path: String, accept_disk: bool)
signal switch_to_resource_requested(resource_path: String)
signal switch_to_live_requested(memory_id: int)
signal diagnostic_node_clicked(node_id: String)

var last_lint_issues: Array[Dictionary] = []

var _status_pill_panel: PanelContainer = null
var _status_pill_lbl: Label = null
var _kpi_active_val_lbl: Label = null


#region 公开构建与原位遥测刷新

func clear_refs() -> void:
	_status_pill_panel = null
	_status_pill_lbl = null
	_kpi_active_val_lbl = null
	last_lint_issues.clear()


func build(kit: InspectorStyleKit, store: MermaidSessionStore, g: MermaidGraphModel, frame: Dictionary) -> PanelContainer:
	clear_refs()
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var card: PanelContainer = kit.make_card(false)
	var vbox: VBoxContainer = kit.make_vbox(6.0)
	card.add_child(vbox)

	var top_row: HBoxContainer = kit.make_hbox(6.0)
	vbox.add_child(top_row)
	top_row.add_child(InspectorStyleKit.make_scaled_icon(_resolve_mode_icon(store), roundi(15.0 * kit.s)))

	var title_lbl: Label = kit.make_label(_resolve_session_title(store, g), kit.fs_body, t.font_strong)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_row.add_child(title_lbl)

	var pill_box := PanelContainer.new()
	pill_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pill_lbl: Label = kit.make_label("", kit.fs_sub, Color.WHITE)
	pill_box.add_child(pill_lbl)
	top_row.add_child(pill_box)
	_status_pill_panel = pill_box
	_status_pill_lbl = pill_lbl

	var pill_info: Dictionary = _resolve_mode_pill_info(store, frame)
	kit.apply_status_pill_theme(pill_box, pill_lbl, str(pill_info["text"]), pill_info["color"] as Color)

	var sub_txt: String = _resolve_session_subtitle(store)
	if not sub_txt.is_empty():
		var sub_lbl: Label = kit.make_label(sub_txt, kit.fs_sub, t.font_dim)
		sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub_lbl.tooltip_text = sub_txt
		vbox.add_child(sub_lbl)

	# 紧凑单行拓扑摘要条（替代高占高三宫格，让下方的焦点节点编辑器直达首屏）
	var meta_strip := PanelContainer.new()
	meta_strip.add_theme_stylebox_override("panel", kit.sb_meta_strip)
	var meta_row: HBoxContainer = kit.make_hbox(6.0)
	meta_strip.add_child(meta_row)
	vbox.add_child(meta_strip)

	var arch_lbl: Label = kit.make_label(_describe_schema_short(g), kit.fs_sub, t.accent)
	meta_row.add_child(arch_lbl)
	meta_row.add_child(kit.make_label("·", kit.fs_sub, t.font_faint))

	var topo_scale: String = FlowEditorI18n.t(&"insp.kpi_scale_fmt", [g.nodes.size(), g.edges.size()]) if g != null else FlowEditorI18n.t(&"insp.kpi_scale_zero")
	meta_row.add_child(kit.make_label(topo_scale, kit.fs_sub, t.font))
	meta_row.add_child(kit.make_label("·", kit.fs_sub, t.font_faint))

	var is_runtime: bool = store.is_live_selected() or store.is_snapshot_selected()
	var active_nodes: Dictionary = frame.get("active_nodes", {}) as Dictionary if frame.get("active_nodes", {}) is Dictionary else {}
	var focus_prefix: String = FlowEditorI18n.t(&"insp.kpi_focus_short") if is_runtime else FlowEditorI18n.t(&"insp.kpi_entry_short")
	meta_row.add_child(kit.make_label(focus_prefix, kit.fs_sub, t.font_dim))

	var focus_val_txt: String = _summarize_active_focus(g, active_nodes) if is_runtime else _resolve_entry_display(g)
	var focus_val_lbl: Label = kit.make_label(focus_val_txt, kit.fs_sub, t.success if is_runtime else t.cat_entry)
	focus_val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_val_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	focus_val_lbl.tooltip_text = focus_val_txt
	meta_row.add_child(focus_val_lbl)
	_kpi_active_val_lbl = focus_val_lbl

	_append_resource_live_link_and_conflict(kit, vbox, store)
	if store.is_editable_mode() and g != null:
		_append_linter_diagnostics(kit, vbox, store, g)
	return card


func refresh_live(kit: InspectorStyleKit, store: MermaidSessionStore, g: MermaidGraphModel, frame: Dictionary) -> void:
	if _status_pill_panel != null and _status_pill_lbl != null:
		var pill_info: Dictionary = _resolve_mode_pill_info(store, frame)
		kit.apply_status_pill_theme(_status_pill_panel, _status_pill_lbl, str(pill_info["text"]), pill_info["color"] as Color)
	if _kpi_active_val_lbl != null:
		var active_nodes: Dictionary = frame.get("active_nodes", {}) as Dictionary if frame.get("active_nodes", {}) is Dictionary else {}
		var summary_txt: String = _summarize_active_focus(g, active_nodes)
		_kpi_active_val_lbl.text = summary_txt
		_kpi_active_val_lbl.tooltip_text = summary_txt

#endregion


#region 冲突横幅、蓝图互切与静态 Linter 诊断区

func _append_resource_live_link_and_conflict(kit: InspectorStyleKit, vbox: VBoxContainer, store: MermaidSessionStore) -> void:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	if store.is_resource_selected():
		var rec: Dictionary = store.get_active_record()
		var rpath: String = str(rec.get("path", ""))
		if bool(rec.get("external_conflict", false)) and not rpath.is_empty():
			var banner := PanelContainer.new()
			banner.add_theme_stylebox_override("panel", InspectorStyleKit.make_padded_sb(
				t.dark1.lerp(t.warning, 0.12), Color(t.warning, 0.55),
				maxi(1, roundi(1.0 * kit.s)), maxi(3, roundi(4.0 * kit.s)), 8.0 * kit.s, 6.0 * kit.s
			))
			var b_vbox: VBoxContainer = kit.make_vbox(6.0)
			banner.add_child(b_vbox)
			var b_lbl: Label = kit.make_label(FlowEditorI18n.t(&"insp.conflict_msg"), kit.fs_sub, t.warning.lerp(t.font_strong, 0.35))
			b_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b_vbox.add_child(b_lbl)

			var b_row: HBoxContainer = kit.make_hbox(6.0)
			b_vbox.add_child(b_row)
			var reload_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.conflict_reload"), InspectorStyleKit.IconResourceList, true)
			reload_btn.pressed.connect(func() -> void: resolve_external_conflict_requested.emit(rpath, true))
			b_row.add_child(reload_btn)
			var keep_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.conflict_keep"), null, false)
			keep_btn.pressed.connect(func() -> void: resolve_external_conflict_requested.emit(rpath, false))
			b_row.add_child(keep_btn)
			vbox.add_child(banner)

		var live_matches: Array[Dictionary] = store.find_live_instances_for_resource(rpath)
		if not live_matches.is_empty():
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", roundi(6.0 * kit.s))
			flow.add_theme_constant_override("v_separation", roundi(4.0 * kit.s))
			for m: Dictionary in live_matches:
				var mid: int = int(m["memory_id"])
				var live_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.switch_live", [str(m["title"])]), InspectorStyleKit.IconStatusLive, false)
				live_btn.add_theme_color_override("icon_normal_color", t.success)
				live_btn.pressed.connect(func() -> void: switch_to_live_requested.emit(mid))
				flow.add_child(live_btn)
			vbox.add_child(flow)
		return

	if store.is_live_selected() or store.is_snapshot_selected():
		var linked_res: String = store.get_active_linked_resource_path()
		if not linked_res.is_empty():
			var link_row: HBoxContainer = kit.make_hbox(6.0)
			var res_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.open_source_res", [linked_res.get_file()]), InspectorStyleKit.IconResourceList, false)
			res_btn.add_theme_color_override("icon_normal_color", t.accent)
			res_btn.pressed.connect(func() -> void: switch_to_resource_requested.emit(linked_res))
			link_row.add_child(res_btn)
			vbox.add_child(link_row)


func _append_linter_diagnostics(kit: InspectorStyleKit, vbox: VBoxContainer, store: MermaidSessionStore, g: MermaidGraphModel) -> void:
	var owner_path: String = str(store.get_active_record().get("path", "")) if store.is_resource_selected() else ""
	last_lint_issues = FlowGraphLinter.lint(g, owner_path)
	if last_lint_issues.is_empty():
		return
	if g.nodes.is_empty() and last_lint_issues.size() == 1 and str(last_lint_issues[0].get("code", "")) == "EMPTY_GRAPH":
		return

	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var err_cnt: int = 0
	var warn_cnt: int = 0
	for iss: Dictionary in last_lint_issues:
		if str(iss.get("severity", "")) == FlowGraphLinter.SEVERITY_ERROR:
			err_cnt += 1
		else:
			warn_cnt += 1

	var box_col: Color = t.error if err_cnt > 0 else t.warning
	var lint_panel := PanelContainer.new()
	lint_panel.add_theme_stylebox_override("panel", InspectorStyleKit.make_padded_sb(
		t.dark1.lerp(box_col, 0.08), Color(box_col, 0.45),
		maxi(1, roundi(1.0 * kit.s)), maxi(3, roundi(4.0 * kit.s)), 8.0 * kit.s, 6.0 * kit.s
	))
	var lv: VBoxContainer = kit.make_vbox(4.0)
	lint_panel.add_child(lv)

	var summary: String = FlowEditorI18n.t(&"insp.lint_summary", [err_cnt, warn_cnt])
	lv.add_child(kit.make_label(summary, kit.fs_sub, box_col.lightened(0.18)))

	for issue: Dictionary in last_lint_issues:
		var is_err: bool = str(issue.get("severity", "")) == FlowGraphLinter.SEVERITY_ERROR
		var target_nid: String = str(issue.get("node_id", "")).strip_edges()
		var item_col: Color = t.error if is_err else t.warning

		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", kit.sb_row_idle)
		var row_hb: HBoxContainer = kit.make_hbox(6.0)
		row_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(row_hb)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(maxf(2.5, roundf(3.0 * kit.s)), roundf(12.0 * kit.s))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = item_col
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_hb.add_child(dot)

		var msg_lbl: Label = kit.make_label(str(issue.get("message", "")), kit.fs_sub, item_col.lerp(t.font, 0.35))
		msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_hb.add_child(msg_lbl)

		if not target_nid.is_empty():
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.tooltip_text = FlowEditorI18n.t(&"insp.lint_locate_tip", [target_nid])
			row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", kit.sb_row_hover))
			row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", kit.sb_row_idle))
			row.gui_input.connect(func(ev: InputEvent) -> void:
				if FlowEditorInput.is_pointer_press(ev, FlowEditorInput.PTR_PRIMARY):
					diagnostic_node_clicked.emit(target_nid)
					row.accept_event()
			)
		lv.add_child(row)

	vbox.add_child(lint_panel)

#endregion


#region 概览元数据解析辅助

static func _resolve_mode_icon(store: MermaidSessionStore) -> Texture2D:
	if store.is_live_selected():
		return InspectorStyleKit.IconStatusLive
	if store.is_resource_selected():
		return InspectorStyleKit.IconCodeDsl
	return InspectorStyleKit.IconStatusOffline


static func _resolve_session_title(store: MermaidSessionStore, g: MermaidGraphModel) -> String:
	if store.is_live_selected() or store.is_snapshot_selected():
		var desc: Dictionary = store.get_active_record().get("desc", {}) as Dictionary
		var t_s: String = str(desc.get("title", ""))
		return t_s if not t_s.is_empty() else str(desc.get("primary_class", FlowEditorI18n.t(&"insp.title_live_fallback")))
	if store.is_resource_selected():
		var rpath: String = str(store.get_active_record().get("path", ""))
		return rpath.get_file() if not rpath.is_empty() else FlowEditorI18n.t(&"insp.title_res_fallback")
	if g != null and not g.title.is_empty() and g.title != "mermaid_graph":
		return g.title
	return FlowEditorI18n.t(&"insp.title_draft")


static func _resolve_session_subtitle(store: MermaidSessionStore) -> String:
	if store.is_live_selected() or store.is_snapshot_selected():
		var desc: Dictionary = store.get_active_record().get("desc", {}) as Dictionary
		var owner_str: String = "%s (%s)" % [str(desc.get("owner_name", "None")), MermaidSessionStore.format_mem_id(int(desc.get("owner_id", 0)))]
		var raw_chain: Variant = desc.get("inheritance_chain", [])
		var parts: PackedStringArray = PackedStringArray()
		if raw_chain is Array:
			for c: Variant in raw_chain as Array:
				parts.append(str(c))
		return FlowEditorI18n.t(&"insp.sub_owner", [owner_str, ("  ·  " + " → ".join(parts)) if not parts.is_empty() else ""])
	if store.is_resource_selected():
		var rpath: String = str(store.get_active_record().get("path", ""))
		return rpath if not rpath.is_empty() else FlowEditorI18n.t(&"insp.sub_mem_res")
	return FlowEditorI18n.t(&"insp.sub_draft")


static func _resolve_mode_pill_info(store: MermaidSessionStore, frame: Dictionary) -> Dictionary:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	if bool(frame.get("_is_scrubbing", false)):
		return {
			"text": FlowEditorI18n.t(&"insp.pill_scrub", [int(frame.get("_scrub_index", 0)) + 1, int(frame.get("_scrub_total", 1))]),
			"color": t.warning,
		}
	if store.is_live_selected():
		var paused: bool = bool(frame.get("paused", false))
		return {"text": FlowEditorI18n.t(&"insp.pill_paused") if paused else FlowEditorI18n.t(&"insp.pill_live"), "color": t.warning if paused else t.success}
	if store.is_snapshot_selected():
		return {"text": FlowEditorI18n.t(&"insp.pill_snapshot"), "color": t.warning}
	if store.is_resource_selected():
		var rec: Dictionary = store.get_active_record()
		if bool(rec.get("external_conflict", false)):
			return {"text": FlowEditorI18n.t(&"insp.pill_conflict"), "color": t.error}
		var dirty: bool = bool(rec.get("dirty", false))
		return {"text": FlowEditorI18n.t(&"insp.pill_dirty") if dirty else FlowEditorI18n.t(&"insp.pill_synced"), "color": t.warning if dirty else t.success}
	return {"text": FlowEditorI18n.t(&"insp.pill_draft"), "color": t.accent}


static func _describe_schema_short(g: MermaidGraphModel) -> String:
	if g == null or g.nodes.is_empty():
		return FlowEditorI18n.t(&"insp.schema_empty")
	var s_name: StringName = g.resolve_effective_schema()
	if s_name == MermaidGraphModel.SCHEMA_FSM:
		return FlowEditorI18n.t(&"insp.schema_fsm")
	if s_name == MermaidGraphModel.SCHEMA_BT:
		return FlowEditorI18n.t(&"insp.schema_bt")
	return String(g.diagram_type)


static func _resolve_entry_display(g: MermaidGraphModel) -> String:
	if g == null or g.nodes.is_empty():
		return "—"
	if not g.initial_node_id.is_empty():
		return str(g.find_node(g.initial_node_id).get("title", g.initial_node_id))
	return str((g.nodes[0] as Dictionary).get("title", FlowEditorI18n.t(&"insp.kpi_auto_entry")))


static func _summarize_active_focus(g: MermaidGraphModel, active_nodes: Dictionary) -> String:
	if active_nodes.is_empty():
		return FlowEditorI18n.t(&"insp.kpi_idle")
	var running_titles: PackedStringArray = PackedStringArray()
	for k: Variant in active_nodes.keys():
		var nid: String = str(k)
		var st_d: Dictionary = active_nodes[nid] as Dictionary
		if str(st_d.get("state", "RUNNING")) == "RUNNING":
			var nd: Dictionary = g.find_node(nid) if g != null else {}
			running_titles.append(str(nd.get("title", nid)))
	if running_titles.size() == 1:
		return running_titles[0]
	if running_titles.size() > 1:
		return "%s (%d)" % [running_titles[running_titles.size() - 1], running_titles.size()]
	return FlowEditorI18n.t(&"insp.kpi_eval_count", [active_nodes.size()])

#endregion
