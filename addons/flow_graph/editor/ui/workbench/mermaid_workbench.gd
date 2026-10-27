@tool
extends VBoxContainer

## Mermaid Godot 顶部主视口大画布工作台薄协调器（Workbench Thin Coordinator）。[br]
##
## 编排顶栏控件、资源直编（打开/保存/热重载 `.tres`）、源码双向同步与子图面包屑；职责委派至 [`WorkbenchMutationController`](workbench_mutation_controller.gd)、[`WorkbenchDebugSessionController`](workbench_debug_session_controller.gd)、[`WorkbenchNavScrubberBar`](workbench_nav_scrubber_bar.gd)、[`WorkbenchDpiScaler`](workbench_dpi_scaler.gd) 与 [`WorkbenchChromeController`](workbench_chrome_controller.gd)。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const MermaidResourceCatalog = preload(FlowGraphContracts.SCRIPT_RESOURCE_CATALOG)
const FlowUndoStack = preload(FlowGraphContracts.SCRIPT_UNDO_STACK)
const MermaidGraphCanvas = preload(FlowGraphContracts.SCRIPT_CANVAS)
const MermaidSyntaxHighlighter = preload(FlowGraphContracts.SCRIPT_SYNTAX_HIGHLIGHTER)
const MermaidInspectorPanel = preload(FlowGraphContracts.SCRIPT_INSPECTOR_PANEL)
const MermaidResourceBrowser = preload(FlowGraphContracts.SCRIPT_RESOURCE_BROWSER)
const WorkbenchNavScrubberBar = preload(FlowGraphContracts.SCRIPT_WB_NAV_BAR)
const WorkbenchMutationController = preload(FlowGraphContracts.SCRIPT_WB_MUTATION_CTRL)
const WorkbenchDebugSessionController = preload(FlowGraphContracts.SCRIPT_WB_DEBUG_CTRL)
const WorkbenchDpiScaler = preload(FlowGraphContracts.SCRIPT_WB_DPI_SCALER)
const WorkbenchChromeController = preload(FlowGraphContracts.SCRIPT_WB_CHROME_CTRL)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

const IconStatusOffline: Texture2D = FlowGraphIcons.STATUS_OFFLINE
const IconStatusLive: Texture2D = FlowGraphIcons.STATUS_LIVE
const IconCodeDsl: Texture2D = FlowGraphIcons.TB_CODE_DSL

const DOCK_TAB_INSPECTOR: int = 0
const DOCK_TAB_RESOURCES: int = 1
const DOCK_TAB_SOURCE: int = 2

signal standalone_window_toggled(enabled: bool)
signal float_workbench_toggled(enabled: bool)
signal float_topmost_toggled(enabled: bool)

