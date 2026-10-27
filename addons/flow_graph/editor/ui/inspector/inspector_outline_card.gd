@tool
extends RefCounted

## 检视器卡片 3 & 4：交互式拓扑节点大纲（O(N) 原位状态刷新）与 P3 黑板 Schema 声明编辑器（Inspector Outline & Schema Card）。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const InspectorStyleKit = preload(FlowGraphContracts.SCRIPT_INSPECTOR_STYLE_KIT)

const BB_TYPES: PackedStringArray = ["float", "int", "bool", "String"]

signal node_selected_from_inspector(node_id: String, center_view: bool)
signal schema_edited(new_schema: Array[Dictionary])

## `{String (node_id): {"panel": PanelContainer, "badge": Label, "selected": bool}}`
var _outline_rows: Dictionary = {}


#region 拓扑节点大纲构建与原位刷新

func clear_refs() -> void:
	_outline_rows.clear()


func build_outline_card(
	kit: InspectorStyleKit,
	store: MermaidSessionStore,
	g: MermaidGraphModel,
	interrupt_set: Dictionary,
	selected_node_id: String,
	frame: Dictionary
) -> PanelContainer:
	clear_refs()
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var card: PanelContainer = kit.make_card(false)
	var vbox: VBoxContainer = kit.make_vbox(7.0)
	card.add_child(vbox)

	var hdr_row: HBoxContainer = kit.make_hbox(6.0)
	vbox.add_child(hdr_row)
	var hdr_lbl: Label = kit.make_label(FlowEditorI18n.t(&"insp.outline_title"), kit.fs_body, t.font)
	hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(hdr_lbl)
	hdr_row.add_child(kit.make_label(FlowEditorI18n.t(&"insp.outline_sub", [g.nodes.size()]), kit.fs_sub, t.font_faint))

	var list_vbox: VBoxContainer = kit.make_vbox(4.0)
	vbox.add_child(list_vbox)

	var is_runtime: bool = store.is_live_selected() or store.is_snapshot_selected()
	var active_nodes: Dictionary = frame.get("active_nodes", {}) as Dictionary if frame.get("active_nodes", {}) is Dictionary else {}

	for nd: Dictionary in g.nodes:
		var nid: String = str(nd.get("id", ""))
		var ntitle: String = str(nd.get("title", nid))
		var nkind: String = str(nd.get("kind", "State"))
		var is_initial: bool = (nid == g.initial_node_id)
		var is_interrupt: bool = interrupt_set.has(nid)
		var is_sel: bool = (nid == selected_node_id)
		var has_code: bool = not str((nd.get("source", {}) as Dictionary).get("file", "")).is_empty()
		var has_bp: bool = store.has_breakpoint(nid)

		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", kit.sb_row_selected if is_sel else kit.sb_row_idle)
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var hbox: HBoxContainer = kit.make_hbox(6.0)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hbox)

		var accent_col: Color = CanvasThemePalette.resolve_accent_color(nkind, is_initial, is_interrupt, CanvasThemePalette.is_fsm_terminal(g, nid))
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(maxf(2.5, roundf(3.0 * kit.s)), roundf(16.0 * kit.s))
		bar.color = accent_col
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(bar)

		if has_bp:
			var bp_lbl: Label = kit.make_label("●", kit.fs_sub, t.error)
			bp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(bp_lbl)

		var ico_tex: Texture2D = CanvasThemePalette.resolve_kind_icon(nkind, is_initial, is_interrupt, CanvasThemePalette.is_fsm_terminal(g, nid))
		if ico_tex != null:
			var ico_r: TextureRect = InspectorStyleKit.make_scaled_icon(ico_tex, roundi(15.0 * kit.s))
			ico_r.modulate = accent_col
			ico_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(ico_r)

		var title_s: String = ("%s  (%s)" % [ntitle, nid]) if ntitle != nid else nid
		var t_lbl: Label = kit.make_label(title_s, kit.fs_body, t.font_strong if is_sel else t.font)
		t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(t_lbl)

		if has_code:
			var code_ico: TextureRect = InspectorStyleKit.make_scaled_icon(InspectorStyleKit.IconCodeDsl, roundi(13.0 * kit.s))
			code_ico.modulate = t.font_dim
			code_ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(code_ico)

		var k_disp: String = FlowEditorI18n.kind_label(nkind)
		var right_txt: String = FlowEditorI18n.t(&"insp.outline_entry_fmt", [k_disp]) if is_initial else (FlowEditorI18n.t(&"insp.outline_int_fmt", [k_disp]) if is_interrupt else k_disp)
		var right_col: Color = accent_col.lightened(0.12)
		if is_runtime:
			if active_nodes.has(nid):
				var st_rec: Dictionary = active_nodes[nid] as Dictionary
				var st_s: String = str(st_rec.get("state", "RUNNING"))
				var st_disp: String = FlowEditorI18n.state_label(st_s)
				var bd_s: String = str(st_rec.get("badge", ""))
				right_txt = ("%s · %s" % [st_disp, bd_s]) if not bd_s.is_empty() else st_disp
				right_col = InspectorStyleKit.resolve_state_color(st_s)
			else:
				right_txt = FlowEditorI18n.state_label("IDLE")
				right_col = t.font_faint

		var badge_lbl: Label = kit.make_label(right_txt, kit.fs_sub, right_col)
		badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(badge_lbl)

		_outline_rows[nid] = {"panel": row, "badge": badge_lbl, "selected": is_sel}

		var cap_nid: String = nid
		var cap_sel: bool = is_sel
		row.mouse_entered.connect(func() -> void:
			if not cap_sel:
				row.add_theme_stylebox_override("panel", kit.sb_row_hover)
		)
		row.mouse_exited.connect(func() -> void:
			if not cap_sel:
				row.add_theme_stylebox_override("panel", kit.sb_row_idle)
		)
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					node_selected_from_inspector.emit(cap_nid, mb.double_click)
					row.accept_event()
		)
		list_vbox.add_child(row)

	return card


