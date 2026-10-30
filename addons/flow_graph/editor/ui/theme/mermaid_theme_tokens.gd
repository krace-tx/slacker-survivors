@tool
extends RefCounted

## Godot 4 编辑器设计令牌值对象（Editor Design Tokens）。[br]
##
## 默认值严格取自 Godot 4 内置暗色预设（`base #363d4a` / `accent #70bafa` / `contrast 0.3`）与脚本编辑器默认语法配色；[br]
## 由 [`MermaidThemeService`](mermaid_theme_service.gd) 在编辑器内以用户实时主题覆盖原色，再经 [method derive] 推导全部派生色，保证插件与编辑器同色同调。[br]
## 纯数据叶子脚本：零 `preload` 依赖、零编辑器 API 调用。

#region 原色（可被编辑器主题覆盖）

var base: Color = Color(0.21, 0.24, 0.29)
var accent: Color = Color(0.44, 0.73, 0.98)
var dark1: Color = Color(0.147, 0.168, 0.203)
var dark2: Color = Color(0.1155, 0.132, 0.1595)
var dark3: Color = Color(0.084, 0.096, 0.116)
var font: Color = Color(0.804, 0.812, 0.824)
var mono: Color = Color(1.0, 1.0, 1.0)
var success: Color = Color(0.45, 0.95, 0.5)
var warning: Color = Color(1.0, 0.87, 0.4)
var error: Color = Color(1.0, 0.47, 0.42)

var code_bg: Color = Color(0.1155, 0.132, 0.1595)
var code_text: Color = Color(0.804, 0.812, 0.824)
var code_line_number: Color = Color(0.804, 0.812, 0.824, 0.5)
var code_current_line: Color = Color(1.0, 1.0, 1.0, 0.07)
var code_caret: Color = Color(0.878, 0.878, 0.878)
var code_selection: Color = Color(0.44, 0.73, 0.98, 0.4)
var code_keyword: Color = Color(1.0, 0.44, 0.52)
var code_control_flow: Color = Color(1.0, 0.55, 0.8)
var code_engine_type: Color = Color(0.56, 1.0, 0.86)
var code_comment: Color = Color(0.804, 0.812, 0.824, 0.5)
var code_string: Color = Color(1.0, 0.93, 0.63)
var code_number: Color = Color(0.63, 1.0, 0.88)
var code_symbol: Color = Color(0.67, 0.79, 1.0)
var code_function: Color = Color(0.34, 0.7, 1.0)
var code_member: Color = Color(0.74, 0.88, 1.0)

#endregion


#region 派生色（由 derive() 计算，禁止外部直接赋值）

var is_light: bool = false

var surface: Color = Color()
var surface_hover: Color = Color()
var border: Color = Color()
var border_strong: Color = Color()
var separator: Color = Color()
var hover_overlay: Color = Color()
var press_overlay: Color = Color()
var shadow: Color = Color()

var font_strong: Color = Color()
var font_dim: Color = Color()
var font_faint: Color = Color()
var icon: Color = Color()

var grid_minor: Color = Color()
var grid_major: Color = Color()

## 节点语义分类色，沿用 Godot 4 编辑器图标调色板（Node2D 蓝 / Control 绿 / 资源紫 / 动画黄 / 3D 红）
var cat_state: Color = Color()
var cat_entry: Color = Color()
var cat_interrupt: Color = Color()
var cat_selector: Color = Color()
var cat_sequence: Color = Color()
var cat_condition: Color = Color()
var cat_decorator: Color = Color()
var cat_action: Color = Color()

## 节点图标家族色（颜色只表达家族；红/绿保留给运行结果 SUCCESS / FAILURE）
var cat_flow: Color = Color()
var cat_leaf: Color = Color()
var cat_terminal: Color = Color()

const RADIUS_UI: int = 3
const RADIUS_CARD: int = 4

#endregion


#region 派生推导与签名

