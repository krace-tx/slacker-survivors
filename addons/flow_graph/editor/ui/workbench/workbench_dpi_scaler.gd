@tool
extends RefCounted

## 工作台 Godot 4 原生主题与 HiDPI 动态字号/间距缩放器（Workbench DPI & Theme Scaler）。[br]
##
## 负责监听 `EditorSettings` 主题变更，并将 `EditorInterface.get_editor_scale()` 与编辑器默认字号统一下发至顶栏按钮、缩放胶囊、右侧三页签、画布、检视器、资源目录与历史回放条。

const MermaidGraphCanvas = preload(FlowGraphContracts.SCRIPT_CANVAS)
const MermaidSyntaxHighlighter = preload(FlowGraphContracts.SCRIPT_SYNTAX_HIGHLIGHTER)
const MermaidInspectorPanel = preload(FlowGraphContracts.SCRIPT_INSPECTOR_PANEL)
const MermaidResourceBrowser = preload(FlowGraphContracts.SCRIPT_RESOURCE_BROWSER)
const WorkbenchNavScrubberBar = preload(FlowGraphContracts.SCRIPT_WB_NAV_BAR)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const MermaidWorkbenchStyler = preload(FlowGraphContracts.SCRIPT_WORKBENCH_STYLER)

var ui_scale_override: float = 0.0
var _last_applied_scale: float = -1.0
var _last_applied_fs: int = -1
var _wb: Control = null
var _on_theme_resynced: Callable = Callable()


func setup(wb: Control, on_theme_resynced: Callable) -> void:
	_wb = wb
	_on_theme_resynced = on_theme_resynced
	var es: EditorSettings = MermaidThemeService.editor_settings_or_null()
	if es != null and not es.settings_changed.is_connected(_on_editor_settings_changed):
		es.settings_changed.connect(_on_editor_settings_changed)


func _on_editor_settings_changed() -> void:
	if _wb != null and _wb.is_node_ready() and MermaidThemeService.refresh():
		reapply_all()


func apply_theme() -> void:
	if _wb == null:
		return
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	MermaidWorkbenchStyler.apply(_wb, t)
	for path: String in ["%UndoBtn", "%RedoBtn", "%LangToggleBtn"]:
		var u_btn: Button = _wb.get_node_or_null(path) as Button
		if u_btn != null:
			MermaidWorkbenchStyler.style_flat_button(u_btn, t, t.font, t.icon, Vector4(6, 2, 6, 2))
	var rb: MermaidResourceBrowser = _wb.get_node_or_null("%ResourceBrowser") as MermaidResourceBrowser
	if rb != null:
		rb.apply_theme(t)
	var ce: CodeEdit = _wb.get_node_or_null("%CodeEditor") as CodeEdit
	if ce != null:
		ce.syntax_highlighter = MermaidSyntaxHighlighter.create()
	var gc: MermaidGraphCanvas = _wb.get_node_or_null("%GraphCanvas") as MermaidGraphCanvas
	if gc != null:
		gc.queue_redraw()


func reapply_all() -> void:
	apply_theme()
	_last_applied_scale = -1.0
	apply_dpi_scale()
	if _on_theme_resynced.is_valid():
		_on_theme_resynced.call()


func set_scale_override(scale_val: float) -> void:
	ui_scale_override = clampf(scale_val, 0.75, 3.0)
	if _wb != null and _wb.is_node_ready():
		_last_applied_scale = -1.0
		apply_dpi_scale()
		if _on_theme_resynced.is_valid():
			_on_theme_resynced.call()


