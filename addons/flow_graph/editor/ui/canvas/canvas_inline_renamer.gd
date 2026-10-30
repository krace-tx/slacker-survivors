@tool
extends RefCounted

## 画布节点卡片原位标题重命名浮层（Canvas Inline Node Title Renamer）。[br]
##
## 双击节点、按下 `F2` 或新建状态后直接贴合节点屏幕矩形浮出无干扰 `LineEdit`，支持 `Enter` / 失焦提交与 `Esc` 放弃。

const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

signal rename_committed(node_id: String, new_title: String)

var _host_canvas: Control = null
var _edit: LineEdit = null
var _editing_node_id: String = ""
var _initial_title: String = ""
var _world_rect: Rect2 = Rect2()
var _closing: bool = false


func setup(host_canvas: Control) -> void:
	if host_canvas == null or _edit != null:
		return
	_host_canvas = host_canvas
	_edit = LineEdit.new()
	_edit.name = "CanvasInlineRenameEdit"
	_edit.visible = false
	_edit.select_all_on_focus = true
	_edit.text_submitted.connect(_on_text_submitted)
	_edit.focus_exited.connect(_on_focus_exited)
	_edit.gui_input.connect(_on_edit_gui_input)
	host_canvas.add_child(_edit)


func is_active() -> bool:
	return _edit != null and _edit.visible and not _editing_node_id.is_empty()


func get_editing_node_id() -> String:
	return _editing_node_id if is_active() else ""


func open_for_node(
	node_id: String,
	current_title: String,
	world_rect: Rect2,
	zoom: float,
	scroll_offset: Vector2,
	ui_scale: float = 1.0
) -> void:
	if _edit == null or node_id.is_empty():
		return
	if is_active() and _editing_node_id != node_id:
		commit_and_close()

	_closing = false
	_editing_node_id = node_id
	_initial_title = current_title
	_world_rect = world_rect
	_apply_style(zoom, ui_scale)
	sync_transform(world_rect, zoom, scroll_offset)

	_edit.placeholder_text = FlowEditorI18n.t(&"canvas.rename_placeholder")
	_edit.text = current_title
	_edit.visible = true
	_edit.grab_focus()
	_edit.select_all()
	_edit.caret_column = _edit.text.length()


func sync_transform(world_rect: Rect2, zoom: float, scroll_offset: Vector2) -> void:
	if not is_active():
		return
	_world_rect = world_rect
	var z: float = maxf(zoom, 0.25)
	var s_pos: Vector2 = world_rect.position * z - scroll_offset
	var s_size: Vector2 = world_rect.size * z
	var pad_x: float = roundf(6.0 * z)
	var pad_y: float = roundf(3.0 * z)
	_edit.position = Vector2(s_pos.x + pad_x, s_pos.y + pad_y)
	_edit.size = Vector2(maxf(96.0, s_size.x - pad_x * 2.0), maxf(22.0, s_size.y - pad_y * 2.0))


func commit_and_close() -> void:
	if _closing or _edit == null or not _edit.visible:
		return
	_closing = true
	var target_id: String = _editing_node_id
	var base_title: String = _initial_title
	var next_title: String = _edit.text.strip_edges()
	_editing_node_id = ""
	_edit.visible = false
	if _host_canvas != null and _host_canvas.is_inside_tree():
		_host_canvas.grab_focus()
	_closing = false
	if not target_id.is_empty() and not next_title.is_empty() and next_title != base_title:
		rename_committed.emit(target_id, next_title)


func cancel_and_close() -> void:
	if _closing or _edit == null or not _edit.visible:
		return
	_closing = true
	_editing_node_id = ""
	_edit.visible = false
	if _host_canvas != null and _host_canvas.is_inside_tree():
		_host_canvas.grab_focus()
	_closing = false


func _apply_style(zoom: float, ui_scale: float) -> void:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var fsize: int = clampi(roundi(12.5 * maxf(zoom, 0.75 * ui_scale)), 11, 24)
	var sb: StyleBoxFlat = CanvasThemePalette.make_flat_sb(t.dark1, t.accent, 2, 5)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	_edit.add_theme_font_size_override("font_size", fsize)
	_edit.add_theme_stylebox_override("normal", sb)
	_edit.add_theme_stylebox_override("focus", sb)
	_edit.add_theme_color_override("font_color", t.font_strong)
	_edit.add_theme_color_override("font_placeholder_color", t.font_faint)


func _on_text_submitted(_txt: String) -> void:
	commit_and_close()


func _on_focus_exited() -> void:
	commit_and_close()


func _on_edit_gui_input(event: InputEvent) -> void:
	if FlowEditorInput.resolve_modal_action(event, false) == FlowEditorInput.MODAL_CANCEL:
		_edit.accept_event()
		cancel_and_close()
