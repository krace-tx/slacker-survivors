@tool
extends RefCounted

## 画布 Godot 4 视觉调色板与节点语义图标表（Canvas Godot 4 Palette & Semantic Icon Registry）。[br]
##
## 由 [`MermaidThemeService`](../theme/mermaid_theme_service.gd) 的实时令牌派生画布全部颜色与样式盒：[br]
## 节点卡片对齐 Godot 4 状态机编辑器（中性卡片 + 强调色运行描边 + 底部播放进度条），连线默认中性灰、运行态强调色、瞬时跃迁警示色。[br]
## [b]节点图标标准：[/b][br]
## 1. 只表达有区分度的信息：FSM 普通状态不画图标，仅入口 / 全局打断 / 终态绘制；[br]
## 2. 沿用既有约定：FSM 采用 UML（入口实心点、终态靶心、`*` 全局打断），BT 采用通用字形（`?` 选择、`->` 顺序、`⇉` 并行/子树、`!` 取反、时钟冷却/限时、装饰器、菱形条件、播放动作、沙漏等待）；[br]
## 3. 颜色只表达家族：流程控制琥珀、装饰器紫、子树蓝、叶子中性白，红 / 绿保留给运行结果。

const MermaidGraphModel = preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

const IconEntryOrigin: Texture2D = FlowGraphIcons.NODE_ENTRY
const IconKindAny: Texture2D = FlowGraphIcons.NODE_ANY
const IconKindFinal: Texture2D = FlowGraphIcons.NODE_FINAL
const IconKindSelector: Texture2D = FlowGraphIcons.NODE_SELECTOR
const IconKindSequence: Texture2D = FlowGraphIcons.NODE_SEQUENCE
const IconKindParallel: Texture2D = FlowGraphIcons.NODE_PARALLEL
const IconKindInverter: Texture2D = FlowGraphIcons.NODE_INVERTER
const IconKindCooldown: Texture2D = FlowGraphIcons.NODE_COOLDOWN
const IconKindDecorator: Texture2D = FlowGraphIcons.NODE_DECORATOR
const IconKindCondition: Texture2D = FlowGraphIcons.NODE_CONDITION
const IconKindAction: Texture2D = FlowGraphIcons.NODE_ACTION
const IconKindWait: Texture2D = FlowGraphIcons.NODE_WAIT
const IconBoltTrigger: Texture2D = FlowGraphIcons.STATUS_BOLT

const FLOW_KINDS: Array[String] = ["Selector", "WeightedSelector", "Fallback", "Sequence", "Parallel"]
const DECORATOR_KINDS: Array[String] = [
	"Decorator", "Inverter", "Cooldown", "Repeat", "Repeater",
	"TimeLimit", "Timeout", "Limiter", "ForceSuccess", "ForceFailure",
	"AlwaysSucceed", "AlwaysFail", "Service",
]
const LEAF_KINDS: Array[String] = ["Condition", "Input", "Action", "Output", "Wait", "SubTree"]

var token_version: int = -1
var tokens: MermaidThemeTokens = null

#region 画布语义颜色

var canvas_bg: Color = Color()
var grid_minor: Color = Color()
var grid_major: Color = Color()

var text_title: Color = Color()
var text_title_active: Color = Color()
var text_dim: Color = Color()
var text_faint: Color = Color()

var accent: Color = Color()
var success: Color = Color()
var warning: Color = Color()
var error: Color = Color()
var interrupt: Color = Color()

var edge_idle: Color = Color()
var edge_dormant: Color = Color()
var edge_any: Color = Color()
var edge_focus: Color = Color()
var edge_hover: Color = Color()
var edge_trail: Color = Color()
var edge_active: Color = Color()
var edge_pulse: Color = Color()
var edge_success: Color = Color()
var edge_failure: Color = Color()

var minimap_edge: Color = Color()
var minimap_node: Color = Color()
var handle_bg: Color = Color()

#endregion

#region 样式盒

