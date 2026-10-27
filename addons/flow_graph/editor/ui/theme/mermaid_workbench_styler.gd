@tool
extends RefCounted

## Mermaid 工作台 Godot 4 原生风格样式器（Workbench Godot 4 Styler）。[br]
##
## 按 Godot 4 编辑器的控件语言为工作台全部控件注入样式：扁平工具按钮（悬停浅叠加、切换态强调色图标）、`dark_color_1` 输入控件、[br]
## `base_color` 面板与 `dark_color_2` 代码区、3px 圆角与 1px 发丝分隔线。所有颜色均来自 [`MermaidThemeTokens`](mermaid_theme_tokens.gd)，随编辑器主题实时切换。

const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

const P_TOOLBAR: String = "ToolbarPanel"
const P_BACKDROP: String = "WorkspaceBackdrop"
const P_EXPAND_DRAWER_POD: String = "%ExpandDrawerPod"
const P_ZOOM_POD: String = "%ZoomPod"
const P_DOCK_HEADER: String = "%DockHeader"
const P_MODE_CHIP: String = "%ModeChip"
const SEPARATOR_PATHS: Array[String] = [
	"%Sep0",
	"%Sep1",
	"%Sep2",
	"%Sep3",
	"%ZoomSep",
]
const FLAT_ACTION_BUTTONS: Array[String] = ["%ToggleDrawerBtn", "%OpenResBtn", "%DirToggleBtn", "%AutoLayoutBtn", "%PauseBtn"]
const FLAT_ICON_BUTTONS: Array[String] = ["%StepBtn", "%SnapToggleBtn", "%LabelsToggleBtn", "%MinimapToggleBtn", "%WindowMenuBtn", "%ToggleSidebarBtn"]
const ZOOM_BUTTONS: Array[String] = ["%ExpandDrawerBtn", "%ZoomOutBtn", "%ZoomResetBtn", "%ZoomInBtn", "%FitViewBtn"]
const DOCK_TABS: Array[String] = ["%TabTelemetryBtn", "%TabResourcesBtn", "%TabSourceBtn"]


static func apply(root: Control, t: MermaidThemeTokens) -> void:
	if root == null or t == null:
		return

	_panel(root, P_TOOLBAR, MermaidThemeTokens.bar(t.base, t.dark3, SIDE_BOTTOM, Vector4(6, 3, 6, 3)))
	_panel(root, P_BACKDROP, MermaidThemeTokens.flat(t.dark3, 0))
	_panel(root, P_EXPAND_DRAWER_POD, MermaidThemeTokens.flat(Color(t.base, 0.94), MermaidThemeTokens.RADIUS_UI, Color(t.border, 0.65), 1, Vector4(2, 2, 2, 2)))
	_panel(root, P_ZOOM_POD, MermaidThemeTokens.flat(Color(t.base, 0.92), MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, Vector4(2, 2, 2, 2)))
	_panel(root, "%RightSidebar", MermaidThemeTokens.flat(t.base, 0))
	_panel(root, P_DOCK_HEADER, MermaidThemeTokens.bar(t.base, t.dark3, SIDE_BOTTOM, Vector4(4, 3, 6, 3)))
	_panel(root, P_MODE_CHIP, MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, Vector4(6, 1, 6, 1)))
	_panel(root, "%ParseHintBar", MermaidThemeTokens.bar(Color(t.error, 0.12), Color(t.error, 0.45), SIDE_BOTTOM, Vector4(10, 5, 10, 5)))

	for sep_path: String in SEPARATOR_PATHS:
		var sep: ColorRect = root.get_node_or_null(sep_path) as ColorRect
		if sep != null:
			sep.color = t.separator

	_style_option(root.get_node_or_null("%InstanceSelect") as Button, t)
	for p: String in FLAT_ACTION_BUTTONS:
		_style_flat(root.get_node_or_null(p) as Button, t, t.font, t.icon, Vector4(6, 2, 6, 2))
	var save_btn: Button = root.get_node_or_null("%SaveResBtn") as Button
	_style_flat(save_btn, t, t.accent, t.accent, Vector4(6, 2, 6, 2))
	for p2: String in FLAT_ICON_BUTTONS:
		_style_flat(root.get_node_or_null(p2) as Button, t, t.font, t.icon, Vector4(4, 4, 4, 4))
	for p3: String in ZOOM_BUTTONS:
		_style_flat(root.get_node_or_null(p3) as Button, t, t.font, t.icon, Vector4(4, 1, 4, 1))
	for p4: String in DOCK_TABS:
		_style_tab(root.get_node_or_null(p4) as Button, t)

	var hint_lbl: Label = root.get_node_or_null("%ParseHintLabel") as Label
	if hint_lbl != null:
		hint_lbl.add_theme_color_override(&"font_color", t.error.lerp(t.font_strong, 0.25))

	_style_code_editor(root.get_node_or_null("%CodeEditor") as CodeEdit, t)


#region 控件样式原语

## 供代码动态创建的停靠页签复用与静态页签一致的分段样式。
static func style_dock_tab(btn: Button, t: MermaidThemeTokens) -> void:
	_style_tab(btn, t)


## 供代码动态创建的工具按钮复用 Godot 4 扁平工具按钮样式。
static func style_flat_button(btn: Button, t: MermaidThemeTokens, font_c: Color, icon_c: Color, margins: Vector4 = Vector4(6, 2, 6, 2)) -> void:
	_style_flat(btn, t, font_c, icon_c, margins)