func derive() -> void:
	is_light = base.get_luminance() > 0.5
	separator = Color(font, 0.12)
	if not is_light:
		surface = base.darkened(0.12)
		surface_hover = base.darkened(0.04)
		border = base.lightened(0.09)
		border_strong = base.lightened(0.22)
		hover_overlay = Color(1.0, 1.0, 1.0, 0.06)
		press_overlay = Color(0.0, 0.0, 0.0, 0.22)
		shadow = Color(0.0, 0.0, 0.0, 0.28)
		font_strong = font.lerp(mono, 0.45)
		font_dim = font.lerp(base, 0.38)
		font_faint = font.lerp(base, 0.6)
		icon = Color(0.878, 0.878, 0.878)
		grid_minor = Color(1.0, 1.0, 1.0, 0.022)
		grid_major = Color(1.0, 1.0, 1.0, 0.05)
		cat_state = Color(0.878, 0.878, 0.878)
		cat_entry = Color(0.557, 0.937, 0.592)
		cat_interrupt = Color(0.765, 0.557, 0.945)
		cat_selector = Color(1.0, 0.792, 0.373)
		cat_sequence = Color(0.553, 0.647, 0.953)
		cat_condition = Color(0.557, 0.937, 0.592)
		cat_decorator = Color(0.765, 0.557, 0.945)
		cat_action = Color(0.988, 0.498, 0.498)
	else:
		surface = base.lightened(0.55)
		surface_hover = base.lightened(0.7)
		border = base.darkened(0.12)
		border_strong = base.darkened(0.26)
		hover_overlay = Color(0.0, 0.0, 0.0, 0.06)
		press_overlay = Color(0.0, 0.0, 0.0, 0.12)
		shadow = Color(0.0, 0.0, 0.0, 0.12)
		font_strong = font.lerp(Color.BLACK, 0.4)
		font_dim = font.lerp(base, 0.4)
		font_faint = font.lerp(base, 0.6)
		icon = Color(0.31, 0.31, 0.31)
		grid_minor = Color(0.0, 0.0, 0.0, 0.035)
		grid_major = Color(0.0, 0.0, 0.0, 0.07)
		cat_state = Color(0.31, 0.31, 0.31)
		cat_entry = Color(0.184, 0.631, 0.224)
		cat_interrupt = Color(0.659, 0.365, 0.914)
		cat_selector = Color(0.8, 0.608, 0.161)
		cat_sequence = Color(0.239, 0.392, 0.867)
		cat_condition = Color(0.184, 0.631, 0.224)
		cat_decorator = Color(0.659, 0.365, 0.914)
		cat_action = Color(0.804, 0.22, 0.22)
	cat_flow = cat_selector
	cat_leaf = icon
	cat_terminal = font_dim


func signature() -> String:
	return "|".join(PackedStringArray([
		base.to_html(), accent.to_html(), dark1.to_html(), dark2.to_html(), dark3.to_html(),
		font.to_html(), success.to_html(), warning.to_html(), error.to_html(),
		code_bg.to_html(), code_text.to_html(), code_keyword.to_html(), code_string.to_html(),
		code_comment.to_html(), code_number.to_html(), code_symbol.to_html(), code_selection.to_html(),
	]))


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)

#endregion


#region 样式盒工厂

## 构建 Godot 4 风格扁平样式盒；`margins` 为 `(左, 上, 右, 下)`，分量为负数时保持默认。
static func flat(
	bg: Color,
	radius: int = RADIUS_UI,
	border_color: Color = Color(0, 0, 0, 0),
	border_width: int = 0,
	margins: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if margins.x >= 0.0:
		sb.content_margin_left = margins.x
	if margins.y >= 0.0:
		sb.content_margin_top = margins.y
	if margins.z >= 0.0:
		sb.content_margin_right = margins.z
	if margins.w >= 0.0:
		sb.content_margin_bottom = margins.w
	return sb


## 构建单侧描边的面板条（工具栏底边、动作栏顶边等）。
static func bar(bg: Color, edge_color: Color, side: Side, margins: Vector4) -> StyleBoxFlat:
	var sb: StyleBoxFlat = flat(bg, 0, edge_color, 0, margins)
	match side:
		SIDE_LEFT:
			sb.border_width_left = 1
		SIDE_TOP:
			sb.border_width_top = 1
		SIDE_RIGHT:
			sb.border_width_right = 1
		SIDE_BOTTOM:
			sb.border_width_bottom = 1
	return sb

#endregion