var sb_shadow: StyleBoxFlat = null
var sb_card_idle: StyleBoxFlat = null
var sb_card_hover: StyleBoxFlat = null
var sb_card_running: StyleBoxFlat = null
var sb_card_success: StyleBoxFlat = null
var sb_card_failure: StyleBoxFlat = null
var sb_select_ring: StyleBoxFlat = null
var sb_any_zone: StyleBoxFlat = null
var sb_any_badge: StyleBoxFlat = null
var sb_portal_idle: StyleBoxFlat = null
var sb_portal_active: StyleBoxFlat = null
var sb_pill_focus: StyleBoxFlat = null
var sb_pill_dim: StyleBoxFlat = null
var sb_pill_pulse: StyleBoxFlat = null
var sb_pill_active: StyleBoxFlat = null
var sb_pill_success: StyleBoxFlat = null
var sb_pill_fail: StyleBoxFlat = null
var sb_badge_chip: StyleBoxFlat = null
var sb_minimap: StyleBoxFlat = null

#endregion


func _init() -> void:
	tokens = MermaidThemeService.tokens()
	token_version = MermaidThemeService.version()
	var t: MermaidThemeTokens = tokens
	var r_card: int = MermaidThemeTokens.RADIUS_CARD
	var r_ui: int = MermaidThemeTokens.RADIUS_UI
	var clear := Color(0, 0, 0, 0)

	canvas_bg = t.dark2
	grid_minor = t.grid_minor
	grid_major = t.grid_major

	text_title = t.font
	text_title_active = t.font_strong
	text_dim = t.font_dim
	text_faint = t.font_faint

	accent = t.accent
	success = t.success
	warning = t.warning
	error = t.error
	interrupt = t.cat_interrupt

	edge_idle = Color(t.font, 0.34)
	edge_dormant = Color(t.font, 0.16)
	edge_any = Color(t.cat_interrupt, 0.42)
	edge_focus = Color(t.font_strong, 0.82)
	edge_hover = Color(t.font_strong, 0.96)
	edge_trail = Color(t.accent, 0.5)
	edge_active = Color(t.accent, 0.92)
	edge_pulse = Color(t.warning, 0.95)
	edge_success = Color(t.success, 0.62)
	edge_failure = Color(t.error, 0.5)

	minimap_edge = Color(t.font, 0.16)
	minimap_node = Color(t.font, 0.42)
	handle_bg = t.surface

	sb_shadow = make_flat_sb(t.shadow, clear, 0, r_card + 1)
	sb_card_idle = make_flat_sb(t.surface, t.border, 1, r_card)
	sb_card_hover = make_flat_sb(t.surface_hover, t.border_strong, 1, r_card)
	sb_card_running = make_flat_sb(t.surface.lerp(t.accent, 0.1), t.accent, 1, r_card)
	sb_card_success = make_flat_sb(t.surface.lerp(t.success, 0.06), Color(t.success, 0.55), 1, r_card)
	sb_card_failure = make_flat_sb(t.surface.lerp(t.error, 0.08), Color(t.error, 0.6), 1, r_card)
	sb_select_ring = make_flat_sb(clear, t.accent, 2, r_card + 2)

	sb_any_zone = make_flat_sb(Color(t.font, 0.018), Color(t.cat_interrupt, 0.22), 1, r_card + 2)
	sb_any_badge = make_flat_sb(t.surface, Color(t.cat_interrupt, 0.55), 1, r_ui)

	sb_portal_idle = make_flat_sb(Color(t.dark1, 0.96), t.border, 1, r_ui)
	sb_portal_active = make_flat_sb(t.dark1.lerp(t.warning, 0.14), Color(t.warning, 0.8), 1, r_ui)

	sb_pill_focus = make_flat_sb(t.surface, Color(t.font, 0.32), 1, r_ui)
	sb_pill_dim = make_flat_sb(Color(t.dark2, 0.94), Color(t.border, 0.85), 1, r_ui)
	sb_pill_pulse = make_flat_sb(t.dark1.lerp(t.warning, 0.16), Color(t.warning, 0.85), 1, r_ui)
	sb_pill_active = make_flat_sb(t.dark1.lerp(t.accent, 0.16), Color(t.accent, 0.8), 1, r_ui)
	sb_pill_success = make_flat_sb(t.dark1.lerp(t.success, 0.1), Color(t.success, 0.55), 1, r_ui)
	sb_pill_fail = make_flat_sb(t.dark1.lerp(t.error, 0.12), Color(t.error, 0.55), 1, r_ui)

	sb_badge_chip = make_flat_sb(Color(t.dark2, 0.9), clear, 0, r_ui)
	sb_minimap = make_flat_sb(Color(t.dark3, 0.92), t.border, 1, r_ui)


