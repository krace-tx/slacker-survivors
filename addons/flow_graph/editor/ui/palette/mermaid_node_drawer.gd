@tool
extends PanelContainer

## 左侧可折叠节点库抽屉（Collapsible Left Node Library Drawer）。[br]
##
## 按当前图模型（FSM / BT / 空白草稿）自适应展示语义分组折叠卡片，支持实时关键字/缩写过滤、单击智能追加与原生拖拽至画布放置。

const FlowNodeCatalog = preload(FlowGraphContracts.SCRIPT_NODE_CATALOG)
const NodeDrawerItemRow = preload(FlowGraphContracts.SCRIPT_NODE_DRAWER_ITEM)
const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const MermaidWorkbenchStyler = preload(FlowGraphContracts.SCRIPT_WORKBENCH_STYLER)

signal collapse_requested()
signal node_spawn_clicked(kind: String, preset: String)

var _ui_scale: float = 1.0
var _base_fs: int = 14
var _is_fsm: bool = false
var _is_empty_generic: bool = true
var _read_only: bool = false
var _query: String = ""
var _state_sig: String = ""
## `{StringName: true}` 记录用户在无搜索态手动折叠的分组 ID
var _collapsed_groups: Dictionary = {}

var _root_vb: VBoxContainer = null
var _header_panel: PanelContainer = null
var _header_hb: HBoxContainer = null
var _title_lbl: Label = null
var _badge_chip: PanelContainer = null
var _badge_lbl: Label = null
var _collapse_btn: Button = null
var _search_pad: MarginContainer = null
var _search_edit: LineEdit = null
var _scroll: ScrollContainer = null
var _groups_vb: VBoxContainer = null
var _empty_lbl: Label = null
var _footer_panel: PanelContainer = null
var _footer_lbl: Label = null


#region 生命周期与公开同步接口

func _ready() -> void:
	_build_ui()
	apply_theme(MermaidThemeService.tokens())
	_rebuild_groups(true)


func sync_context(is_fsm: bool, is_empty_generic: bool, read_only: bool) -> void:
	var next_sig: String = "%s|%s|%s|%s" % [str(is_fsm), str(is_empty_generic), str(read_only), String(FlowEditorI18n.get_locale())]
	_is_fsm = is_fsm
	_is_empty_generic = is_empty_generic
	_read_only = read_only
	if not is_node_ready():
		return
	if next_sig == _state_sig:
		return
	_state_sig = next_sig
	_rebuild_groups(false)


func apply_locale() -> void:
	_state_sig = ""
	var drawer_w: float = 252.0 if FlowEditorI18n.is_english() else 236.0
	custom_minimum_size = Vector2(roundf(drawer_w * _ui_scale), 0.0)
	if not is_node_ready():
		return
	if _title_lbl != null:
		_title_lbl.text = FlowEditorI18n.t(&"drawer.title")
	if _collapse_btn != null:
		_collapse_btn.tooltip_text = FlowEditorI18n.t(&"drawer.collapse_tip")
	if _search_edit != null:
		_search_edit.placeholder_text = FlowEditorI18n.t(&"drawer.search_placeholder")
	if _empty_lbl != null:
		_empty_lbl.text = FlowEditorI18n.t(&"drawer.empty")
	_rebuild_groups(true)


