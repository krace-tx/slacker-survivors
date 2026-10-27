@tool
extends RefCounted

## 检视器统一视觉度量与紧凑表单控件工厂（Inspector Style Kit & Widget Factory）。[br]
##
## 封装 Godot 4 编辑器主题派生样式盒、HiDPI 缩放字号、防塌缩图标按钮（`expand_icon = false` + `icon_max_width`）、状态胶囊及带算子补全菜单（`▾`）的紧凑输入行。

const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

const IconStatusOffline: Texture2D = FlowGraphIcons.STATUS_OFFLINE
const IconStatusLive: Texture2D = FlowGraphIcons.STATUS_LIVE
const IconBoltTrigger: Texture2D = FlowGraphIcons.STATUS_BOLT
const IconCodeDsl: Texture2D = FlowGraphIcons.TB_CODE_DSL
const IconFitView: Texture2D = FlowGraphIcons.TB_FIT_VIEW
const IconResourceList: Texture2D = FlowGraphIcons.TB_RESOURCE_LIST

var s: float = 1.0
var fs_title: int = 15
var fs_body: int = 14
var fs_sub: int = 12
var fs_kpi: int = 14

var sb_panel_bg: StyleBoxFlat = null
var sb_card: StyleBoxFlat = null
var sb_card_focus: StyleBoxFlat = null
var sb_kpi_tile: StyleBoxFlat = null
var sb_recessed: StyleBoxFlat = null
var sb_row_idle: StyleBoxFlat = null
var sb_row_hover: StyleBoxFlat = null
var sb_row_selected: StyleBoxFlat = null
var sb_row_stripe_even: StyleBoxFlat = null
var sb_row_stripe_odd: StyleBoxFlat = null
var sb_btn_norm: StyleBoxFlat = null
var sb_btn_hov: StyleBoxFlat = null
var sb_btn_force: StyleBoxFlat = null
var sb_btn_force_hov: StyleBoxFlat = null
var sb_input: StyleBoxFlat = null
var sb_input_focus: StyleBoxFlat = null


#region 度量初始化与基础原语

func setup(ui_scale: float, base_font_size: int) -> void:
	s = clampf(ui_scale, 0.75, 3.0)
	fs_body = maxi(12, base_font_size)
	fs_title = maxi(13, roundi(float(fs_body) * 1.07))
	fs_sub = maxi(11, roundi(float(fs_body) * 0.88))
	fs_kpi = maxi(13, roundi(float(fs_body) * 1.04))

	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var r_card: int = maxi(4, roundi(6.0 * s))
	var r_small: int = maxi(3, roundi(4.0 * s))
	var bw: int = maxi(1, roundi(1.0 * s))

	sb_panel_bg = CanvasThemePalette.make_flat_sb(t.dark1, Color(0, 0, 0, 0), 0, 0)
	sb_card = make_padded_sb(t.surface, Color(t.border, 0.6), bw, r_card, 12.0 * s, 10.0 * s)
	sb_card_focus = make_padded_sb(t.surface, Color(t.accent, 0.55), bw, r_card, 12.0 * s, 10.0 * s)
	sb_kpi_tile = make_padded_sb(t.dark1, Color(t.border, 0.4), bw, r_small, 8.0 * s, 6.0 * s)
	sb_recessed = make_padded_sb(t.dark1, Color(t.border, 0.4), bw, r_small, 8.0 * s, 6.0 * s)
	sb_row_idle = make_padded_sb(t.dark1, Color(0, 0, 0, 0), bw, r_small, 8.0 * s, 5.0 * s)
	sb_row_hover = make_padded_sb(t.dark1.lerp(t.mono, 0.05), Color(t.font, 0.18), bw, r_small, 8.0 * s, 5.0 * s)
	sb_row_selected = make_padded_sb(t.dark1.lerp(t.accent, 0.14), Color(t.accent, 0.7), bw, r_small, 8.0 * s, 5.0 * s)
	sb_row_stripe_even = make_padded_sb(Color(0.104, 0.122, 0.149, 0.0), Color(0, 0, 0, 0), 0, r_small, 8.0 * s, 4.0 * s)
	sb_row_stripe_odd = make_padded_sb(Color(t.font, 0.03), Color(0, 0, 0, 0), 0, r_small, 8.0 * s, 4.0 * s)
	sb_btn_norm = make_padded_sb(t.dark1, Color(t.border, 0.35), bw, r_small, 8.0 * s, 4.0 * s)
	sb_btn_hov = make_padded_sb(t.dark1.lerp(t.mono, 0.06), Color(t.border_strong, 0.5), bw, r_small, 8.0 * s, 4.0 * s)
	sb_btn_force = make_padded_sb(t.dark1, Color(t.warning, 0.45), bw, r_small, 8.0 * s, 4.0 * s)
	sb_btn_force_hov = make_padded_sb(t.dark1.lerp(t.warning, 0.1), Color(t.warning, 0.75), bw, r_small, 8.0 * s, 4.0 * s)
	sb_input = make_padded_sb(t.dark2, Color(t.border, 0.5), bw, r_small, 6.0 * s, 3.0 * s)
	sb_input_focus = make_padded_sb(t.dark2, Color(t.accent, 0.85), bw, r_small, 6.0 * s, 3.0 * s)