## 编辑器主题已变化而本调色板仍持有旧令牌时返回 `true`。
func is_stale() -> bool:
	return token_version != MermaidThemeService.version()


static func make_flat_sb(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	return MermaidThemeTokens.flat(bg, radius, border, bw)


#region 节点语义图标与家族色

func resolve_category_color(kind: String, is_initial: bool, is_interrupt: bool, is_terminal: bool = false) -> Color:
	return _family_color(tokens, kind, is_initial, is_interrupt, is_terminal)


static func resolve_accent_color(kind: String, is_initial: bool, is_interrupt: bool, is_terminal: bool = false) -> Color:
	return _family_color(MermaidThemeService.tokens(), kind, is_initial, is_interrupt, is_terminal)


## 返回节点语义图标；FSM 普通状态返回 `null`（不绘制图标，标题左移占位）。
static func resolve_kind_icon(kind: String, is_initial: bool, is_interrupt: bool = false, is_terminal: bool = false) -> Texture2D:
	match kind:
		"Selector", "WeightedSelector", "Fallback":
			return IconKindSelector
		"Sequence":
			return IconKindSequence
		"Parallel", "SubTree":
			return IconKindParallel
		"Inverter", "ForceFailure":
			return IconKindInverter
		"Cooldown", "TimeLimit", "Timeout", "Limiter":
			return IconKindCooldown
		"Decorator", "Repeater", "Repeat", "ForceSuccess", "Service", "AlwaysSucceed", "AlwaysFail":
			return IconKindDecorator
		"Condition", "Input":
			return IconKindCondition
		"Action", "Output":
			return IconKindAction
		"Wait":
			return IconKindWait
	if DECORATOR_KINDS.has(kind):
		return IconKindDecorator
	if is_initial:
		return IconEntryOrigin
	if is_terminal:
		return IconKindFinal
	if is_interrupt:
		return IconKindAny
	return null


static func get_bolt_trigger_icon() -> Texture2D:
	return IconBoltTrigger


## 状态图中无任何出边（且非入口）的节点视为 UML 终止状态；行为树叶子天然无出边，故仅对 `stateDiagram-v2` 生效。
static func is_fsm_terminal(graph: MermaidGraphModel, node_id: String) -> bool:
	if graph == null or graph.diagram_type != MermaidGraphModel.TYPE_STATE_V2 or node_id == graph.initial_node_id:
		return false
	for ed: Dictionary in graph.edges:
		if str(ed.get("from", "")) == node_id and str(ed.get("to", "")) != node_id:
			return false
	return true


static func _family_color(t: MermaidThemeTokens, kind: String, is_initial: bool, is_interrupt: bool, is_terminal: bool) -> Color:
	if kind == "SubTree":
		return t.cat_sequence
	if FLOW_KINDS.has(kind):
		return t.cat_flow
	if DECORATOR_KINDS.has(kind):
		return t.cat_decorator
	if LEAF_KINDS.has(kind):
		return t.cat_leaf
	if is_initial:
		return t.cat_entry
	if is_terminal:
		return t.cat_terminal
	if is_interrupt:
		return t.cat_interrupt
	return t.cat_state

#endregion