static func _panel(root: Control, path: String, sb: StyleBox) -> void:
	var pc: PanelContainer = root.get_node_or_null(path) as PanelContainer
	if pc != null:
		pc.add_theme_stylebox_override(&"panel", sb)


static func _apply_button_styles(btn: Button, normal: StyleBox, hover: StyleBox, pressed: StyleBox) -> void:
	btn.add_theme_stylebox_override(&"normal", normal)
	btn.add_theme_stylebox_override(&"hover", hover)
	btn.add_theme_stylebox_override(&"pressed", pressed)
	btn.add_theme_stylebox_override(&"hover_pressed", pressed)
	btn.add_theme_stylebox_override(&"disabled", normal)
	btn.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())


static func _apply_button_colors(btn: Button, font_c: Color, font_hover: Color, font_pressed: Color, icon_c: Color, icon_hover: Color, icon_pressed: Color, disabled: Color) -> void:
	btn.add_theme_color_override(&"font_color", font_c)
	btn.add_theme_color_override(&"font_focus_color", font_c)
	btn.add_theme_color_override(&"font_hover_color", font_hover)
	btn.add_theme_color_override(&"font_pressed_color", font_pressed)
	btn.add_theme_color_override(&"font_hover_pressed_color", font_pressed)
	btn.add_theme_color_override(&"font_disabled_color", disabled)
	btn.add_theme_color_override(&"icon_normal_color", icon_c)
	btn.add_theme_color_override(&"icon_focus_color", icon_c)
	btn.add_theme_color_override(&"icon_hover_color", icon_hover)
	btn.add_theme_color_override(&"icon_pressed_color", icon_pressed)
	btn.add_theme_color_override(&"icon_hover_pressed_color", icon_pressed)
	btn.add_theme_color_override(&"icon_disabled_color", disabled)


## Godot 4 扁平工具按钮：常态透明、悬停浅叠加、切换态加深底色并以强调色点亮图标。
static func _style_flat(btn: Button, t: MermaidThemeTokens, font_c: Color, icon_c: Color, margins: Vector4) -> void:
	if btn == null:
		return
	_apply_button_styles(
		btn,
		MermaidThemeTokens.flat(Color(0, 0, 0, 0), MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, margins),
		MermaidThemeTokens.flat(t.hover_overlay, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, margins),
		MermaidThemeTokens.flat(t.press_overlay, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, margins)
	)
	var hover_font: Color = font_c if font_c == t.accent else t.font_strong
	var hover_icon: Color = icon_c if icon_c == t.accent else icon_c.lerp(t.font_strong, 0.6)
	_apply_button_colors(btn, font_c, hover_font, t.accent, icon_c, hover_icon, t.accent, Color(t.font, 0.35))


static func _style_option(btn: Button, t: MermaidThemeTokens) -> void:
	if btn == null:
		return
	var m := Vector4(8, 2, 8, 2)
	_apply_button_styles(
		btn,
		MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, m),
		MermaidThemeTokens.flat(t.dark1.lerp(t.mono, 0.05), MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, m),
		MermaidThemeTokens.flat(t.dark1.darkened(0.15), MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, m)
	)
	_apply_button_colors(btn, t.font, t.font_strong, t.font_strong, Color.WHITE, Color.WHITE, Color.WHITE, Color(t.font, 0.35))


## 分段停靠页签：未选中为暗淡扁平文字，选中为 `dark_color_1` 底与强调色图标（对齐 Godot 4 主视口切换按钮）。
static func _style_tab(btn: Button, t: MermaidThemeTokens) -> void:
	if btn == null:
		return
	var m := Vector4(8, 2, 8, 2)
	_apply_button_styles(
		btn,
		MermaidThemeTokens.flat(Color(0, 0, 0, 0), MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, m),
		MermaidThemeTokens.flat(t.hover_overlay, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, m),
		MermaidThemeTokens.flat(t.dark1, MermaidThemeTokens.RADIUS_UI, Color(0, 0, 0, 0), 0, m)
	)
	_apply_button_colors(btn, t.font_dim, t.font, t.font_strong, t.font_dim, t.font, t.accent, Color(t.font, 0.35))


static func _style_code_editor(ce: CodeEdit, t: MermaidThemeTokens) -> void:
	if ce == null:
		return
	var sb: StyleBoxFlat = MermaidThemeTokens.flat(t.code_bg, 0, Color(0, 0, 0, 0), 0, Vector4(6, 6, 6, 6))
	ce.add_theme_stylebox_override(&"normal", sb)
	ce.add_theme_stylebox_override(&"focus", sb)
	ce.add_theme_stylebox_override(&"read_only", sb)
	ce.add_theme_color_override(&"background_color", t.code_bg)
	ce.add_theme_color_override(&"font_color", t.code_text)
	ce.add_theme_color_override(&"font_readonly_color", Color(t.code_text, 0.72))
	ce.add_theme_color_override(&"font_placeholder_color", Color(t.code_text, 0.32))
	ce.add_theme_color_override(&"current_line_color", t.code_current_line)
	ce.add_theme_color_override(&"caret_color", t.code_caret)
	ce.add_theme_color_override(&"selection_color", t.code_selection)
	ce.add_theme_color_override(&"line_number_color", t.code_line_number)

#endregion