@onready var _instance_select: OptionButton = %InstanceSelect as OptionButton
@onready var _open_res_btn: Button = %OpenResBtn as Button
@onready var _save_res_btn: Button = %SaveResBtn as Button
@onready var _undo_btn: Button = %UndoBtn as Button
@onready var _redo_btn: Button = %RedoBtn as Button
@onready var _transport_box: HBoxContainer = %TransportBox as HBoxContainer
@onready var _pause_btn: Button = %PauseBtn as Button
@onready var _step_btn: Button = %StepBtn as Button
@onready var _dir_toggle_btn: Button = %DirToggleBtn as Button
@onready var _auto_layout_btn: Button = %AutoLayoutBtn as Button
@onready var _snap_toggle_btn: Button = %SnapToggleBtn as Button
@onready var _labels_toggle_btn: Button = %LabelsToggleBtn as Button
@onready var _minimap_toggle_btn: Button = %MinimapToggleBtn as Button
@onready var _lang_toggle_btn: Button = %LangToggleBtn as Button
@onready var _window_menu_btn: MenuButton = %WindowMenuBtn as MenuButton
@onready var _toggle_sidebar_btn: Button = %ToggleSidebarBtn as Button
@onready var _graph_canvas: MermaidGraphCanvas = %GraphCanvas as MermaidGraphCanvas
@onready var _zoom_out_btn: Button = %ZoomOutBtn as Button
@onready var _zoom_reset_btn: Button = %ZoomResetBtn as Button
@onready var _zoom_in_btn: Button = %ZoomInBtn as Button
@onready var _fit_view_btn: Button = %FitViewBtn as Button
@onready var _right_sidebar: Control = %RightSidebar as Control
@onready var _tab_telemetry_btn: Button = %TabTelemetryBtn as Button
@onready var _tab_resources_btn: Button = %TabResourcesBtn as Button
@onready var _tab_source_btn: Button = %TabSourceBtn as Button
@onready var _mode_badge_label: Label = %ModeBadgeLabel as Label
@onready var _telemetry_page: Control = %TelemetryPage as Control
@onready var _inspector_panel: MermaidInspectorPanel = %InspectorPanel as MermaidInspectorPanel
@onready var _resources_page: Control = %ResourcesPage as Control
@onready var _resource_browser: MermaidResourceBrowser = %ResourceBrowser as MermaidResourceBrowser
@onready var _source_page: Control = %SourcePage as Control
@onready var _parse_hint_bar: PanelContainer = %ParseHintBar as PanelContainer
@onready var _parse_hint_label: Label = %ParseHintLabel as Label
@onready var _code_editor: CodeEdit = %CodeEditor as CodeEdit

var _store: MermaidSessionStore = MermaidSessionStore.new()
var _catalog: MermaidResourceCatalog = MermaidResourceCatalog.new()
var _undo_stack: FlowUndoStack = FlowUndoStack.new()
var _mutations: WorkbenchMutationController = WorkbenchMutationController.new()
var _debug_ctrl: WorkbenchDebugSessionController = WorkbenchDebugSessionController.new()
var _dpi: WorkbenchDpiScaler = WorkbenchDpiScaler.new()
var _chrome: WorkbenchChromeController = WorkbenchChromeController.new()
var _nav_bar: WorkbenchNavScrubberBar = null
var _debugger: RefCounted = null
var _suppress_code_signal: bool = false
var _code_debounce_timer: Timer = null
var _active_dock_tab: int = DOCK_TAB_INSPECTOR


#region 生命周期、快捷键与外围壳层绑定

