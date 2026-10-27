@tool
extends RefCounted

## Mermaid 工作台独立浮动窗口宿主管理（Standalone Floating Window Host）。[br]
##
## 实现与 Godot 原生 `Game` / `Script` 视口一致的「提取为独立系统窗口 <-> 嵌回编辑器主视口」无损热重挂载：[br]
## 1. 提取后工作台直接重挂载（`reparent`）至独立原生 `Window`（`transient = false`，支持任务栏独立图标、Alt-Tab、跨副屏最大化与可选置顶），运行态遥测脉冲与草稿状态 100% 零丢失；[br]
## 2. 浮动期间切换编辑器主视口至 `Game` / `3D` / `Script` 时，独立窗口保持常亮实时刷新，主视口内展示轻量引导占位页；[br]
## 3. 点击独立窗口右上角系统关闭按钮（`close_requested`）自动无缝嵌回编辑器主视口。

const MermaidWorkbench = preload(FlowGraphContracts.SCRIPT_WORKBENCH)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)

var _dock_parent: Control = null
var _window_owner: Node = null
var _workbench: MermaidWorkbench = null
var _floating_window: Window = null
var _placeholder: PanelContainer = null
var _ph_title_lbl: Label = null
var _ph_sub_lbl: Label = null
var _ph_focus_btn: Button = null
var _ph_dock_btn: Button = null

var _main_tab_visible: bool = false
var _always_on_top: bool = false
var _has_saved_rect: bool = false
var _saved_pos: Vector2i = Vector2i.ZERO
var _saved_size: Vector2i = Vector2i(1360, 820)


#region 初始化与销毁生命周期

func setup(dock_parent: Control, window_owner: Node, workbench: MermaidWorkbench) -> void:
	_dock_parent = dock_parent
	_window_owner = window_owner
	_workbench = workbench

	if _dock_parent != null and _workbench != null:
		_dock_parent.add_child(_workbench)
		_apply_full_rect_layout(_workbench)
		_workbench.visible = false

		_placeholder = _build_docked_placeholder()
		_placeholder.visible = false
		_dock_parent.add_child(_placeholder)

	if _workbench != null:
		_workbench.float_workbench_toggled.connect(set_floating)
		_workbench.float_topmost_toggled.connect(set_floating_always_on_top)
	FlowEditorI18n.subscribe(self, func(_loc: StringName) -> void: apply_locale())


func dispose() -> void:
	FlowEditorI18n.unsubscribe(self)
	if is_floating():
		set_floating(false)
	if _placeholder != null:
		_placeholder.queue_free()
		_placeholder = null
	_ph_title_lbl = null
	_ph_sub_lbl = null
	_ph_focus_btn = null
	_ph_dock_btn = null
	_workbench = null
	_dock_parent = null
	_window_owner = null


func apply_locale() -> void:
	if is_floating():
		_floating_window.title = FlowEditorI18n.t(&"float.win_title")
	if _ph_title_lbl != null:
		_ph_title_lbl.text = FlowEditorI18n.t(&"float.card_title")
	if _ph_sub_lbl != null:
		_ph_sub_lbl.text = FlowEditorI18n.t(&"float.card_sub")
	if _ph_focus_btn != null:
		_ph_focus_btn.text = FlowEditorI18n.t(&"float.btn_focus")
	if _ph_dock_btn != null:
		_ph_dock_btn.text = FlowEditorI18n.t(&"float.btn_dock")

#endregion


#region 公开浮动控制与可见性协调

func is_floating() -> bool:
	return _floating_window != null and is_instance_valid(_floating_window)


func on_main_screen_visibility_changed(visible: bool) -> void:
	_main_tab_visible = visible
	if is_floating():
		if _placeholder != null:
			_placeholder.visible = visible
		if _workbench != null:
			_workbench.visible = true
	else:
		if _placeholder != null:
			_placeholder.visible = false
		if _workbench != null:
			_workbench.visible = visible


func set_floating(enable: bool) -> void:
	if _workbench == null or _dock_parent == null or _window_owner == null:
		return
	if enable == is_floating():
		if enable:
			focus_floating_window()
		return

	if enable:
		_pop_out_to_window()
	else:
		_dock_back_to_main_screen()


func set_floating_always_on_top(enabled: bool) -> void:
	_always_on_top = enabled
	if is_floating():
		_floating_window.always_on_top = enabled


func focus_floating_window() -> void:
	if not is_floating():
		return
	if _floating_window.mode == Window.MODE_MINIMIZED:
		_floating_window.mode = Window.MODE_WINDOWED
	_floating_window.grab_focus()

#endregion


#region 内部热重挂载与占位面板构建

