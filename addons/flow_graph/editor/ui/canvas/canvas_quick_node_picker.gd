@tool
extends RefCounted

## 画布浮动快速建点搜索面板（Canvas Floating Quick Node Picker）。[br]
##
## 支持「空白处双击 / 空格唤起」、「拉线松手即建点自动连线」与「连线中间插入节点」三种上下文；内置实时模糊筛选与键盘上下键秒选。

const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const FlowNodeCatalog = preload(FlowGraphContracts.SCRIPT_NODE_CATALOG)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

signal node_kind_chosen(kind: String, world_pos: Vector2, connect_from_id: String, split_to_id: String)
signal picker_closed(committed: bool)

const NON_LEAF_BT_SET: Dictionary = {
	"Cooldown": true, "Inverter": true, "Repeater": true, "TimeLimit": true, "Service": true,
	"ForceSuccess": true, "ForceFailure": true,
	"Sequence": true, "Selector": true, "Parallel": true, "WeightedSelector": true, "UtilitySelector": true,
}

var _popup: PopupPanel = null
var _header_lbl: Label = null
var _search_edit: LineEdit = null
var _scroll: ScrollContainer = null
var _list_vbox: VBoxContainer = null
var _row_buttons: Array[Button] = []
var _filtered_kinds: Array[String] = []
var _is_fsm_ctx: bool = false
var _is_empty_generic_ctx: bool = false
var _is_edge_insert_ctx: bool = false
var _has_bt_root_ctx: bool = false
var _highlight_idx: int = 0
var _ui_scale: float = 1.0

var _pending_world_pos: Vector2 = Vector2.ZERO
var _pending_from_id: String = ""
var _pending_split_to_id: String = ""
var _committed_this_open: bool = false


#region 生命周期装配与弹窗唤起

func setup(host_canvas: Control) -> void:
	if host_canvas == null or _popup != null:
		return
	_popup = PopupPanel.new()
	_popup.name = "CanvasQuickNodePicker"
	_popup.popup_hide.connect(_on_popup_hidden)

	var root_vb := VBoxContainer.new()
	root_vb.name = "RootVBox"
	_popup.add_child(root_vb)

	_header_lbl = Label.new()
	_header_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root_vb.add_child(_header_lbl)

	_search_edit = LineEdit.new()
	_search_edit.text_changed.connect(_on_search_text_changed)
	_search_edit.gui_input.connect(_on_search_gui_input)
	root_vb.add_child(_search_edit)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list_vbox)

	host_canvas.add_child(_popup)


func is_open() -> bool:
	return _popup != null and _popup.visible


func close_picker() -> void:
	if _popup != null and _popup.visible:
		_popup.hide()


func open_picker(
	screen_pos: Vector2i,
	world_pos: Vector2,
	is_fsm: bool,
	is_empty_generic: bool,
	ui_scale: float = 1.0,
	connect_from_id: String = "",
	from_display_title: String = "",
	split_to_id: String = "",
	to_display_title: String = "",
	has_bt_root: bool = false
) -> void:
	if _popup == null:
		return
	_ui_scale = clampf(ui_scale, 0.75, 3.0)
	_pending_world_pos = world_pos
	_pending_from_id = connect_from_id
	_pending_split_to_id = split_to_id
	_committed_this_open = false
	_is_fsm_ctx = is_fsm
	_is_empty_generic_ctx = is_empty_generic
	_is_edge_insert_ctx = not split_to_id.is_empty()
	_has_bt_root_ctx = has_bt_root

	_apply_popup_theme()

	if not split_to_id.is_empty():
		var f_show: String = from_display_title if not from_display_title.is_empty() else connect_from_id
		var t_show: String = to_display_title if not to_display_title.is_empty() else split_to_id
		_header_lbl.text = FlowEditorI18n.t(&"picker.title_insert", [f_show, t_show])
	elif not connect_from_id.is_empty():
		var src_show: String = from_display_title if not from_display_title.is_empty() else connect_from_id
		_header_lbl.text = FlowEditorI18n.t(&"picker.title_connect", [src_show])
	else:
		_header_lbl.text = FlowEditorI18n.t(&"picker.title_add")

	_search_edit.placeholder_text = FlowEditorI18n.t(&"picker.search_placeholder")
	_search_edit.text = ""
	_rebuild_filtered_list("")

	var picker_w: float = 264.0 if FlowEditorI18n.is_english() else 248.0
	var pop_size := Vector2i(roundi(picker_w * _ui_scale), roundi(296.0 * _ui_scale))
	_popup.size = pop_size
	_popup.position = screen_pos
	_popup.popup()
	_search_edit.grab_focus.call_deferred()