func _ready() -> void:
	_nav_bar = WorkbenchNavScrubberBar.new()
	_nav_bar.name = "NavScrubberBar"
	add_child(_nav_bar)
	move_child(_nav_bar, 1)
	_nav_bar.breadcrumb_selected.connect(_on_breadcrumb_selected)
	_nav_bar.scrub_index_changed.connect(_debug_ctrl.on_scrub_index_changed)

	_mutations.setup(_store, _undo_stack, _graph_canvas, _inspector_panel)
	_mutations.view_sync_requested.connect(_on_mutation_view_sync)
	_mutations.parse_hint_changed.connect(_set_parse_hint)
	_mutations.breakpoint_changed.connect(_debug_ctrl.sync_breakpoint)

	_debug_ctrl.setup(_store, _graph_canvas, _inspector_panel, _nav_bar, _pause_btn)
	_debug_ctrl.dropdown_rebuild_requested.connect(_rebuild_instance_dropdown)
	_debug_ctrl.dock_tab_switch_requested.connect(_switch_dock_tab)
	_debug_ctrl.render_requested.connect(func(fit_v: bool) -> void:
		_render_active_graph()
		if fit_v and _graph_canvas != null:
			_graph_canvas.fit_graph_view()
	)

	_chrome.setup(self, _window_menu_btn)
	_chrome.standalone_window_toggled.connect(func(on: bool) -> void: standalone_window_toggled.emit(on))
	_chrome.float_workbench_toggled.connect(func(on: bool) -> void: float_workbench_toggled.emit(on))
	_chrome.float_topmost_toggled.connect(func(on: bool) -> void: float_topmost_toggled.emit(on))
	_chrome.dialog_open_selected.connect(func(p: String) -> void: open_resource_at_path(p, true))
	_chrome.dialog_save_selected.connect(_on_dialog_save_selected)
	_chrome.external_check_triggered.connect(_check_external_file_changes)

	if _code_editor != null:
		_code_editor.syntax_highlighter = MermaidSyntaxHighlighter.create()
	_code_debounce_timer = Timer.new()
	_code_debounce_timer.one_shot = true
	_code_debounce_timer.wait_time = 0.26
	_code_debounce_timer.timeout.connect(func() -> void: _mutations.apply_code_text(_code_editor.text))
	add_child(_code_debounce_timer)

	_instance_select.item_selected.connect(_on_instance_selected)
	_open_res_btn.pressed.connect(func() -> void: _chrome.popup_open_dialog())
	_save_res_btn.pressed.connect(_on_save_res_pressed)
	if _undo_btn != null: _undo_btn.pressed.connect(func() -> void: _mutations.undo())
	if _redo_btn != null: _redo_btn.pressed.connect(func() -> void: _mutations.redo())
	_pause_btn.toggled.connect(_debug_ctrl.send_pause)
	_step_btn.pressed.connect(_debug_ctrl.send_step)
	_dir_toggle_btn.pressed.connect(_on_dir_toggle_pressed)
	_auto_layout_btn.pressed.connect(func() -> void: _mutations.auto_layout())
	_snap_toggle_btn.toggled.connect(func(on: bool) -> void: _graph_canvas.snapping_enabled = on)
	_labels_toggle_btn.toggled.connect(func(on: bool) -> void: _graph_canvas.show_all_labels = on)
	_minimap_toggle_btn.toggled.connect(func(on: bool) -> void: _graph_canvas.minimap_enabled = on)
	if _lang_toggle_btn != null:
		_lang_toggle_btn.pressed.connect(func() -> void: toggle_editor_locale())
	_toggle_sidebar_btn.toggled.connect(func(show_bar: bool) -> void: _right_sidebar.visible = show_bar)

	_zoom_out_btn.pressed.connect(func() -> void: _graph_canvas.zoom_step(1.0 / 1.18))
	_zoom_in_btn.pressed.connect(func() -> void: _graph_canvas.zoom_step(1.18))
	_zoom_reset_btn.pressed.connect(func() -> void: _graph_canvas.reset_zoom_100())
	_fit_view_btn.pressed.connect(func() -> void:
		_graph_canvas.fit_graph_view()
		_refresh_zoom_label()
	)
	_tab_telemetry_btn.pressed.connect(func() -> void: _switch_dock_tab(DOCK_TAB_INSPECTOR))
	if _tab_resources_btn != null: _tab_resources_btn.pressed.connect(func() -> void: _switch_dock_tab(DOCK_TAB_RESOURCES))
	_tab_source_btn.pressed.connect(func() -> void: _switch_dock_tab(DOCK_TAB_SOURCE))

	if _inspector_panel != null:
		_inspector_panel.node_selected_from_inspector.connect(_on_inspector_node_selected)
		_inspector_panel.jump_code_requested.connect(WorkbenchChromeController.jump_to_script)
		_inspector_panel.force_node_requested.connect(_debug_ctrl.send_force_node)
		_inspector_panel.switch_to_resource_requested.connect(_on_inspector_switch_to_resource)
		_inspector_panel.switch_to_live_requested.connect(_on_inspector_switch_to_live)
		_inspector_panel.resolve_external_conflict_requested.connect(_on_resolve_external_conflict)
		_inspector_panel.live_var_edit_requested.connect(_debug_ctrl.send_set_var)
		_inspector_panel.live_fire_event_requested.connect(_debug_ctrl.send_fire_event)
		_inspector_panel.sub_graph_open_requested.connect(_on_sub_graph_open_requested)

	if _resource_browser != null:
		_resource_browser.resource_open_requested.connect(func(p: String) -> void: open_resource_at_path(p, false, false))
		_resource_browser.rescan_requested.connect(_on_browser_rescan_requested)

	_code_editor.text_changed.connect(_on_code_text_changed)
	_graph_canvas.node_force_requested.connect(_debug_ctrl.send_force_node)
	_graph_canvas.node_inspected.connect(func(nid: String) -> void: _refresh_inspector_panel(nid))
	_graph_canvas.sub_graph_open_requested.connect(func(sp: String, _nid: String) -> void: _on_sub_graph_open_requested(sp))
	_graph_canvas.view_zoom_changed.connect(func(_z: float) -> void: _refresh_zoom_label())

	_catalog.catalog_changed.connect(_on_catalog_changed)
	_catalog.setup()
	_dpi.setup(self, func() -> void:
		_refresh_inspector_panel(_graph_canvas.get_selected_node_id() if _graph_canvas != null else "")
		_refresh_zoom_label()
	)
	FlowEditorI18n.subscribe(self, func(_loc: StringName) -> void: _on_locale_changed())
	_chrome.apply_locale()
	_dpi.apply_theme()
	_dpi.apply_dpi_scale(_nav_bar)
	_sync_resource_browser_entries()
	_rebuild_instance_dropdown()
	_switch_dock_tab(DOCK_TAB_RESOURCES if not _catalog.entries.is_empty() else DOCK_TAB_INSPECTOR)
	_render_active_graph()