func _pop_out_to_window() -> void:
	var s: float = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	var win := Window.new()
	win.name = "FlowGraphFloatingWindow"
	win.title = FlowEditorI18n.t(&"float.win_title")
	if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		win.force_native = true
		win.gui_embed_subwindows = false
	win.transient = false
	win.exclusive = false
	win.min_size = Vector2i(roundi(860.0 * s), roundi(520.0 * s))
	win.always_on_top = _always_on_top

	if _window_owner is Control and (_window_owner as Control).theme != null:
		win.theme = (_window_owner as Control).theme

	if _has_saved_rect:
		win.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
		win.position = _saved_pos
		win.size = _saved_size
	else:
		win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
		var target_sz := Vector2i(roundi(float(_saved_size.x) * s), roundi(float(_saved_size.y) * s))
		var usable: Rect2i = DisplayServer.screen_get_usable_rect()
		if usable.size.x > 600 and usable.size.y > 400:
			target_sz.x = mini(target_sz.x, int(float(usable.size.x) * 0.85))
			target_sz.y = mini(target_sz.y, int(float(usable.size.y) * 0.85))
		win.size = target_sz

	win.close_requested.connect(_on_floating_window_close_requested)
	_window_owner.add_child(win)
	win.show()
	_floating_window = win

	_workbench.reparent(win, false)
	_apply_full_rect_layout(_workbench)
	_workbench.visible = true
	_workbench.set_floating_ui_state(true, _always_on_top)

	if _placeholder != null:
		_placeholder.visible = _main_tab_visible


func _dock_back_to_main_screen() -> void:
	if is_floating():
		if _floating_window.mode == Window.MODE_WINDOWED:
			_saved_pos = _floating_window.position
			_saved_size = _floating_window.size
			_has_saved_rect = true

	_workbench.reparent(_dock_parent, false)
	_apply_full_rect_layout(_workbench)
	_workbench.visible = _main_tab_visible
	_workbench.set_floating_ui_state(false, _always_on_top)

	if _placeholder != null:
		_placeholder.visible = false

	if _floating_window != null:
		_floating_window.queue_free()
		_floating_window = null


func _on_floating_window_close_requested() -> void:
	set_floating(false)


static func _apply_full_rect_layout(ctrl: Control) -> void:
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _build_docked_placeholder() -> PanelContainer:
	var s: float = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	var base_fs: int = roundi(14.0 * s)
	if Engine.is_editor_hint():
		var ed_theme: Theme = EditorInterface.get_editor_theme()
		if ed_theme != null and ed_theme.default_font_size > 0:
			base_fs = ed_theme.default_font_size

	var root_panel := PanelContainer.new()
	root_panel.name = "MermaidFloatingPlaceholder"
	_apply_full_rect_layout(root_panel)

	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = MermaidThemeService.tokens().dark2
	root_panel.add_theme_stylebox_override("panel", sb_bg)

	var center := CenterContainer.new()
	_apply_full_rect_layout(center)
	root_panel.add_child(center)

	var card := PanelContainer.new()
	var sb_card := StyleBoxFlat.new()
	sb_card.bg_color = MermaidThemeService.tokens().base
	sb_card.border_color = MermaidThemeService.tokens().dark3
	sb_card.set_border_width_all(maxi(1, roundi(1.0 * s)))
	sb_card.set_corner_radius_all(roundi(8.0 * s))
	sb_card.content_margin_left = roundf(28.0 * s)
	sb_card.content_margin_right = roundf(28.0 * s)
	sb_card.content_margin_top = roundf(24.0 * s)
	sb_card.content_margin_bottom = roundf(24.0 * s)
	card.add_theme_stylebox_override("panel", sb_card)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(10.0 * s))
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = FlowEditorI18n.t(&"float.card_title")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", roundi(float(base_fs) * 1.12))
	title_lbl.add_theme_color_override("font_color", MermaidThemeService.tokens().font_strong)
	vbox.add_child(title_lbl)
	_ph_title_lbl = title_lbl

	var sub_lbl := Label.new()
	sub_lbl.text = FlowEditorI18n.t(&"float.card_sub")
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", base_fs)
	sub_lbl.add_theme_color_override("font_color", MermaidThemeService.tokens().font_dim)
	vbox.add_child(sub_lbl)
	_ph_sub_lbl = sub_lbl

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, roundf(4.0 * s))
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", roundi(10.0 * s))
	vbox.add_child(btn_row)

	var focus_btn := Button.new()
	focus_btn.text = FlowEditorI18n.t(&"float.btn_focus")
	focus_btn.custom_minimum_size = Vector2(roundf(132.0 * s), roundf(32.0 * s))
	focus_btn.add_theme_font_size_override("font_size", base_fs)
	focus_btn.pressed.connect(focus_floating_window)
	btn_row.add_child(focus_btn)
	_ph_focus_btn = focus_btn

	var dock_btn := Button.new()
	dock_btn.text = FlowEditorI18n.t(&"float.btn_dock")
	dock_btn.custom_minimum_size = Vector2(roundf(148.0 * s), roundf(32.0 * s))
	dock_btn.add_theme_font_size_override("font_size", base_fs)
	dock_btn.pressed.connect(func() -> void: set_floating(false))
	btn_row.add_child(dock_btn)
	_ph_dock_btn = dock_btn

	return root_panel

#endregion
