@tool
extends VBoxContainer

## 项目图资源浏览页（Project Graph Resource Browser）。[br]
##
## 右侧停靠栏「资源」页：展示 [`MermaidResourceCatalog`](../../bridge/mermaid_resource_catalog.gd) 扫描到的全部图资源，[br]
## 支持关键字搜索（文件名 / 目录 / 类名）、`全部 / FSM / BT` 筛选与按目录分组；单击条目即在画布打开。[br]
## 条目右侧标注会话状态：`已打开`、`未保存 *`、`运行中`（存在由该资源编译的运行期实例）。

const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const MermaidWorkbenchStyler = preload(FlowGraphContracts.SCRIPT_WORKBENCH_STYLER)

signal resource_open_requested(path: String)
signal rescan_requested()

const FILTER_ALL: StringName = &"all"
const FILTER_FSM: StringName = &"fsm"
const FILTER_BT: StringName = &"bt"

var _entries: Array[Dictionary] = []
var _open_paths: Dictionary = {}  ## {String (path): bool (dirty)}
var _live_paths: Dictionary = {}  ## {String (path): true}
var _active_path: String = ""
var _marks_sig: String = ""
var _filter: StringName = FILTER_ALL
var _query: String = ""
var _suppress_select: bool = false

var _toolbar_box: HBoxContainer = null
var _search: LineEdit = null
var _filter_btns: Dictionary = {}  ## {StringName: Button}
var _rescan_btn: Button = null
var _count_lbl: Label = null
var _tree: Tree = null
var _empty_lbl: Label = null


#region 生命周期与公开接口

func _ready() -> void:
	_build()
	apply_theme(MermaidThemeService.tokens())
	_rebuild_tree()


func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries.duplicate()
	if is_node_ready():
		_rebuild_tree()


## 更新会话标记；内容未变化时不重建列表。
func set_session_marks(open_paths: Dictionary, live_paths: Dictionary, active_path: String) -> void:
	var sig: String = "%s#%s#%s" % [str(open_paths), str(live_paths.keys()), active_path]
	if sig == _marks_sig:
		return
	_marks_sig = sig
	_open_paths = open_paths.duplicate()
	_live_paths = live_paths.duplicate()
	_active_path = active_path
	if is_node_ready():
		_rebuild_tree()


func get_visible_paths() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: Dictionary in _filtered_entries():
		out.append(str(e["path"]))
	return out


func set_query(text: String) -> void:
	if _search != null:
		_search.text = text
	_on_query_changed(text)


func set_filter(filter_id: StringName) -> void:
	_filter = filter_id
	for k: Variant in _filter_btns.keys():
		(_filter_btns[k] as Button).set_pressed_no_signal(StringName(str(k)) == filter_id)
	_rebuild_tree()


func apply_metrics(ui_scale: float, base_font_size: int) -> void:
	var s: float = clampf(ui_scale, 0.75, 3.0)
	var sub_fs: int = maxi(11, roundi(float(base_font_size) * 0.88))
	add_theme_constant_override(&"separation", roundi(6.0 * s))
	if _toolbar_box != null:
		_toolbar_box.add_theme_constant_override(&"separation", roundi(4.0 * s))
	if _search != null:
		_search.custom_minimum_size = Vector2(0.0, roundf(28.0 * s))
		_search.add_theme_font_size_override(&"font_size", base_font_size)
	for b: Variant in _filter_btns.values():
		(b as Button).custom_minimum_size = Vector2(0.0, roundf(26.0 * s))
		(b as Button).add_theme_font_size_override(&"font_size", sub_fs)
	if _rescan_btn != null:
		_rescan_btn.add_theme_font_size_override(&"font_size", sub_fs)
	if _count_lbl != null:
		_count_lbl.add_theme_font_size_override(&"font_size", sub_fs)
	if _tree != null:
		_tree.add_theme_font_size_override(&"font_size", base_font_size)
		_tree.add_theme_constant_override(&"v_separation", roundi(4.0 * s))
		_tree.set_column_custom_minimum_width(1, roundi(128.0 * s))
	if _empty_lbl != null:
		_empty_lbl.add_theme_font_size_override(&"font_size", sub_fs)