func _exit_tree() -> void:
	FlowEditorI18n.unsubscribe(self)
	_chrome.dispose()
	if _catalog != null: _catalog.dispose()

func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey): return
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or ke.echo or not ke.is_command_or_control_pressed(): return
	if ke.keycode == KEY_S and not ke.shift_pressed:
		_on_save_res_pressed()
		accept_event()
		return
	var f_owner: Control = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if f_owner is LineEdit or f_owner is CodeEdit: return
	if ke.keycode == KEY_Z and not ke.shift_pressed and _mutations.undo(): accept_event()
	elif (ke.keycode == KEY_Y or (ke.keycode == KEY_Z and ke.shift_pressed)) and _mutations.redo(): accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		if MermaidThemeService.refresh(): _dpi.reapply_all()
		elif _dpi.apply_dpi_scale(_nav_bar):
			_refresh_inspector_panel(_graph_canvas.get_selected_node_id() if _graph_canvas != null else "")
			_refresh_zoom_label()
	elif (what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN) and is_node_ready():
		_chrome.queue_external_check(false)

func apply_ui_scale_override(scale_val: float) -> void:
	_dpi.set_scale_override(scale_val)
	if _nav_bar != null and is_node_ready(): _dpi.apply_dpi_scale(_nav_bar)

func set_editor_locale(locale: StringName, persist: bool = true) -> void:
	FlowEditorI18n.set_locale(locale, persist)

func toggle_editor_locale(persist: bool = true) -> StringName:
	return FlowEditorI18n.toggle_locale(persist)

func _on_locale_changed() -> void:
	if not is_node_ready(): return
	_chrome.apply_locale()
	if _nav_bar != null: _nav_bar.apply_locale(_store)
	if _resource_browser != null: _resource_browser.apply_locale()
	if _graph_canvas != null: _graph_canvas.apply_locale()
	_sync_resource_browser_entries()
	_rebuild_instance_dropdown()
	_render_active_graph()

#endregion


#region 公开门面、资源直编、保存热重载与冲突决议

func bind_debugger(debugger_plugin: RefCounted) -> void:
	_debugger = debugger_plugin
	_debug_ctrl.bind_debugger(debugger_plugin, _on_session_active_changed)