func apply_metrics(ui_scale: float, base_font_size: int) -> void:
	_ui_scale = clampf(ui_scale, 0.75, 3.0)
	_base_fs = maxi(11, base_font_size)
	var drawer_w: float = 252.0 if FlowEditorI18n.is_english() else 236.0
	custom_minimum_size = Vector2(roundf(drawer_w * _ui_scale), 0.0)
	if not is_node_ready():
		return
	var s: float = _ui_scale
	var sub_fs: int = maxi(11, roundi(float(_base_fs) * 0.86))
	if _header_hb != null:
		_header_hb.add_theme_constant_override(&"separation", roundi(5.0 * s))
	if _title_lbl != null:
		_title_lbl.add_theme_font_size_override(&"font_size", _base_fs)
	if _badge_lbl != null:
		_badge_lbl.add_theme_font_size_override(&"font_size", maxi(10, roundi(float(_base_fs) * 0.78)))
	if _collapse_btn != null:
		_collapse_btn.custom_minimum_size = Vector2(roundf(26.0 * s), roundf(26.0 * s))
		_collapse_btn.add_theme_font_size_override(&"font_size", _base_fs)
	if _search_pad != null:
		var m_h: int = roundi(8.0 * s)
		var m_v: int = roundi(6.0 * s)
		_search_pad.add_theme_constant_override(&"margin_left", m_h)
		_search_pad.add_theme_constant_override(&"margin_right", m_h)
		_search_pad.add_theme_constant_override(&"margin_top", m_v)
		_search_pad.add_theme_constant_override(&"margin_bottom", roundi(4.0 * s))
	if _search_edit != null:
		_search_edit.custom_minimum_size = Vector2(0.0, roundf(28.0 * s))
		_search_edit.add_theme_font_size_override(&"font_size", sub_fs)
	if _empty_lbl != null:
		_empty_lbl.add_theme_font_size_override(&"font_size", sub_fs)
	if _footer_lbl != null:
		_footer_lbl.add_theme_font_size_override(&"font_size", maxi(10, roundi(float(_base_fs) * 0.78)))
	apply_theme(MermaidThemeService.tokens())
	_rebuild_groups(true)


func apply_theme(t: MermaidThemeTokens) -> void:
	if t == null or _root_vb == null:
		return
	var s: float = _ui_scale
	add_theme_stylebox_override(&"panel", MermaidThemeTokens.bar(t.base, t.dark3, SIDE_RIGHT, Vector4.ZERO))
	if _header_panel != null:
		_header_panel.add_theme_stylebox_override(&"panel", MermaidThemeTokens.bar(t.base, t.dark3, SIDE_BOTTOM, Vector4(roundf(9.0 * s), roundf(4.0 * s), roundf(6.0 * s), roundf(4.0 * s))))
	if _title_lbl != null:
		_title_lbl.add_theme_color_override(&"font_color", t.font_strong)
	if _badge_chip != null:
		_badge_chip.add_theme_stylebox_override(&"panel", MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, Vector4(roundf(6.0 * s), roundf(2.0 * s), roundf(6.0 * s), roundf(2.0 * s))))
	if _badge_lbl != null:
		_badge_lbl.add_theme_color_override(&"font_color", t.accent)
	if _collapse_btn != null:
		MermaidWorkbenchStyler.style_flat_button(_collapse_btn, t, t.font_dim, t.icon, Vector4(4, 2, 4, 2))
	if _search_edit != null:
		var sb_in: StyleBoxFlat = MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(t.border, 0.45), 1, Vector4(roundf(8.0 * s), roundf(4.0 * s), roundf(8.0 * s), roundf(4.0 * s)))
		var sb_fc: StyleBoxFlat = MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(t.accent, 0.75), 1, Vector4(roundf(8.0 * s), roundf(4.0 * s), roundf(8.0 * s), roundf(4.0 * s)))
		_search_edit.add_theme_stylebox_override(&"normal", sb_in)
		_search_edit.add_theme_stylebox_override(&"focus", sb_fc)
		_search_edit.add_theme_color_override(&"font_color", t.font)
		_search_edit.add_theme_color_override(&"font_placeholder_color", Color(t.font, 0.38))
		_search_edit.add_theme_color_override(&"caret_color", t.accent)
		_search_edit.add_theme_color_override(&"clear_button_color", t.font_dim)
		_search_edit.add_theme_color_override(&"clear_button_color_pressed", t.font_strong)
	if _footer_panel != null:
		_footer_panel.add_theme_stylebox_override(&"panel", MermaidThemeTokens.bar(t.base, t.dark3, SIDE_TOP, Vector4(roundf(8.0 * s), roundf(5.0 * s), roundf(8.0 * s), roundf(5.0 * s))))
	if _footer_lbl != null:
		_footer_lbl.add_theme_color_override(&"font_color", t.warning if _read_only else t.font_faint)


