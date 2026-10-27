@tool
extends PanelContainer

## 工作台上下文导航与 60 帧历史回放栏（Sub-Graph Breadcrumb & 60-Frame Scrubber Bar）。[br]
##
## 挂载在顶栏下方、画布上方；当既无子图下钻面包屑、也无多帧历史可回放时自动 `visible = false` 零空间占用：[br]
## - 左侧 P3 子图面包屑：`[← 返回上级]  parent.tres  ›  child.tres`，支持任意层级一键跳回；[br]
## - 右侧 P2 时间轴滑块：`[◀]` + `HSlider` + `帧 X / Y` + `[▶]` + `[● 回到实时]`，支持 `LIVE` 与停止后 `SNAPSHOT` 逐帧回溯。

const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const MermaidWorkbenchStyler = preload(FlowGraphContracts.SCRIPT_WORKBENCH_STYLER)

signal breadcrumb_selected(path: String, truncate_idx: int)
signal scrub_index_changed(scrub_idx: int)

## `Array[Dictionary]`: `{"path": String, "title": String}`
var breadcrumb_stack: Array[Dictionary] = []

var _s: float = 1.0
var _fs: int = 12
var _suppress_slider: bool = false
var _cur_total_frames: int = 0
var _cur_scrub_idx: int = -1

var _root_hbox: HBoxContainer = null
var _crumb_box: HBoxContainer = null
var _scrub_box: HBoxContainer = null
var _prev_btn: Button = null
var _slider: HSlider = null
var _frame_lbl: Label = null
var _next_btn: Button = null
var _live_btn: Button = null


#region 生命周期与内部控件装配

func _ready() -> void:
	_ensure_ui()
	apply_metrics(1.0, 14)
	visible = false


func _ensure_ui() -> void:
	if _root_hbox != null and is_instance_valid(_root_hbox):
		return
	_root_hbox = HBoxContainer.new()
	_root_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_root_hbox)

	_crumb_box = HBoxContainer.new()
	_crumb_box.visible = false
	_root_hbox.add_child(_crumb_box)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_hbox.add_child(spacer)

	_scrub_box = HBoxContainer.new()
	_scrub_box.visible = false
	_root_hbox.add_child(_scrub_box)

	_prev_btn = _make_bar_btn("◀", FlowEditorI18n.t(&"nav.prev_tip"))
	_prev_btn.pressed.connect(func() -> void: step_frame(-1))
	_scrub_box.add_child(_prev_btn)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 1.0
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(148.0, 20.0)
	_slider.value_changed.connect(_on_slider_value_changed)
	_scrub_box.add_child(_slider)

	_frame_lbl = Label.new()
	_frame_lbl.text = FlowEditorI18n.t(&"nav.frame_live", [0, 0])
	_frame_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scrub_box.add_child(_frame_lbl)

	_next_btn = _make_bar_btn("▶", FlowEditorI18n.t(&"nav.next_tip"))
	_next_btn.pressed.connect(func() -> void: step_frame(1))
	_scrub_box.add_child(_next_btn)

	_live_btn = _make_bar_btn(FlowEditorI18n.t(&"nav.return_live"), FlowEditorI18n.t(&"nav.return_tip"))
	_live_btn.pressed.connect(return_to_live)
	_scrub_box.add_child(_live_btn)

#endregion


#region P3 子图面包屑栈操作 API

func push_breadcrumb(parent_path: String, parent_title: String = "") -> void:
	var clean_p: String = parent_path.strip_edges()
	if clean_p.is_empty():
		return
	for i: int in range(breadcrumb_stack.size()):
		if str(breadcrumb_stack[i].get("path", "")) == clean_p:
			truncate_to(i)
			break
	breadcrumb_stack.append({
		"path": clean_p,
		"title": parent_title if not parent_title.is_empty() else clean_p.get_file(),
	})