func set_standalone_check_state(enabled: bool) -> void:
	_chrome.standalone_enabled = enabled
	_chrome.rebuild_window_menu_items()

func set_floating_ui_state(is_floating: bool, float_topmost: bool) -> void:
	_chrome.is_floating_window = is_floating
	_chrome.float_topmost_enabled = float_topmost
	_chrome.rebuild_window_menu_items()

func _on_window_menu_id_pressed(id: int) -> void:
	_chrome.on_window_menu_id_pressed(id, _debugger)

func open_resource(res: Resource) -> void:
	if _store.open_resource_session(res).is_empty(): return
	if _nav_bar != null: _nav_bar.clear_breadcrumbs()
	_set_parse_hint("")
	_rebuild_instance_dropdown()
	_switch_dock_tab(DOCK_TAB_INSPECTOR)
	_render_active_graph()
	if _graph_canvas != null and not _store.get_active_graph().nodes.is_empty(): _graph_canvas.fit_graph_view()

func open_resource_at_path(path: String, switch_to_inspector: bool = false, preserve_breadcrumbs: bool = false) -> bool:
	var res: Dictionary = _store.open_or_focus_resource_path(path)
	if not bool(res.get("ok", false)):
		_set_parse_hint(str(res.get("error", "")))
		_switch_dock_tab(DOCK_TAB_SOURCE)
		return false
	if not preserve_breadcrumbs and _nav_bar != null: _nav_bar.clear_breadcrumbs()
	_set_parse_hint("")
	_rebuild_instance_dropdown()
	if switch_to_inspector: _switch_dock_tab(DOCK_TAB_INSPECTOR)
	_render_active_graph()
	if not bool(res.get("reused", false)) and _graph_canvas != null and not _store.get_active_graph().nodes.is_empty(): _graph_canvas.fit_graph_view()
	return true

func load_mermaid_text(source: String) -> void:
	var res: Dictionary = _store.apply_draft_source(source)
	if not bool(res.get("ok", false)):
		_set_parse_hint(FlowEditorI18n.t(&"dock.syntax_hint", [str(res.get("error", ""))]))
		return
	if _nav_bar != null: _nav_bar.clear_breadcrumbs()
	_set_parse_hint("")
	_rebuild_instance_dropdown()
	_render_active_graph()
	if _graph_canvas != null and not _store.draft_graph.nodes.is_empty(): _graph_canvas.fit_graph_view()

func save_active_resource(target_path: String = "") -> Dictionary:
	var save_res: Dictionary = _store.save_or_export_active(target_path)
	if bool(save_res.get("ok", false)):
		var saved_path: String = str(save_res.get("path", ""))
		_set_parse_hint("")
		_catalog.request_rescan()
		_rebuild_instance_dropdown()
		_update_save_btn_visual()
		_refresh_inspector_panel(_graph_canvas.get_selected_node_id() if _graph_canvas != null else "")
		_debug_ctrl.notify_hot_reload_if_running(saved_path)
	return save_res

func _on_save_res_pressed() -> void:
	if _store.is_resource_selected():
		var existing_path: String = str(_store.get_active_record().get("path", ""))
		if not existing_path.is_empty():
			var save_res: Dictionary = save_active_resource(existing_path)
			if not bool(save_res.get("ok", false)):
				_set_parse_hint(str(save_res.get("error", "")))
				_switch_dock_tab(DOCK_TAB_SOURCE)
			return
	var active_g: MermaidGraphModel = _store.get_active_graph()
	if active_g == null or active_g.nodes.is_empty():
		_set_parse_hint(FlowEditorI18n.t(&"dock.export_empty_err"))
		_switch_dock_tab(DOCK_TAB_SOURCE)
		return
	_chrome.popup_export_dialog(active_g)

func _on_dialog_save_selected(path: String) -> void:
	var exp_res: Dictionary = save_active_resource(path)
	if not bool(exp_res.get("ok", false)):
		_set_parse_hint(str(exp_res.get("error", "")))
		_switch_dock_tab(DOCK_TAB_SOURCE)
		return
	_switch_dock_tab(DOCK_TAB_INSPECTOR)
	_render_active_graph()

