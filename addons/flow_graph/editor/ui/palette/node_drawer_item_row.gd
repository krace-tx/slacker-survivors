@tool
extends Button

## 左侧节点库抽屉单条目按钮（Node Drawer Interactive Item Row）。[br]
##
## 采用内部弹性双栏布局（`图标 + 自适应省略标题 + 右对齐紧凑标签`），杜绝多语言长词条重叠或越界溢出；同时支持 **单击快速追加** 与 **原生拖拽至画布/节点/连线放置**。

const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

signal item_activated(kind: String, preset: String)

var node_kind: String = "State"
var node_preset: String = ""
var item_title: String = ""
var item_tag: String = ""
var item_color: Color = Color.WHITE
var item_icon: Texture2D = null
var ui_scale: float = 1.0

var _margin: MarginContainer = null
var _hbox: HBoxContainer = null
var _icon_rect: TextureRect = null
var _title_lbl: Label = null
var _tag_pill: PanelContainer = null
var _tag_lbl: Label = null
var _hovered: bool = false


func configure(item_spec: Dictionary, scale_val: float, base_fs: int, read_only: bool) -> void:
	node_kind = str(item_spec.get("kind", "State"))
	node_preset = str(item_spec.get("preset", ""))
	item_title = str(item_spec.get("title", node_kind))
	item_tag = str(item_spec.get("tag", ""))
	item_color = item_spec.get("color", Color.WHITE) as Color
	item_icon = item_spec.get("icon", null) as Texture2D
	ui_scale = clampf(scale_val, 0.75, 3.0)

	text = ""
	icon = null
	focus_mode = Control.FOCUS_NONE
	disabled = read_only
	mouse_default_cursor_shape = Control.CURSOR_ARROW if read_only else Control.CURSOR_POINTING_HAND
	tooltip_text = FlowEditorI18n.t(&"drawer.hint_readonly") if read_only else str(item_spec.get("tooltip", item_title))

	_ensure_inner_layout()
	_icon_rect.visible = (item_icon != null)
	_icon_rect.texture = item_icon
	_title_lbl.text = item_title
	_tag_pill.visible = not item_tag.is_empty()
	_tag_lbl.text = item_tag

	if not pressed.is_connected(_on_row_pressed):
		pressed.connect(_on_row_pressed)
	if not mouse_entered.is_connected(_on_hover_entered):
		mouse_entered.connect(_on_hover_entered)
	if not mouse_exited.is_connected(_on_hover_exited):
		mouse_exited.connect(_on_hover_exited)

	apply_visuals(ui_scale, base_fs)


func _ensure_inner_layout() -> void:
	if _margin != null:
		return
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	_hbox = HBoxContainer.new()
	_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_hbox)

	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hbox.add_child(_icon_rect)

	_title_lbl = Label.new()
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hbox.add_child(_title_lbl)

	_tag_pill = PanelContainer.new()
	_tag_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	_tag_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tag_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hbox.add_child(_tag_pill)

	_tag_lbl = Label.new()
	_tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_pill.add_child(_tag_lbl)