#endregion


#region 候选过滤、分组列表构建与键盘导航

func _apply_popup_theme() -> void:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var s: float = _ui_scale
	var fs_body: int = maxi(12, roundi(12.5 * s))
	var fs_sub: int = maxi(11, roundi(11.0 * s))
	var pad_sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(t.surface, Color(t.accent, 0.55), maxi(1, roundi(1.0 * s)), maxi(5, roundi(6.0 * s)))
	pad_sb.content_margin_left = roundf(8.0 * s)
	pad_sb.content_margin_right = roundf(8.0 * s)
	pad_sb.content_margin_top = roundf(8.0 * s)
	pad_sb.content_margin_bottom = roundf(8.0 * s)
	_popup.add_theme_stylebox_override("panel", pad_sb)

	var root_vb: VBoxContainer = _header_lbl.get_parent() as VBoxContainer
	if root_vb != null:
		root_vb.add_theme_constant_override("separation", roundi(6.0 * s))
	_list_vbox.add_theme_constant_override("separation", roundi(2.0 * s))

	_header_lbl.add_theme_font_size_override("font_size", fs_sub)
	_header_lbl.add_theme_color_override("font_color", t.accent if not _pending_from_id.is_empty() else t.font_dim)

	var in_sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(t.dark2, Color(t.border, 0.65), 1, maxi(3, roundi(4.0 * s)))
	in_sb.content_margin_left = roundf(7.0 * s)
	in_sb.content_margin_right = roundf(7.0 * s)
	in_sb.content_margin_top = roundf(4.0 * s)
	in_sb.content_margin_bottom = roundf(4.0 * s)
	var in_focus_sb: StyleBoxFlat = in_sb.duplicate() as StyleBoxFlat
	in_focus_sb.border_color = Color(t.accent, 0.9)
	_search_edit.add_theme_font_size_override("font_size", fs_body)
	_search_edit.add_theme_stylebox_override("normal", in_sb)
	_search_edit.add_theme_stylebox_override("focus", in_focus_sb)
	_search_edit.add_theme_color_override("font_color", t.font_strong)
	_search_edit.add_theme_color_override("font_placeholder_color", t.font_faint)
	_scroll.custom_minimum_size = Vector2(roundf(224.0 * s), roundf(210.0 * s))


func _on_search_text_changed(new_text: String) -> void:
	_rebuild_filtered_list(new_text)


func _rebuild_filtered_list(query: String) -> void:
	for child: Node in _list_vbox.get_children():
		_list_vbox.remove_child(child)
		child.queue_free()
	_row_buttons.clear()
	_filtered_kinds.clear()

	var raw_groups: Array[Dictionary] = FlowNodeCatalog.build_groups(_is_fsm_ctx, _is_empty_generic_ctx and not _is_edge_insert_ctx, query)
	var groups_to_show: Array[Dictionary] = []
	for grp: Dictionary in raw_groups:
		var kept: Array[Dictionary] = []
		for item_v: Variant in (grp["items"] as Array):
			var it: Dictionary = item_v as Dictionary
			var k_id: String = str(it.get("kind", ""))
			var p_id: String = str(it.get("preset", ""))
			if k_id == "Root" and (_has_bt_root_ctx or not _pending_from_id.is_empty() or _is_edge_insert_ctx):
				continue
			if p_id == FlowNodeCatalog.PRESET_INTERRUPT and (not _pending_from_id.is_empty() or _is_edge_insert_ctx):
				continue
			if _is_edge_insert_ctx and not _is_fsm_ctx and not NON_LEAF_BT_SET.has(k_id):
				continue
			kept.append(it)
		if not kept.is_empty():
			groups_to_show.append({
				"title": str(grp["title"]),
				"color": grp["color"] as Color,
				"items": kept,
			})

	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var s: float = _ui_scale
	var fs_row: int = maxi(12, roundi(12.5 * s))
	var fs_grp: int = maxi(10, roundi(10.5 * s))

	if groups_to_show.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = FlowEditorI18n.t(&"picker.empty")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", maxi(11, roundi(11.5 * s)))
		empty_lbl.add_theme_color_override("font_color", t.font_faint)
		_list_vbox.add_child(empty_lbl)
		_highlight_idx = -1
		return

	_highlight_idx = 0
	for grp: Dictionary in groups_to_show:
		var grp_lbl := Label.new()
		grp_lbl.text = str(grp["title"])
		grp_lbl.add_theme_font_size_override("font_size", fs_grp)
		grp_lbl.add_theme_color_override("font_color", Color(grp["color"] as Color, 0.85))
		_list_vbox.add_child(grp_lbl)

		for it_v: Variant in (grp["items"] as Array):
			var it: Dictionary = it_v as Dictionary
			var k_name: String = str(it.get("key", it.get("kind", "")))
			var idx_capture: int = _filtered_kinds.size()
			_filtered_kinds.append(k_name)

			var btn := Button.new()
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.focus_mode = Control.FOCUS_NONE
			btn.expand_icon = false
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			btn.custom_minimum_size = Vector2(0.0, roundf(27.0 * s))
			btn.text = str(it["title"])
			var cat_col: Color = it["color"] as Color
			btn.icon = it["icon"] as Texture2D
			btn.add_theme_constant_override("icon_max_width", maxi(14, roundi(15.0 * s)))
			btn.add_theme_constant_override("h_separation", roundi(7.0 * s))
			btn.add_theme_font_size_override("font_size", fs_row)
			btn.add_theme_color_override("font_color", t.font)
			btn.add_theme_color_override("font_hover_color", t.font_strong)
			btn.add_theme_color_override("icon_normal_color", cat_col)
			btn.add_theme_color_override("icon_hover_color", cat_col.lightened(0.15))
			btn.mouse_entered.connect(func() -> void: _set_highlight_index(idx_capture, false))
			btn.pressed.connect(func() -> void: _commit_index(idx_capture))
			_list_vbox.add_child(btn)
			_row_buttons.append(btn)

	_refresh_row_styles()