func set_search_query(q: String) -> void:
	if _search_edit != null and _search_edit.text != q:
		_search_edit.text = q
	_on_search_changed(q)


func get_visible_group_count() -> int:
	return _groups_vb.get_child_count() if _groups_vb != null else 0

#endregion


#region 内部控件树搭建与分组手风琴渲染

func _build_ui() -> void:
	if _root_vb != null:
		return
	custom_minimum_size = Vector2(236.0, 0.0)
	_root_vb = VBoxContainer.new()
	_root_vb.add_theme_constant_override(&"separation", 0)
	add_child(_root_vb)

	_header_panel = PanelContainer.new()
	_root_vb.add_child(_header_panel)
	_header_hb = HBoxContainer.new()
	_header_hb.add_theme_constant_override(&"separation", 5)
	_header_panel.add_child(_header_hb)

	_title_lbl = Label.new()
	_title_lbl.text = FlowEditorI18n.t(&"drawer.title")
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_hb.add_child(_title_lbl)

	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_hb.add_child(h_spacer)

	_badge_chip = PanelContainer.new()
	_badge_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header_hb.add_child(_badge_chip)
	_badge_lbl = Label.new()
	_badge_chip.add_child(_badge_lbl)

	_collapse_btn = Button.new()
	_collapse_btn.text = "«"
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.tooltip_text = FlowEditorI18n.t(&"drawer.collapse_tip")
	_collapse_btn.pressed.connect(func() -> void: collapse_requested.emit())
	_header_hb.add_child(_collapse_btn)

	_search_pad = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_search_pad.add_theme_constant_override(StringName(side), 6)
	_root_vb.add_child(_search_pad)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = FlowEditorI18n.t(&"drawer.search_placeholder")
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	_search_pad.add_child(_search_edit)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_vb.add_child(_scroll)

	var scroll_pad := MarginContainer.new()
	scroll_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_pad.add_theme_constant_override(&"margin_left", 8)
	scroll_pad.add_theme_constant_override(&"margin_right", 8)
	scroll_pad.add_theme_constant_override(&"margin_top", 2)
	scroll_pad.add_theme_constant_override(&"margin_bottom", 8)
	_scroll.add_child(scroll_pad)

	_groups_vb = VBoxContainer.new()
	_groups_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups_vb.add_theme_constant_override(&"separation", 8)
	scroll_pad.add_child(_groups_vb)

	_empty_lbl = Label.new()
	_empty_lbl.text = FlowEditorI18n.t(&"drawer.empty")
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_lbl.visible = false
	_root_vb.add_child(_empty_lbl)

	_footer_panel = PanelContainer.new()
	_root_vb.add_child(_footer_panel)
	_footer_lbl = Label.new()
	_footer_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_panel.add_child(_footer_lbl)


func _on_search_changed(new_text: String) -> void:
	_query = new_text
	_rebuild_groups(true)