static func make_padded_sb(bg: Color, border: Color, bw: int, radius: int, pad_h: float, pad_v: float) -> StyleBoxFlat:
	var sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(bg, border, bw, radius)
	sb.content_margin_left = roundf(pad_h)
	sb.content_margin_right = roundf(pad_h)
	sb.content_margin_top = roundf(pad_v)
	sb.content_margin_bottom = roundf(pad_v)
	return sb

func make_card(focused: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", sb_card_focus if focused else sb_card)
	return card

func make_vbox(sep_base: float = 7.0) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", roundi(sep_base * s))
	return vb

func make_hbox(sep_base: float = 6.0) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", roundi(sep_base * s))
	return hb

func make_label(txt: String, fsize: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", col)
	return lbl

static func make_scaled_icon(tex: Texture2D, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(float(px), float(px))
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return tr

func make_action_button(text_val: String, icon_tex: Texture2D = null, is_force_style: bool = false) -> Button:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var btn := Button.new()
	btn.text = text_val
	btn.icon = icon_tex
	btn.expand_icon = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0.0, roundf(27.0 * s))
	btn.add_theme_font_size_override("font_size", fs_sub)
	btn.add_theme_constant_override("icon_max_width", maxi(14, roundi(15.0 * s)))
	btn.add_theme_constant_override("h_separation", roundi(5.0 * s))
	btn.add_theme_stylebox_override("normal", sb_btn_force if is_force_style else sb_btn_norm)
	btn.add_theme_stylebox_override("hover", sb_btn_force_hov if is_force_style else sb_btn_hov)
	btn.add_theme_stylebox_override("pressed", sb_btn_force if is_force_style else sb_btn_norm)
	btn.add_theme_color_override("font_color", t.font)
	btn.add_theme_color_override("font_hover_color", t.font_strong)
	btn.add_theme_color_override("icon_normal_color", t.warning if is_force_style else t.icon)
	return btn

func make_mini_button(text_val: String, tooltip: String = "", font_col: Color = Color(0, 0, 0, 0)) -> Button:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var btn := Button.new()
	btn.text = text_val
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(roundf(24.0 * s), roundf(24.0 * s))
	btn.add_theme_font_size_override("font_size", fs_sub)
	btn.add_theme_stylebox_override("normal", sb_btn_norm)
	btn.add_theme_stylebox_override("hover", sb_btn_hov)
	btn.add_theme_stylebox_override("pressed", sb_btn_norm)
	btn.add_theme_color_override("font_color", font_col if font_col.a > 0.01 else t.font_dim)
	btn.add_theme_color_override("font_hover_color", t.font_strong)
	return btn

#endregion


#region 紧凑表单控件与算子补全行工厂

func make_line_edit(initial_text: String, placeholder: String = "", on_commit: Callable = Callable()) -> LineEdit:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var ed := LineEdit.new()
	ed.text = initial_text
	ed.placeholder_text = placeholder
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed.custom_minimum_size = Vector2(roundf(48.0 * s), roundf(24.0 * s))
	ed.add_theme_font_size_override("font_size", fs_sub)
	ed.add_theme_stylebox_override("normal", sb_input)
	ed.add_theme_stylebox_override("focus", sb_input_focus)
	ed.add_theme_color_override("font_color", t.font_strong)
	ed.add_theme_color_override("font_placeholder_color", t.font_faint)
	if on_commit.is_valid():
		var state: Dictionary = {"base": initial_text}
		var commit_fn: Callable = func() -> void:
			var cur: String = ed.text.strip_edges()
			if cur != str(state["base"]):
				state["base"] = cur
				on_commit.call(cur)
		ed.text_submitted.connect(func(_t: String) -> void:
			commit_fn.call()
			ed.release_focus()
		)
		ed.focus_exited.connect(commit_fn)
	return ed

func make_option_button(items: PackedStringArray, selected_idx: int = 0, on_selected: Callable = Callable(), display_labels: PackedStringArray = PackedStringArray()) -> OptionButton:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(roundf(60.0 * s), roundf(24.0 * s))
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", fs_sub)
	ob.add_theme_stylebox_override("normal", sb_input)
	ob.add_theme_stylebox_override("hover", sb_btn_hov)
	ob.add_theme_stylebox_override("pressed", sb_input_focus)
	ob.add_theme_color_override("font_color", t.font_strong)
	var use_labels: bool = (display_labels.size() == items.size())
	for i: int in range(items.size()):
		ob.add_item(display_labels[i] if use_labels else items[i])
	if items.size() > 0:
		ob.select(clampi(selected_idx, 0, items.size() - 1))
	if ob.get_popup() != null:
		ob.get_popup().add_theme_font_size_override("font_size", fs_sub)
	if on_selected.is_valid():
		ob.item_selected.connect(func(idx: int) -> void:
			if idx >= 0 and idx < items.size():
				on_selected.call(items[idx], idx)
		)
	return ob

func make_check_box(label_txt: String, pressed_val: bool, on_toggled: Callable = Callable()) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label_txt
	cb.button_pressed = pressed_val
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_font_size_override("font_size", fs_sub)
	cb.add_theme_color_override("font_color", MermaidThemeService.tokens().font)
	if on_toggled.is_valid():
		cb.toggled.connect(func(on: bool) -> void: on_toggled.call(on))
	return cb

func make_form_row(label_text: String, right_ctrl: Control, label_w: float = 72.0) -> HBoxContainer:
	var row: HBoxContainer = make_hbox(6.0)
	var lbl: Label = make_label(label_text, fs_sub, MermaidThemeService.tokens().font_dim)
	lbl.custom_minimum_size = Vector2(roundf(label_w * s), 0.0)
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.tooltip_text = label_text
	row.add_child(lbl)
	right_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_ctrl)
	return row

func make_picker_input(initial_text: String, placeholder: String, candidates: PackedStringArray, on_commit: Callable, allow_negate: bool = false) -> HBoxContainer:
	var box: HBoxContainer = make_hbox(4.0)
	var state: Dictionary = {"base": initial_text}
	var ed: LineEdit = make_line_edit(initial_text, placeholder)
	var fire_commit: Callable = func(next_val: String) -> void:
		var clean_v: String = next_val.strip_edges()
		ed.text = clean_v
		if clean_v != str(state["base"]):
			state["base"] = clean_v
			if on_commit.is_valid():
				on_commit.call(clean_v)
	ed.text_submitted.connect(func(txt: String) -> void:
		fire_commit.call(txt)
		ed.release_focus()
	)
	ed.focus_exited.connect(func() -> void: fire_commit.call(ed.text))
	box.add_child(ed)

	var mb := MenuButton.new()
	mb.text = "▾"
	mb.tooltip_text = FlowEditorI18n.t(&"insp.picker_tip")
	mb.flat = false
	mb.focus_mode = Control.FOCUS_NONE
	mb.custom_minimum_size = Vector2(roundf(24.0 * s), roundf(24.0 * s))
	mb.add_theme_font_size_override("font_size", fs_sub)
	mb.add_theme_stylebox_override("normal", sb_btn_norm)
	mb.add_theme_stylebox_override("hover", sb_btn_hov)
	mb.add_theme_stylebox_override("pressed", sb_btn_norm)
	mb.add_theme_color_override("font_color", MermaidThemeService.tokens().accent)

	var pop: PopupMenu = mb.get_popup()
	pop.add_theme_font_size_override("font_size", fs_sub)
	var item_values: Array[String] = []
	if allow_negate:
		pop.add_item(FlowEditorI18n.t(&"insp.picker_negate"), 9000)
		if not candidates.is_empty():
			pop.add_separator()
	for i: int in range(candidates.size()):
		var cand: String = candidates[i]
		pop.add_item(cand, i)
		item_values.append(cand)
		if allow_negate:
			pop.add_item("!%s" % cand, 1000 + i)
	if candidates.is_empty():
		pop.add_item(FlowEditorI18n.t(&"insp.picker_empty"), 9998)
		pop.set_item_disabled(pop.get_item_index(9998), true)
	pop.add_separator()
	pop.add_item(FlowEditorI18n.t(&"insp.picker_clear"), 9999)
	pop.id_pressed.connect(func(id: int) -> void:
		if id == 9999:
			fire_commit.call("")
		elif id == 9000:
			var cur_s: String = ed.text.strip_edges()
			if not cur_s.is_empty():
				fire_commit.call(cur_s.substr(1) if cur_s.begins_with("!") else ("!%s" % cur_s))
		elif id >= 1000 and id - 1000 < item_values.size():
			fire_commit.call("!%s" % item_values[id - 1000])
		elif id >= 0 and id < item_values.size():
			fire_commit.call(item_values[id])
	)
	box.add_child(mb)
	return box

#endregion


#region 状态胶囊与值格式化辅助

func apply_status_pill_theme(panel: PanelContainer, lbl: Label, text_val: String, accent: Color) -> void:
	var bg: Color = MermaidThemeService.tokens().dark1.lerp(accent, 0.16)
	panel.add_theme_stylebox_override("panel", make_padded_sb(bg, Color(accent, 0.5), maxi(1, roundi(1.0 * s)), maxi(3, roundi(4.0 * s)), 7.0 * s, 2.0 * s))
	lbl.text = text_val
	lbl.add_theme_color_override("font_color", accent.lightened(0.22))

func make_kv_row(k_text: String, v_text: String, v_col: Color) -> HBoxContainer:
	var row: HBoxContainer = make_hbox(8.0)
	var kl: Label = make_label(k_text, fs_sub, MermaidThemeService.tokens().font_dim)
	kl.custom_minimum_size = Vector2(roundf(76.0 * s), 0.0)
	kl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(kl)
	var vl: Label = make_label(v_text, fs_body, v_col)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(vl)
	return row

static func resolve_state_color(st_name: String) -> Color:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	match st_name:
		"RUNNING": return t.accent
		"SUCCESS": return t.success
		"FAILURE": return t.error
		_: return t.font_dim

static func format_watch_value(val: Variant) -> Dictionary:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	match typeof(val):
		TYPE_BOOL: return {"text": "true" if bool(val) else "false", "color": t.success if bool(val) else t.error}
		TYPE_INT: return {"text": str(int(val)), "color": t.code_number}
		TYPE_FLOAT: return {"text": "%.2f" % float(val), "color": t.code_number}
		TYPE_VECTOR2: return {"text": "(%.1f, %.1f)" % [(val as Vector2).x, (val as Vector2).y], "color": t.code_engine_type}
		TYPE_VECTOR2I: return {"text": "(%d, %d)" % [(val as Vector2i).x, (val as Vector2i).y], "color": t.code_engine_type}
		_: return {"text": str(val), "color": t.font}

static func parse_typed_literal(raw_text: String, type_hint: String = "") -> Variant:
	var s_val: String = raw_text.strip_edges()
	match type_hint:
		"bool": return s_val.to_lower() in ["true", "1", "yes", "on"]
		"int": return int(s_val) if s_val.is_valid_int() else int(float(s_val)) if s_val.is_valid_float() else 0
		"float": return float(s_val) if s_val.is_valid_float() else 0.0
		"String": return raw_text
	if s_val.to_lower() == "true": return true
	if s_val.to_lower() == "false": return false
	if s_val.is_valid_int(): return int(s_val)
	if s_val.is_valid_float(): return float(s_val)
	return s_val

#endregion