func refresh_live(active_nodes: Dictionary) -> void:
	var faint_col: Color = MermaidThemeService.tokens().font_faint
	var idle_txt: String = FlowEditorI18n.state_label("IDLE")
	for nid_v: Variant in _outline_rows.keys():
		var nid: String = str(nid_v)
		var rec: Dictionary = _outline_rows[nid] as Dictionary
		var badge_lbl: Label = rec.get("badge", null) as Label
		if badge_lbl == null:
			continue
		if active_nodes.has(nid):
			var st_info: Dictionary = active_nodes[nid] as Dictionary
			var st_name: String = str(st_info.get("state", "RUNNING"))
			var st_disp: String = FlowEditorI18n.state_label(st_name)
			var b_extra: String = str(st_info.get("badge", ""))
			badge_lbl.text = ("%s · %s" % [st_disp, b_extra]) if not b_extra.is_empty() else st_disp
			badge_lbl.add_theme_color_override("font_color", InspectorStyleKit.resolve_state_color(st_name))
		else:
			badge_lbl.text = idle_txt
			badge_lbl.add_theme_color_override("font_color", faint_col)

#endregion


#region P3 黑板 Schema 声明卡片（DRAFT / RESOURCE 编辑态）

func build_schema_card(kit: InspectorStyleKit, g: MermaidGraphModel) -> PanelContainer:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var card: PanelContainer = kit.make_card(false)
	var vbox: VBoxContainer = kit.make_vbox(7.0)
	card.add_child(vbox)

	var hdr_row: HBoxContainer = kit.make_hbox(6.0)
	vbox.add_child(hdr_row)
	var hdr_lbl: Label = kit.make_label(FlowEditorI18n.t(&"insp.schema_title", [g.blackboard_schema.size()]), kit.fs_body, t.font)
	hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(hdr_lbl)

	var add_btn: Button = kit.make_action_button(FlowEditorI18n.t(&"insp.schema_add"), null, false)
	add_btn.add_theme_color_override("font_color", t.accent)
	add_btn.pressed.connect(func() -> void:
		var next_arr: Array[Dictionary] = _clone_schema(g.blackboard_schema)
		next_arr.append({"key": _next_unique_bb_key(next_arr), "type": "float", "default": 0.0})
		schema_edited.emit(next_arr)
	)
	hdr_row.add_child(add_btn)

	if g.blackboard_schema.is_empty():
		vbox.add_child(kit.make_label(FlowEditorI18n.t(&"insp.schema_empty_hint"), kit.fs_sub, t.font_faint))
		return card

	var table := PanelContainer.new()
	table.add_theme_stylebox_override("panel", kit.sb_recessed)
	var rows_vbox: VBoxContainer = kit.make_vbox(4.0)
	table.add_child(rows_vbox)
	vbox.add_child(table)

	for i: int in range(g.blackboard_schema.size()):
		var entry: Dictionary = g.blackboard_schema[i]
		var cur_key: String = str(entry.get("key", ""))
		var cur_type: String = str(entry.get("type", "float"))
		var cur_def: Variant = entry.get("default", 0.0)
		var row_idx: int = i

		var row: HBoxContainer = kit.make_hbox(4.0)
		var key_ed: LineEdit = kit.make_line_edit(cur_key, FlowEditorI18n.t(&"insp.ph_field_name"), func(nk: String) -> void:
			if nk.is_empty():
				return
			var next_s: Array[Dictionary] = _clone_schema(g.blackboard_schema)
			if row_idx < next_s.size():
				next_s[row_idx]["key"] = nk
				schema_edited.emit(next_s)
		)
		row.add_child(key_ed)

		var t_idx: int = maxi(0, BB_TYPES.find(cur_type))
		var type_ob: OptionButton = kit.make_option_button(BB_TYPES, t_idx, func(nt: String, _idx: int) -> void:
			var next_s: Array[Dictionary] = _clone_schema(g.blackboard_schema)
			if row_idx < next_s.size():
				next_s[row_idx]["type"] = nt
				next_s[row_idx]["default"] = _default_for_type(nt)
				schema_edited.emit(next_s)
		)
		type_ob.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_child(type_ob)

		if cur_type == "bool":
			var cb: CheckBox = kit.make_check_box("true" if bool(cur_def) else "false", bool(cur_def), func(on: bool) -> void:
				var next_s: Array[Dictionary] = _clone_schema(g.blackboard_schema)
				if row_idx < next_s.size():
					next_s[row_idx]["default"] = on
					schema_edited.emit(next_s)
			)
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(cb)
		else:
			var def_ed: LineEdit = kit.make_line_edit(str(cur_def), FlowEditorI18n.t(&"insp.ph_init_val"), func(nv: String) -> void:
				var next_s: Array[Dictionary] = _clone_schema(g.blackboard_schema)
				if row_idx < next_s.size():
					next_s[row_idx]["default"] = InspectorStyleKit.parse_typed_literal(nv, cur_type)
					schema_edited.emit(next_s)
			)
			row.add_child(def_ed)

		var del_btn: Button = kit.make_mini_button("✕", FlowEditorI18n.t(&"insp.schema_del_tip"), t.error)
		del_btn.pressed.connect(func() -> void:
			var next_s: Array[Dictionary] = _clone_schema(g.blackboard_schema)
			if row_idx < next_s.size():
				next_s.remove_at(row_idx)
				schema_edited.emit(next_s)
		)
		row.add_child(del_btn)
		rows_vbox.add_child(row)

	return card


static func _clone_schema(src: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in src:
		out.append(d.duplicate(true))
	return out


static func _next_unique_bb_key(arr: Array[Dictionary]) -> String:
	var used: Dictionary = {}
	for d: Dictionary in arr:
		used[str(d.get("key", ""))] = true
	var seq: int = 1
	while used.has("var_%d" % seq):
		seq += 1
	return "var_%d" % seq


static func _default_for_type(t_name: String) -> Variant:
	match t_name:
		"bool": return false
		"int": return 0
		"String": return ""
		_: return 0.0

#endregion