func apply_theme(t: MermaidThemeTokens) -> void:
	if t == null or _tree == null:
		return
	add_theme_constant_override(&"separation", 6)
	if _search != null:
		var sb_in: StyleBoxFlat = MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, Vector4(8, 4, 8, 4))
		var sb_in_focus: StyleBoxFlat = MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(t.accent, 0.65), 1, Vector4(8, 4, 8, 4))
		_search.add_theme_stylebox_override(&"normal", sb_in)
		_search.add_theme_stylebox_override(&"focus", sb_in_focus)
		_search.add_theme_color_override(&"font_color", t.font)
		_search.add_theme_color_override(&"font_placeholder_color", Color(t.font, 0.38))
		_search.add_theme_color_override(&"caret_color", t.accent)
		_search.add_theme_color_override(&"selection_color", t.code_selection)
		_search.add_theme_color_override(&"clear_button_color", t.font_dim)
		_search.add_theme_color_override(&"clear_button_color_pressed", t.font_strong)

	var sb_sel: StyleBoxFlat = MermaidThemeTokens.flat(Color(t.accent, 0.16), MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, Vector4(4, 2, 4, 2))
	var sb_sel_focus: StyleBoxFlat = MermaidThemeTokens.flat(Color(t.accent, 0.22), MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, Vector4(4, 2, 4, 2))
	_tree.add_theme_stylebox_override(&"panel", MermaidThemeTokens.flat(t.dark1, 0, Color(0, 0, 0, 0), 0, Vector4(6, 4, 6, 4)))
	_tree.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_tree.add_theme_stylebox_override(&"selected", sb_sel)
	_tree.add_theme_stylebox_override(&"selected_focus", sb_sel_focus)
	_tree.add_theme_stylebox_override(&"cursor", StyleBoxEmpty.new())
	_tree.add_theme_stylebox_override(&"cursor_unfocused", StyleBoxEmpty.new())
	_tree.add_theme_color_override(&"font_color", t.font)
	_tree.add_theme_color_override(&"font_selected_color", t.font_strong)
	_tree.add_theme_color_override(&"guide_color", Color(0, 0, 0, 0))
	for b: Variant in _filter_btns.values():
		MermaidWorkbenchStyler.style_dock_tab(b as Button, t)
	if _rescan_btn != null:
		MermaidWorkbenchStyler.style_flat_button(_rescan_btn, t, t.font_dim, t.icon, Vector4(6, 2, 6, 2))
	if _count_lbl != null:
		_count_lbl.add_theme_color_override(&"font_color", t.font_faint)
	if _empty_lbl != null:
		_empty_lbl.add_theme_color_override(&"font_color", t.font_dim)
	if is_node_ready():
		_rebuild_tree()

#endregion


#region 界面构建与列表重建

func _build() -> void:
	if _tree != null:
		return
	var pad := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top"]:
		pad.add_theme_constant_override(StringName(side), 8)
	add_child(pad)

	var head := VBoxContainer.new()
	head.add_theme_constant_override(&"separation", 6)
	pad.add_child(head)

	_search = LineEdit.new()
	_search.placeholder_text = FlowEditorI18n.t(&"browser.search_placeholder")
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_query_changed)
	head.add_child(_search)

	_toolbar_box = HBoxContainer.new()
	head.add_child(_toolbar_box)
	var group := ButtonGroup.new()
	for spec: Array in [
		[FILTER_ALL, FlowEditorI18n.t(&"browser.filter_all")],
		[FILTER_FSM, FlowEditorI18n.t(&"browser.filter_fsm")],
		[FILTER_BT, FlowEditorI18n.t(&"browser.filter_bt")],
	]:
		var b := Button.new()
		b.text = str(spec[1])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = (spec[0] as StringName) == _filter
		var fid: StringName = spec[0] as StringName
		b.pressed.connect(func() -> void: set_filter(fid))
		_toolbar_box.add_child(b)
		_filter_btns[fid] = b

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar_box.add_child(spacer)

	_count_lbl = Label.new()
	_count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toolbar_box.add_child(_count_lbl)

	_rescan_btn = Button.new()
	_rescan_btn.text = FlowEditorI18n.t(&"browser.rescan")
	_rescan_btn.focus_mode = Control.FOCUS_NONE
	_rescan_btn.tooltip_text = FlowEditorI18n.t(&"browser.rescan_tip")
	_rescan_btn.pressed.connect(func() -> void: rescan_requested.emit())
	_toolbar_box.add_child(_rescan_btn)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 128)
	_tree.select_mode = Tree.SELECT_SINGLE
	_tree.item_selected.connect(_on_tree_item_selected)
	add_child(_tree)

	_empty_lbl = Label.new()
	_empty_lbl.text = FlowEditorI18n.t(&"browser.empty")
	_empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.visible = false
	add_child(_empty_lbl)