func _check_external_file_changes(force_content_check: bool = true) -> void:
	var diff: Dictionary = _store.check_external_resource_changes(force_content_check)
	var reloaded: Array = diff.get("reloaded", []) as Array
	var conflicts: Array = diff.get("conflicts", []) as Array
	if reloaded.is_empty() and conflicts.is_empty(): return
	_rebuild_instance_dropdown()
	_update_save_btn_visual()
	var active_path: String = _store.active_key if _store.is_resource_selected() else ""
	if not active_path.is_empty() and (reloaded.has(active_path) or conflicts.has(active_path)):
		_render_active_graph()
		if conflicts.has(active_path) and _active_dock_tab != DOCK_TAB_INSPECTOR: _switch_dock_tab(DOCK_TAB_INSPECTOR)

func _on_catalog_changed() -> void:
	_sync_resource_browser_entries()
	_chrome.queue_external_check(true)

func _sync_resource_browser_entries() -> void:
	if _catalog == null: return
	if _resource_browser != null:
		_resource_browser.set_entries(_catalog.entries)
		_sync_resource_browser_marks()
	if _inspector_panel != null:
		var c_paths: PackedStringArray = PackedStringArray()
		for e: Dictionary in _catalog.entries: c_paths.append(str(e["path"]))
		_inspector_panel.set_catalog_paths(c_paths)
	if _tab_resources_btn != null:
		_tab_resources_btn.tooltip_text = FlowEditorI18n.t(&"dock.tab_resources_count_tip", [_catalog.entries.size()])

func _sync_resource_browser_marks() -> void:
	if _resource_browser != null:
		_resource_browser.set_session_marks(_store.get_open_resource_status_map(), _store.get_live_source_paths(), _store.active_key if _store.is_resource_selected() else "")

func _on_browser_rescan_requested() -> void:
	if _catalog != null:
		_catalog.protocol_classes.clear()
		_catalog.rescan(true)
	_check_external_file_changes(true)

func _on_inspector_switch_to_resource(resource_path: String) -> void:
	open_resource_at_path(resource_path, true, false)

func _on_inspector_switch_to_live(memory_id: int) -> void:
	if _store.select_live_instance(memory_id):
		_rebuild_instance_dropdown()
		_switch_dock_tab(DOCK_TAB_INSPECTOR)
		_render_active_graph()

func _on_resolve_external_conflict(resource_path: String, accept_disk: bool) -> void:
	if accept_disk: _store.reload_resource_from_disk(resource_path)
	else: _store.dismiss_external_conflict(resource_path)
	_rebuild_instance_dropdown()
	_update_save_btn_visual()
	_render_active_graph()

#endregion


#region 视图渲染同步、子图面包屑与调试回调委派

func _switch_dock_tab(tab_id: int) -> void:
	_active_dock_tab = tab_id
	if _tab_telemetry_btn != null: _tab_telemetry_btn.set_pressed_no_signal(tab_id == DOCK_TAB_INSPECTOR)
	if _tab_resources_btn != null: _tab_resources_btn.set_pressed_no_signal(tab_id == DOCK_TAB_RESOURCES)
	if _tab_source_btn != null: _tab_source_btn.set_pressed_no_signal(tab_id == DOCK_TAB_SOURCE)
	if _telemetry_page != null: _telemetry_page.visible = (tab_id == DOCK_TAB_INSPECTOR)
	if _resources_page != null: _resources_page.visible = (tab_id == DOCK_TAB_RESOURCES)
	if _source_page != null: _source_page.visible = (tab_id == DOCK_TAB_SOURCE)