func pop_breadcrumb() -> void:
	if breadcrumb_stack.is_empty():
		return
	var last_idx: int = breadcrumb_stack.size() - 1
	var target_path: String = str(breadcrumb_stack[last_idx].get("path", ""))
	breadcrumb_selected.emit(target_path, last_idx)


func truncate_to(idx: int) -> void:
	var keep: int = maxi(0, idx)
	while breadcrumb_stack.size() > keep:
		breadcrumb_stack.pop_back()


func clear_breadcrumbs() -> void:
	breadcrumb_stack.clear()


func get_breadcrumb_depth() -> int:
	return breadcrumb_stack.size()

#endregion


#region P2 60 帧时间轴回放控制 API

func select_frame(idx: int) -> void:
	if _cur_total_frames <= 0:
		return
	scrub_index_changed.emit(clampi(idx, 0, _cur_total_frames - 1))


func step_frame(delta: int) -> void:
	if _cur_total_frames <= 0:
		return
	var base_idx: int = _cur_scrub_idx if _cur_scrub_idx >= 0 else (_cur_total_frames - 1)
	var next_idx: int = clampi(base_idx + delta, 0, _cur_total_frames - 1)
	scrub_index_changed.emit(next_idx)


func return_to_live() -> void:
	scrub_index_changed.emit(-1)


func _on_slider_value_changed(val: float) -> void:
	if _suppress_slider or _cur_total_frames <= 0:
		return
	scrub_index_changed.emit(clampi(roundi(val), 0, _cur_total_frames - 1))

#endregion


#region 主题缩放与状态同步渲染

func apply_metrics(ui_scale: float, base_fs: int) -> void:
	_ensure_ui()
	_s = clampf(ui_scale, 0.75, 3.0)
	_fs = maxi(11, roundi(float(base_fs) * 0.88))
	var t: MermaidThemeTokens = MermaidThemeService.tokens()

	add_theme_stylebox_override("panel", MermaidThemeTokens.bar(t.dark1, t.dark3, SIDE_BOTTOM, Vector4(10.0 * _s, 4.0 * _s, 10.0 * _s, 4.0 * _s)))
	_root_hbox.add_theme_constant_override("separation", roundi(8.0 * _s))
	_crumb_box.add_theme_constant_override("separation", roundi(4.0 * _s))
	_scrub_box.add_theme_constant_override("separation", roundi(6.0 * _s))

	_slider.custom_minimum_size = Vector2(roundf(152.0 * _s), roundf(22.0 * _s))
	_frame_lbl.custom_minimum_size = Vector2(roundf(84.0 * _s), 0.0)
	_frame_lbl.add_theme_font_size_override("font_size", _fs)
	_frame_lbl.add_theme_color_override("font_color", t.font_dim)

	for btn: Button in [_prev_btn, _next_btn, _live_btn]:
		if btn != null:
			btn.custom_minimum_size = Vector2(0.0, roundf(24.0 * _s))
			btn.add_theme_font_size_override("font_size", _fs)
			MermaidWorkbenchStyler.style_flat_button(btn, t, t.accent if btn == _live_btn else t.font, t.icon, Vector4(6.0 * _s, 2.0 * _s, 6.0 * _s, 2.0 * _s))


func apply_locale(store: MermaidSessionStore) -> void:
	_ensure_ui()
	_prev_btn.tooltip_text = FlowEditorI18n.t(&"nav.prev_tip")
	_next_btn.tooltip_text = FlowEditorI18n.t(&"nav.next_tip")
	_live_btn.tooltip_text = FlowEditorI18n.t(&"nav.return_tip")
	sync_state(store)