func apply_visuals(scale_val: float, base_fs: int) -> void:
	ui_scale = clampf(scale_val, 0.75, 3.0)
	_ensure_inner_layout()
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var row_fs: int = maxi(12, roundi(float(base_fs) * 0.93))
	var tag_fs: int = maxi(10, roundi(float(base_fs) * 0.75))
	var r_sm: int = maxi(3, roundi(4.0 * ui_scale))
	var ico_px: float = roundf(15.0 * ui_scale)

	custom_minimum_size = Vector2(0.0, roundf(29.0 * ui_scale))
	_margin.add_theme_constant_override(&"margin_left", roundi(8.0 * ui_scale))
	_margin.add_theme_constant_override(&"margin_right", roundi(7.0 * ui_scale))
	_margin.add_theme_constant_override(&"margin_top", roundi(2.0 * ui_scale))
	_margin.add_theme_constant_override(&"margin_bottom", roundi(2.0 * ui_scale))
	_hbox.add_theme_constant_override(&"separation", roundi(6.0 * ui_scale))
	_icon_rect.custom_minimum_size = Vector2(ico_px, ico_px)

	var sb_idle: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(t.dark1, 0.42), Color(t.border, 0.25), 1, r_sm)
	var sb_hover: StyleBoxFlat = CanvasThemePalette.make_flat_sb(t.surface.lerp(item_color, 0.12), Color(item_color, 0.62), 1, r_sm)
	var sb_press: StyleBoxFlat = CanvasThemePalette.make_flat_sb(t.surface.lerp(item_color, 0.20), Color(item_color, 0.85), 1, r_sm)
	var sb_dis: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(t.dark1, 0.20), Color(0, 0, 0, 0), 0, r_sm)

	add_theme_stylebox_override(&"normal", sb_idle)
	add_theme_stylebox_override(&"hover", sb_hover)
	add_theme_stylebox_override(&"pressed", sb_press)
	add_theme_stylebox_override(&"disabled", sb_dis)
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())

	_title_lbl.add_theme_font_size_override(&"font_size", row_fs)
	_tag_lbl.add_theme_font_size_override(&"font_size", tag_fs)

	var sb_tag: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(t.dark2, 0.55), Color(0, 0, 0, 0), 0, maxi(2, roundi(3.0 * ui_scale)))
	sb_tag.content_margin_left = roundf(5.0 * ui_scale)
	sb_tag.content_margin_right = roundf(5.0 * ui_scale)
	sb_tag.content_margin_top = roundf(1.0 * ui_scale)
	sb_tag.content_margin_bottom = roundf(1.0 * ui_scale)
	_tag_pill.add_theme_stylebox_override(&"panel", sb_tag)

	_refresh_foreground_colors()


func _refresh_foreground_colors() -> void:
	if _title_lbl == null:
		return
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	if disabled:
		_title_lbl.add_theme_color_override(&"font_color", Color(t.font, 0.35))
		_icon_rect.modulate = Color(item_color, 0.32)
		_tag_lbl.add_theme_color_override(&"font_color", Color(t.font_faint, 0.40))
		return
	var is_hi: bool = _hovered and not disabled
	_title_lbl.add_theme_color_override(&"font_color", t.font_strong if is_hi else t.font)
	_icon_rect.modulate = item_color.lightened(0.16) if is_hi else item_color
	_tag_lbl.add_theme_color_override(&"font_color", Color(t.font_dim if is_hi else t.font_faint, 0.90))


func _on_hover_entered() -> void:
	_hovered = true
	_refresh_foreground_colors()


func _on_hover_exited() -> void:
	_hovered = false
	_refresh_foreground_colors()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled:
		return null
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var preview := PanelContainer.new()
	var sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(Color(t.surface, 0.96), Color(item_color, 0.88), 2, maxi(4, roundi(5.0 * ui_scale)))
	sb.content_margin_left = roundf(10.0 * ui_scale)
	sb.content_margin_right = roundf(12.0 * ui_scale)
	sb.content_margin_top = roundf(6.0 * ui_scale)
	sb.content_margin_bottom = roundf(6.0 * ui_scale)
	preview.add_theme_stylebox_override(&"panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", roundi(6.0 * ui_scale))
	preview.add_child(hb)
	if item_icon != null:
		var tr := TextureRect.new()
		tr.texture = item_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(roundf(15.0 * ui_scale), roundf(15.0 * ui_scale))
		tr.modulate = item_color
		hb.add_child(tr)
	var lb := Label.new()
	lb.text = item_title
	lb.add_theme_font_size_override(&"font_size", maxi(12, roundi(12.5 * ui_scale)))
	lb.add_theme_color_override(&"font_color", t.font_strong)
	hb.add_child(lb)
	set_drag_preview(preview)

	return {
		"flow_graph_palette_item": true,
		"kind": node_kind,
		"preset": node_preset,
		"title": item_title,
	}


func _on_row_pressed() -> void:
	if not disabled:
		item_activated.emit(node_kind, node_preset)