func _render_active_graph(focus_node_override: String = "\b") -> void:
	if _graph_canvas == null: return
	var g: MermaidGraphModel = _store.get_active_graph()
	var is_live: bool = _store.is_live_selected()
	var is_snap: bool = _store.is_snapshot_selected()
	var is_res: bool = _store.is_resource_selected()
	var read_only_topo: bool = _store.is_read_only_topology()

	_graph_canvas.render_graph(g, is_live, _store.get_active_plan(), read_only_topo)
	_graph_canvas.set_breakpoints(_store.get_active_breakpoints())
	if focus_node_override != "\b": _graph_canvas.select_and_focus_node(focus_node_override, false)

	_sync_code_from_store()
	_update_save_btn_visual()
	_update_undo_redo_visual()
	if _dir_toggle_btn != null and g != null: _dir_toggle_btn.text = String(g.direction)
	if _code_editor != null: _code_editor.editable = not read_only_topo
	if _transport_box != null: _transport_box.visible = is_live

	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	if is_live or is_snap:
		var disp_frame: Dictionary = _store.get_active_display_frame()
		var is_paused: bool = bool(disp_frame.get("paused", false)) and is_live
		_graph_canvas.apply_frame_telemetry(disp_frame)
		_pause_btn.set_pressed_no_signal(is_paused)
		_debug_ctrl.update_pause_btn_visual(is_paused)
		if _mode_badge_label != null:
			_mode_badge_label.text = MermaidSessionStore.format_mem_id(_store.get_selected_live_memory_id()) if is_live else FlowEditorI18n.t(&"dock.badge_snapshot")
			_mode_badge_label.add_theme_color_override("font_color", t.success if is_live else t.warning)
	else:
		_pause_btn.set_pressed_no_signal(false)
		_debug_ctrl.update_pause_btn_visual(false)
		if _mode_badge_label != null:
			_mode_badge_label.text = FlowEditorI18n.t(&"dock.badge_resource") if is_res else FlowEditorI18n.t(&"dock.badge_draft")
			_mode_badge_label.add_theme_color_override("font_color", t.accent if is_res else t.font_dim)

	if _nav_bar != null: _nav_bar.sync_state(_store)
	_refresh_inspector_panel(_graph_canvas.get_selected_node_id())
	_refresh_zoom_label()

func _update_save_btn_visual() -> void:
	if _save_res_btn != null:
		_save_res_btn.text = (FlowEditorI18n.t(&"toolbar.save_res_dirty") if bool(_store.get_active_record().get("dirty", false)) else FlowEditorI18n.t(&"toolbar.save_res")) if _store.is_resource_selected() else FlowEditorI18n.t(&"toolbar.export_res")

func _update_undo_redo_visual() -> void:
	if _undo_btn != null: _undo_btn.disabled = not _mutations.can_undo()
	if _redo_btn != null: _redo_btn.disabled = not _mutations.can_redo()

func _sync_code_from_store() -> void:
	if _code_editor == null: return
	var next_txt: String = _store.serialize_active_mermaid(_store.is_editable_mode())
	if _code_editor.text != next_txt:
		_suppress_code_signal = true
		_code_editor.text = next_txt
		_suppress_code_signal = false

func _rebuild_instance_dropdown() -> void:
	if _instance_select == null: return
	_instance_select.clear()
	var entries: Array[Dictionary] = _store.get_dropdown_entries()
	var select_idx: int = 0
	for i: int in range(entries.size()):
		var entry: Dictionary = entries[i]
		var mode_name: StringName = entry["mode"] as StringName
		var ico: Texture2D = IconStatusLive if mode_name == MermaidSessionStore.MODE_LIVE else (IconCodeDsl if mode_name == MermaidSessionStore.MODE_RESOURCE else IconStatusOffline)
		_instance_select.add_icon_item(ico, str(entry["label"]))
		if mode_name == _store.active_mode and str(entry["key"]) == _store.active_key: select_idx = i
	_instance_select.select(select_idx)
	_sync_resource_browser_marks()