func _rebuild_groups(_force: bool) -> void:
	if _groups_vb == null:
		return
	for ch: Node in _groups_vb.get_children():
		_groups_vb.remove_child(ch)
		ch.queue_free()

	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var s: float = _ui_scale
	var groups: Array[Dictionary] = FlowNodeCatalog.build_groups(_is_fsm, _is_empty_generic, _query)
	var total_items: int = 0
	for grp: Dictionary in groups:
		total_items += (grp["items"] as Array).size()

	if _badge_lbl != null:
		var badge_key: StringName = &"drawer.badge_all" if _is_empty_generic else (&"drawer.badge_fsm" if _is_fsm else &"drawer.badge_bt")
		_badge_lbl.text = FlowEditorI18n.t(badge_key, [total_items])
	if _footer_lbl != null:
		_footer_lbl.text = FlowEditorI18n.t(&"drawer.hint_readonly") if _read_only else FlowEditorI18n.t(&"drawer.hint_edit")
		_footer_lbl.add_theme_color_override(&"font_color", t.warning if _read_only else t.font_faint)

	var has_groups: bool = not groups.is_empty()
	_scroll.visible = has_groups
	_empty_lbl.visible = not has_groups
	if not has_groups:
		return

	_groups_vb.add_theme_constant_override(&"separation", roundi(8.0 * s))
	var searching: bool = not _query.strip_edges().is_empty()
	var grp_fs: int = maxi(11, roundi(float(_base_fs) * 0.85))
	var cnt_fs: int = maxi(10, roundi(float(_base_fs) * 0.76))

	for grp: Dictionary in groups:
		var gid: StringName = grp["id"] as StringName
		var g_col: Color = grp["color"] as Color
		var items: Array = grp["items"] as Array
		var is_collapsed: bool = (not searching) and _collapsed_groups.has(gid)

		var sec_vb := VBoxContainer.new()
		sec_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec_vb.add_theme_constant_override(&"separation", roundi(3.0 * s))
		_groups_vb.add_child(sec_vb)

		var hdr_btn := Button.new()
		hdr_btn.focus_mode = Control.FOCUS_NONE
		hdr_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hdr_btn.clip_text = true
		hdr_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hdr_btn.custom_minimum_size = Vector2(0.0, roundf(25.0 * s))
		hdr_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var chevron: String = "▸" if is_collapsed else "▾"
		hdr_btn.text = "%s  %s" % [chevron, str(grp["title"])]
		hdr_btn.add_theme_font_size_override(&"font_size", grp_fs)
		hdr_btn.add_theme_color_override(&"font_color", t.font_dim)
		hdr_btn.add_theme_color_override(&"font_hover_color", t.font_strong)
		hdr_btn.add_theme_color_override(&"font_pressed_color", t.font_strong)

		var sb_hdr: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(g_col, 0.08), Color(0, 0, 0, 0), 0, maxi(3, roundi(3.0 * s)))
		sb_hdr.border_width_left = maxi(2, roundi(2.5 * s))
		sb_hdr.border_color = Color(g_col, 0.85)
		sb_hdr.content_margin_left = roundf(8.0 * s)
		sb_hdr.content_margin_right = roundf(28.0 * s)
		var sb_hdr_hov: StyleBoxFlat = sb_hdr.duplicate() as StyleBoxFlat
		sb_hdr_hov.bg_color = Color(g_col, 0.15)
		hdr_btn.add_theme_stylebox_override(&"normal", sb_hdr)
		hdr_btn.add_theme_stylebox_override(&"hover", sb_hdr_hov)
		hdr_btn.add_theme_stylebox_override(&"pressed", sb_hdr_hov)
		hdr_btn.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())

		var cnt_lbl := Label.new()
		cnt_lbl.text = str(items.size())
		cnt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cnt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cnt_lbl.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		cnt_lbl.offset_left = -roundf(28.0 * s)
		cnt_lbl.offset_right = -roundf(7.0 * s)
		cnt_lbl.add_theme_font_size_override(&"font_size", cnt_fs)
		cnt_lbl.add_theme_color_override(&"font_color", Color(g_col, 0.85))
		hdr_btn.add_child(cnt_lbl)

		var items_vb := VBoxContainer.new()
		items_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		items_vb.add_theme_constant_override(&"separation", roundi(3.0 * s))
		items_vb.visible = not is_collapsed

		var captured_gid: StringName = gid
		hdr_btn.pressed.connect(func() -> void:
			if _collapsed_groups.has(captured_gid):
				_collapsed_groups.erase(captured_gid)
			else:
				_collapsed_groups[captured_gid] = true
			_rebuild_groups(true)
		)

		sec_vb.add_child(hdr_btn)
		sec_vb.add_child(items_vb)

		if not is_collapsed:
			for sp_v: Variant in items:
				var row := NodeDrawerItemRow.new()
				row.configure(sp_v as Dictionary, _ui_scale, _base_fs, _read_only)
				row.item_activated.connect(func(k: String, p: String) -> void: node_spawn_clicked.emit(k, p))
				items_vb.add_child(row)

#endregion