func _set_highlight_index(next_idx: int, ensure_scroll: bool) -> void:
	if _filtered_kinds.is_empty():
		_highlight_idx = -1
		return
	_highlight_idx = posmod(next_idx, _filtered_kinds.size())
	_refresh_row_styles()
	if ensure_scroll and _highlight_idx >= 0 and _highlight_idx < _row_buttons.size():
		var target_btn: Button = _row_buttons[_highlight_idx]
		var top_y: float = target_btn.position.y
		var bot_y: float = top_y + target_btn.size.y
		var cur_v: float = float(_scroll.scroll_vertical)
		var view_h: float = _scroll.size.y
		if top_y < cur_v:
			_scroll.scroll_vertical = roundi(top_y)
		elif bot_y > cur_v + view_h and view_h > 10.0:
			_scroll.scroll_vertical = roundi(bot_y - view_h)


func _refresh_row_styles() -> void:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var s: float = _ui_scale
	var r_sm: int = maxi(3, roundi(4.0 * s))
	var sb_idle: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, r_sm)
	sb_idle.content_margin_left = roundf(7.0 * s)
	sb_idle.content_margin_right = roundf(7.0 * s)
	var sb_hi: StyleBoxFlat = CanvasThemePalette.make_flat_sb(t.dark1.lerp(t.accent, 0.18), Color(t.accent, 0.55), 1, r_sm)
	sb_hi.content_margin_left = roundf(7.0 * s)
	sb_hi.content_margin_right = roundf(7.0 * s)
	for i: int in range(_row_buttons.size()):
		var b: Button = _row_buttons[i]
		var active_sb: StyleBoxFlat = sb_hi if i == _highlight_idx else sb_idle
		b.add_theme_stylebox_override("normal", active_sb)
		b.add_theme_stylebox_override("hover", sb_hi)
		b.add_theme_stylebox_override("pressed", sb_hi)


func _on_search_gui_input(event: InputEvent) -> void:
	var act: StringName = FlowEditorInput.resolve_modal_action(event, true)
	if act == &"":
		return
	match act:
		FlowEditorInput.MODAL_NAV_NEXT:
			_set_highlight_index(_highlight_idx + 1, true)
			_search_edit.accept_event()
		FlowEditorInput.MODAL_NAV_PREV:
			_set_highlight_index(_highlight_idx - 1, true)
			_search_edit.accept_event()
		FlowEditorInput.MODAL_CONFIRM:
			_commit_index(_highlight_idx)
			_search_edit.accept_event()
		FlowEditorInput.MODAL_CANCEL:
			close_picker()
			_search_edit.accept_event()


func _commit_index(idx: int) -> void:
	if idx < 0 or idx >= _filtered_kinds.size():
		return
	var chosen_kind: String = _filtered_kinds[idx]
	_committed_this_open = true
	if _popup != null:
		_popup.hide()
	node_kind_chosen.emit(chosen_kind, _pending_world_pos, _pending_from_id, _pending_split_to_id)


func _on_popup_hidden() -> void:
	picker_closed.emit(_committed_this_open)

#endregion