func _refresh_inspector_panel(inspected_node_id: String = "") -> void:
	if _inspector_panel != null: _inspector_panel.rebuild_inspector(_store, inspected_node_id)

func _refresh_zoom_label() -> void:
	if _zoom_reset_btn != null and _graph_canvas != null: _zoom_reset_btn.text = "%d%%" % _graph_canvas.get_display_zoom_percent()

func _set_parse_hint(err_msg: String) -> void:
	if _parse_hint_bar != null and _parse_hint_label != null:
		_parse_hint_bar.visible = not err_msg.is_empty()
		_parse_hint_label.text = err_msg

func _on_mutation_view_sync(full_rerender: bool, fit_view: bool, focus_node_id: String) -> void:
	_rebuild_instance_dropdown()
	if full_rerender:
		_render_active_graph(focus_node_id)
		if fit_view and _graph_canvas != null and not _store.get_active_graph().nodes.is_empty(): _graph_canvas.fit_graph_view()
	else:
		_sync_code_from_store()
		_update_save_btn_visual()
		_update_undo_redo_visual()
		_refresh_inspector_panel(focus_node_id)

func _on_inspector_node_selected(node_id: String, center_view: bool) -> void:
	if _graph_canvas != null: _graph_canvas.select_and_focus_node(node_id, center_view)
	_refresh_inspector_panel(node_id)

func _on_code_text_changed() -> void:
	if not _suppress_code_signal and _store.is_editable_mode(): _code_debounce_timer.start(0.26)

func _on_dir_toggle_pressed() -> void:
	_mutations.toggle_direction()

func _on_sub_graph_open_requested(sub_path: String) -> void:
	var clean_sub: String = sub_path.strip_edges()
	if clean_sub.is_empty(): return
	var parent_path: String = _store.active_key if _store.is_resource_selected() else _store.get_active_linked_resource_path()
	if open_resource_at_path(clean_sub, true, true) and _nav_bar != null and not parent_path.is_empty() and parent_path != clean_sub:
		_nav_bar.push_breadcrumb(parent_path, parent_path.get_file())
		_nav_bar.sync_state(_store)

func _on_breadcrumb_selected(target_path: String, truncate_idx: int) -> void:
	if _nav_bar != null: _nav_bar.truncate_to(truncate_idx)
	open_resource_at_path(target_path, true, true)

func _on_instance_selected(idx: int) -> void:
	_store.select_by_dropdown_index(idx)
	_sync_resource_browser_marks()
	if _active_dock_tab != DOCK_TAB_RESOURCES:
		_switch_dock_tab(DOCK_TAB_INSPECTOR if (_store.is_live_selected() or _store.is_snapshot_selected() or _store.is_resource_selected()) else DOCK_TAB_SOURCE)
	_render_active_graph()
	if _graph_canvas != null and not _store.get_active_graph().nodes.is_empty(): _graph_canvas.fit_graph_view()

func _on_session_active_changed(is_active: bool) -> void:
	_debug_ctrl.on_session_active_changed(is_active, _chrome.topmost_enabled, _active_dock_tab)

func _on_instance_registered(memory_id: int, descriptor: Dictionary, topology: Dictionary, frame: Dictionary) -> void:
	_debug_ctrl.on_instance_registered(memory_id, descriptor, topology, frame)

func _on_instance_unregistered(memory_id: int) -> void:
	_debug_ctrl.on_instance_unregistered(memory_id)

func _on_topology_received(memory_id: int, topology: Dictionary) -> void:
	_debug_ctrl.on_topology_received(memory_id, topology)

func _on_frame_received(memory_id: int, frame: Dictionary) -> void:
	_debug_ctrl.on_frame_received(memory_id, frame)

func _on_edge_flow_received(memory_id: int, from_id: String, to_id: String, label: String) -> void:
	_debug_ctrl.on_edge_flow_received(memory_id, from_id, to_id, label)

#endregion