func apply_dpi_scale(nav_bar: WorkbenchNavScrubberBar = null) -> bool:
	if _wb == null:
		return false
	var s: float = ui_scale_override if ui_scale_override > 0.0 else (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)
	s = clampf(s, 0.75, 3.0)
	var base_fs: int = 0
	if ui_scale_override <= 0.0 and Engine.is_editor_hint() and EditorInterface.get_editor_theme() != null:
		base_fs = EditorInterface.get_editor_theme().default_font_size
	if base_fs <= 0:
		base_fs = roundi(14.0 * s)
	if is_equal_approx(_last_applied_scale, s) and _last_applied_fs == base_fs:
		return false
	_last_applied_scale = s
	_last_applied_fs = base_fs

	var sub_fs: int = maxi(11, roundi(float(base_fs) * 0.88))
	var btn_h: float = roundf(30.0 * s)
	var ico_px: int = maxi(15, roundi(16.0 * s))

	_scale_styles(_wb.get_node_or_null("%ToolbarPanel") as Control, [&"panel"], 10.0 * s, 5.0 * s, 0.0)
	for hb_p: String in ["%ToolbarHBox", "%TransportBox", "%HeaderRow"]:
		var hb: HBoxContainer = _wb.get_node_or_null(hb_p) as HBoxContainer
		if hb != null:
			hb.add_theme_constant_override("separation", roundi(5.0 * s))
	for sp_p: String in ["%Sep1", "%Sep2", "%Sep3"]:
		var sep_r: ColorRect = _wb.get_node_or_null(sp_p) as ColorRect
		if sep_r != null:
			sep_r.custom_minimum_size = Vector2(maxf(1.0, roundf(1.0 * s)), roundf(16.0 * s))

	var inst_sel: OptionButton = _wb.get_node_or_null("%InstanceSelect") as OptionButton
	if inst_sel != null:
		inst_sel.custom_minimum_size = Vector2(roundf(320.0 * s), btn_h)
		inst_sel.add_theme_font_size_override("font_size", base_fs)
		inst_sel.add_theme_constant_override("icon_max_width", ico_px)
		_scale_styles(inst_sel, [&"normal", &"hover", &"pressed"], 10.0 * s, 4.0 * s, 4.0 * s)
		if inst_sel.get_popup() != null:
			inst_sel.get_popup().add_theme_font_size_override("font_size", base_fs)
			inst_sel.get_popup().add_theme_constant_override("icon_max_width", ico_px)

	for tb_p: String in ["%OpenResBtn", "%SaveResBtn", "%PauseBtn", "%DirToggleBtn", "%AutoLayoutBtn", "%LangToggleBtn"]:
		var tb: Button = _wb.get_node_or_null(tb_p) as Button
		if tb != null:
			tb.custom_minimum_size = Vector2(roundf(44.0 * s) if tb_p == "%LangToggleBtn" else 0.0, btn_h)
			tb.add_theme_font_size_override("font_size", sub_fs if tb_p == "%LangToggleBtn" else base_fs)
			tb.add_theme_constant_override("icon_max_width", ico_px)
			_scale_styles(tb, [&"normal", &"hover", &"pressed"], 10.0 * s, 4.0 * s, 4.0 * s)

	for ib_p: String in ["%UndoBtn", "%RedoBtn", "%StepBtn", "%SnapToggleBtn", "%LabelsToggleBtn", "%MinimapToggleBtn", "%WindowMenuBtn", "%ToggleSidebarBtn"]:
		var ib: Button = _wb.get_node_or_null(ib_p) as Button
		if ib != null:
			ib.custom_minimum_size = Vector2(btn_h, btn_h)
			ib.add_theme_font_size_override("font_size", base_fs)
			ib.add_theme_constant_override("icon_max_width", maxi(16, roundi(17.0 * s)))
			_scale_styles(ib, [&"normal", &"hover", &"pressed"], 6.0 * s, 5.0 * s, 4.0 * s)

	var z_pod: PanelContainer = _wb.get_node_or_null("%ZoomPod") as PanelContainer
	if z_pod != null:
		var z_off: float = roundf(14.0 * s)
		z_pod.offset_left = z_off
		z_pod.offset_right = z_off
		z_pod.offset_top = -z_off
		z_pod.offset_bottom = -z_off
		_scale_styles(z_pod, [&"panel"], 4.0 * s, 3.0 * s, 6.0 * s)
	var z_h: float = roundf(26.0 * s)
	for zb_p: String in ["%ZoomOutBtn", "%ZoomInBtn", "%FitViewBtn"]:
		var zb: Button = _wb.get_node_or_null(zb_p) as Button
		if zb != null:
			zb.custom_minimum_size = Vector2(roundf(28.0 * s), z_h)
			zb.add_theme_font_size_override("font_size", base_fs)
			zb.add_theme_constant_override("icon_max_width", ico_px)
			_scale_styles(zb, [&"normal", &"hover", &"pressed"], 5.0 * s, 3.0 * s, 4.0 * s)
	var z_rst: Button = _wb.get_node_or_null("%ZoomResetBtn") as Button
	if z_rst != null:
		z_rst.custom_minimum_size = Vector2(roundf(56.0 * s), z_h)
		z_rst.add_theme_font_size_override("font_size", sub_fs)
		_scale_styles(z_rst, [&"normal", &"hover", &"pressed"], 6.0 * s, 3.0 * s, 4.0 * s)

	var r_side: Control = _wb.get_node_or_null("%RightSidebar") as Control
	if r_side != null:
		r_side.custom_minimum_size = Vector2(roundf(368.0 * s), 0.0)
	_scale_styles(_wb.get_node_or_null("%DockHeader") as Control, [&"panel"], 8.0 * s, 5.0 * s, 0.0)
	for tab_p: String in ["%TabTelemetryBtn", "%TabResourcesBtn", "%TabSourceBtn"]:
		var tab_b: Button = _wb.get_node_or_null(tab_p) as Button
		if tab_b != null:
			tab_b.custom_minimum_size = Vector2(0.0, roundf(28.0 * s))
			tab_b.add_theme_font_size_override("font_size", base_fs)
			tab_b.add_theme_constant_override("icon_max_width", ico_px)
			_scale_styles(tab_b, [&"normal", &"hover", &"pressed"], 10.0 * s, 4.0 * s, 4.0 * s)

	_scale_styles(_wb.get_node_or_null("%ModeChip") as Control, [&"panel"], 8.0 * s, 3.0 * s, 4.0 * s)
	var m_lbl: Label = _wb.get_node_or_null("%ModeBadgeLabel") as Label
	if m_lbl != null:
		m_lbl.add_theme_font_size_override("font_size", sub_fs)
	_scale_styles(_wb.get_node_or_null("%ParseHintBar") as Control, [&"panel"], 10.0 * s, 6.0 * s, 0.0)
	var p_lbl: Label = _wb.get_node_or_null("%ParseHintLabel") as Label
	if p_lbl != null:
		p_lbl.add_theme_font_size_override("font_size", sub_fs)
	var ce: CodeEdit = _wb.get_node_or_null("%CodeEditor") as CodeEdit
	if ce != null:
		ce.add_theme_font_size_override("font_size", maxi(12, roundi(float(base_fs) * 0.96)))
		_scale_styles(ce, [&"normal", &"focus", &"read_only"], 10.0 * s, 8.0 * s, 0.0)

	var gc: MermaidGraphCanvas = _wb.get_node_or_null("%GraphCanvas") as MermaidGraphCanvas
	if gc != null:
		gc.ui_scale = s
	var insp: MermaidInspectorPanel = _wb.get_node_or_null("%InspectorPanel") as MermaidInspectorPanel
	if insp != null:
		insp.setup_metrics(s, base_fs)
	var rb: MermaidResourceBrowser = _wb.get_node_or_null("%ResourceBrowser") as MermaidResourceBrowser
	if rb != null:
		rb.apply_metrics(s, base_fs)
	if nav_bar != null:
		nav_bar.apply_metrics(s, base_fs)
	return true


static func _scale_styles(ctrl: Control, names: Array[StringName], pad_h: float, pad_v: float, radius: float) -> void:
	if ctrl == null:
		return
	var ph: float = roundf(pad_h)
	var pv: float = roundf(pad_v)
	var rad: int = roundi(radius)
	for sname: StringName in names:
		var orig: StyleBox = ctrl.get_theme_stylebox(sname)
		if orig is StyleBoxFlat:
			var sb: StyleBoxFlat = (orig as StyleBoxFlat).duplicate() as StyleBoxFlat
			sb.content_margin_left = ph
			sb.content_margin_right = ph
			sb.content_margin_top = pv
			sb.content_margin_bottom = pv
			if rad > 0:
				sb.set_corner_radius_all(rad)
			ctrl.add_theme_stylebox_override(sname, sb)