func sync_state(store: MermaidSessionStore) -> void:
	_ensure_ui()
	var t: MermaidThemeTokens = MermaidThemeService.tokens()

	# 1. 左侧子图面包屑同步
	for ch: Node in _crumb_box.get_children():
		_crumb_box.remove_child(ch)
		ch.free()

	var show_crumbs: bool = not breadcrumb_stack.is_empty()
	_crumb_box.visible = show_crumbs
	if show_crumbs:
		var back_btn: Button = _make_bar_btn(FlowEditorI18n.t(&"nav.back"), FlowEditorI18n.t(&"nav.back_tip"))
		back_btn.add_theme_font_size_override("font_size", _fs)
		MermaidWorkbenchStyler.style_flat_button(back_btn, t, t.accent, t.accent, Vector4(6.0 * _s, 2.0 * _s, 6.0 * _s, 2.0 * _s))
		back_btn.pressed.connect(pop_breadcrumb)
		_crumb_box.add_child(back_btn)

		for i: int in range(breadcrumb_stack.size()):
			var entry: Dictionary = breadcrumb_stack[i]
			var p_str: String = str(entry.get("path", ""))
			var t_str: String = str(entry.get("title", p_str.get_file()))
			var cap_i: int = i
			var item_btn: Button = _make_bar_btn(t_str, p_str)
			item_btn.add_theme_font_size_override("font_size", _fs)
			MermaidWorkbenchStyler.style_flat_button(item_btn, t, t.font_dim, t.icon, Vector4(5.0 * _s, 2.0 * _s, 5.0 * _s, 2.0 * _s))
			item_btn.pressed.connect(func() -> void: breadcrumb_selected.emit(p_str, cap_i))
			_crumb_box.add_child(item_btn)

			var sep_lbl := Label.new()
			sep_lbl.text = "›"
			sep_lbl.add_theme_font_size_override("font_size", _fs)
			sep_lbl.add_theme_color_override("font_color", t.font_faint)
			_crumb_box.add_child(sep_lbl)

		var cur_name: String = _resolve_current_crumb_label(store)
		var cur_lbl := Label.new()
		cur_lbl.text = cur_name
		cur_lbl.add_theme_font_size_override("font_size", _fs)
		cur_lbl.add_theme_color_override("font_color", t.font_strong)
		_crumb_box.add_child(cur_lbl)

	# 2. 右侧 60 帧历史回放滑条同步
	var can_scrub_mode: bool = store != null and (store.is_live_selected() or store.is_snapshot_selected())
	_cur_total_frames = store.get_active_history_count() if can_scrub_mode else 0
	_cur_scrub_idx = store.scrub_index if store != null else -1
	var show_scrubber: bool = can_scrub_mode and _cur_total_frames >= 2
	_scrub_box.visible = show_scrubber

	if show_scrubber:
		var disp_idx: int = clampi(_cur_scrub_idx, 0, _cur_total_frames - 1) if _cur_scrub_idx >= 0 else (_cur_total_frames - 1)
		_suppress_slider = true
		_slider.min_value = 0.0
		_slider.max_value = float(maxi(1, _cur_total_frames - 1))
		_slider.value = float(disp_idx)
		_suppress_slider = false

		_prev_btn.disabled = (disp_idx <= 0)
		_next_btn.disabled = (disp_idx >= _cur_total_frames - 1)
		if _cur_scrub_idx >= 0:
			_frame_lbl.text = FlowEditorI18n.t(&"nav.frame_scrub", [disp_idx + 1, _cur_total_frames])
			_frame_lbl.add_theme_color_override("font_color", t.warning)
		else:
			_frame_lbl.text = FlowEditorI18n.t(&"nav.frame_live", [_cur_total_frames, _cur_total_frames])
			_frame_lbl.add_theme_color_override("font_color", t.font_dim)

		_live_btn.text = FlowEditorI18n.t(&"nav.return_live") if store.is_live_selected() else FlowEditorI18n.t(&"nav.return_last")
		_live_btn.disabled = (_cur_scrub_idx < 0)

	visible = show_crumbs or show_scrubber


static func _make_bar_btn(txt: String, tip: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.expand_icon = false
	return btn


static func _resolve_current_crumb_label(store: MermaidSessionStore) -> String:
	if store == null:
		return ""
	if store.is_resource_selected():
		return store.active_key.get_file()
	return str(store.get_active_graph().title) if store.get_active_graph() != null else ""

#endregion