func apply_locale() -> void:
	if _search != null:
		_search.placeholder_text = FlowEditorI18n.t(&"browser.search_placeholder")
	if _filter_btns.has(FILTER_ALL):
		(_filter_btns[FILTER_ALL] as Button).text = FlowEditorI18n.t(&"browser.filter_all")
	if _filter_btns.has(FILTER_FSM):
		(_filter_btns[FILTER_FSM] as Button).text = FlowEditorI18n.t(&"browser.filter_fsm")
	if _filter_btns.has(FILTER_BT):
		(_filter_btns[FILTER_BT] as Button).text = FlowEditorI18n.t(&"browser.filter_bt")
	if _rescan_btn != null:
		_rescan_btn.text = FlowEditorI18n.t(&"browser.rescan")
		_rescan_btn.tooltip_text = FlowEditorI18n.t(&"browser.rescan_tip")
	if _empty_lbl != null:
		_empty_lbl.text = FlowEditorI18n.t(&"browser.empty")
	_marks_sig = ""
	if is_node_ready():
		_rebuild_tree()


func _filtered_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var q: String = _query.strip_edges()
	for e: Dictionary in _entries:
		var schema: StringName = e.get("schema", &"other") as StringName
		if _filter == FILTER_FSM and schema != &"fsm":
			continue
		if _filter == FILTER_BT and schema != &"bt":
			continue
		if not q.is_empty():
			var hay: String = "%s %s %s" % [str(e["file"]), str(e["dir"]), str(e["class"])]
			if hay.findn(q) < 0:
				continue
		out.append(e)
	return out


func _rebuild_tree() -> void:
	if _tree == null:
		return
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var shown: Array[Dictionary] = _filtered_entries()
	_count_lbl.text = "%d / %d" % [shown.size(), _entries.size()]
	_empty_lbl.visible = _entries.is_empty()
	_tree.visible = not _entries.is_empty()

	_suppress_select = true
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var dir_items: Dictionary = {}
	var to_select: TreeItem = null
	for e: Dictionary in shown:
		var path: String = str(e["path"])
		var dir_s: String = str(e["dir"])
		if not dir_items.has(dir_s):
			var d_item: TreeItem = _tree.create_item(root)
			d_item.set_text(0, dir_s.trim_prefix("res://") if dir_s != "res://" else "res://")
			d_item.set_custom_color(0, t.font_dim)
			d_item.set_selectable(0, false)
			d_item.set_selectable(1, false)
			dir_items[dir_s] = d_item
		var item: TreeItem = _tree.create_item(dir_items[dir_s] as TreeItem)
		item.set_text(0, str(e["file"]))
		item.set_metadata(0, path)
		item.set_tooltip_text(0, FlowEditorI18n.t(&"browser.item_tip", [path, str(e["class"])]))
		item.set_text(1, _status_text(e))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_custom_color(1, _status_color(e, t))
		item.set_selectable(1, false)
		if path == _active_path:
			item.set_custom_color(0, t.accent)
			to_select = item
	if to_select != null:
		to_select.select(0)
		_tree.scroll_to_item(to_select)
	_suppress_select = false


func _status_text(e: Dictionary) -> String:
	var path: String = str(e["path"])
	var parts: PackedStringArray = PackedStringArray()
	if _live_paths.has(path):
		parts.append(FlowEditorI18n.t(&"browser.status_live"))
	if _open_paths.has(path):
		var st: Variant = _open_paths[path]
		if st is String and str(st) == "conflict":
			parts.append(FlowEditorI18n.t(&"browser.status_conflict"))
		elif (st is String and str(st) == "dirty") or (st is bool and bool(st)):
			parts.append(FlowEditorI18n.t(&"browser.status_dirty"))
		else:
			parts.append(FlowEditorI18n.t(&"browser.status_open"))
	if parts.is_empty():
		var schema: StringName = e.get("schema", &"other") as StringName
		return FlowEditorI18n.t(&"browser.tag_fsm") if schema == &"fsm" else (FlowEditorI18n.t(&"browser.tag_bt") if schema == &"bt" else str(e["class"]))
	return " · ".join(parts)


func _status_color(e: Dictionary, t: MermaidThemeTokens) -> Color:
	var path: String = str(e["path"])
	if _open_paths.has(path):
		var st: Variant = _open_paths[path]
		if st is String and str(st) == "conflict":
			return t.error
		if (st is String and str(st) == "dirty") or (st is bool and bool(st)):
			return t.warning
	if _live_paths.has(path):
		return t.success
	if _open_paths.has(path):
		return t.accent
	return t.font_faint

#endregion


#region 交互回调

func _on_query_changed(text: String) -> void:
	_query = text
	_rebuild_tree()


func _on_tree_item_selected() -> void:
	if _suppress_select:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is String and not str(meta).is_empty():
		resource_open_requested.emit(str(meta))

#endregion
