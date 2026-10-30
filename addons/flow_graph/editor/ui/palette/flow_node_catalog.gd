@tool
extends RefCounted

## FlowGraph 节点分组目录与元数据解析表（Grouped Node Catalog & Metadata Resolver）。[br]
##
## 统一维护状态机（FSM）与行为树（BT）全量可创建节点的语义分组、检索缩写、家族强调色、图标与单语说明，供左侧节点库抽屉与快速搜索面板共享复用。

const CanvasThemePalette = preload(FlowGraphContracts.SCRIPT_CANVAS_PALETTE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

const GROUP_FSM: StringName = &"fsm"
const GROUP_BT_ENTRY: StringName = &"bt_entry"
const GROUP_BT_COMPOSITES: StringName = &"bt_composites"
const GROUP_BT_LEAVES: StringName = &"bt_leaves"
const GROUP_BT_FLOW_DEC: StringName = &"bt_flow_dec"
const GROUP_BT_RES_DEC: StringName = &"bt_res_dec"

const PRESET_NONE: String = ""
const PRESET_INTERRUPT: String = "interrupt"
const PRESET_SUBGRAPH: String = "subgraph"

const KIND_ALIASES: Dictionary = {
	"State": "state st zt zhuangtai normal",
	"State:interrupt": "interrupt any global hit stun dd daduan quanju",
	"State:subgraph": "submachine subgraph hfsm nested zzt zizhuangtai",
	"Root": "root entry start tree gen genjiedian rukou",
	"Sequence": "sequence seq sx shunxu order",
	"Selector": "selector sel fallback xz xuanze",
	"Parallel": "parallel par concurrent bx bingxing",
	"WeightedSelector": "weighted random wsel jq jiaquan",
	"UtilitySelector": "utility score curve ai usel xy xiaoyong pingfen",
	"Action": "action act task dz dongzuo",
	"Condition": "condition cond check bool tj tiaojian",
	"Wait": "wait delay timer sleep dd dengdai",
	"SubTree": "subtree sub asset ref zs zishu",
	"Cooldown": "cooldown cd gate lq lengque",
	"TimeLimit": "timelimit timeout abort tl cs chaoshi",
	"Repeater": "repeater repeat loop rep xh xunhuan",
	"Service": "service tick poll srv fw fuwu",
	"Inverter": "inverter not negate inv qf qufan",
	"ForceSuccess": "forcesuccess always succeed fs",
	"ForceFailure": "forcefailure always fail ff",
}


#region 分组定义与过滤查询

## 根据当前画布模式返回可见分组列表；每项结构：`{"id": StringName, "title": String, "color": Color, "items": Array[Dictionary]}`。
static func build_groups(is_fsm: bool, is_empty_generic: bool, query: String = "") -> Array[Dictionary]:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var raw_groups: Array[Dictionary] = []

	if is_fsm or is_empty_generic:
		raw_groups.append({
			"id": GROUP_FSM,
			"title": FlowEditorI18n.t(&"drawer.group_fsm"),
			"color": t.cat_entry,
			"specs": [
				_spec("State", PRESET_NONE),
				_spec("State", PRESET_INTERRUPT),
				_spec("State", PRESET_SUBGRAPH),
			],
		})

	if (not is_fsm) or is_empty_generic:
		raw_groups.append({
			"id": GROUP_BT_ENTRY,
			"title": FlowEditorI18n.t(&"drawer.group_bt_entry"),
			"color": t.cat_entry,
			"specs": [
				_spec("Root"),
			],
		})
		raw_groups.append({
			"id": GROUP_BT_COMPOSITES,
			"title": FlowEditorI18n.t(&"drawer.group_bt_composites"),
			"color": t.cat_flow,
			"specs": [
				_spec("Sequence"),
				_spec("Selector"),
				_spec("UtilitySelector"),
				_spec("Parallel"),
				_spec("WeightedSelector"),
			],
		})
		raw_groups.append({
			"id": GROUP_BT_LEAVES,
			"title": FlowEditorI18n.t(&"drawer.group_bt_leaves"),
			"color": t.cat_sequence,
			"specs": [
				_spec("Action"),
				_spec("Condition"),
				_spec("Wait"),
				_spec("SubTree"),
			],
		})
		raw_groups.append({
			"id": GROUP_BT_FLOW_DEC,
			"title": FlowEditorI18n.t(&"drawer.group_bt_flow_dec"),
			"color": t.cat_decorator,
			"specs": [
				_spec("Cooldown"),
				_spec("TimeLimit"),
				_spec("Repeater"),
				_spec("Service"),
			],
		})
		raw_groups.append({
			"id": GROUP_BT_RES_DEC,
			"title": FlowEditorI18n.t(&"drawer.group_bt_res_dec"),
			"color": t.cat_decorator.lerp(t.accent, 0.30),
			"specs": [
				_spec("Inverter"),
				_spec("ForceSuccess"),
				_spec("ForceFailure"),
			],
		})

	var q: String = query.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for grp: Dictionary in raw_groups:
		var grp_title: String = str(grp["title"])
		var matched_items: Array[Dictionary] = []
		var specs: Array = grp["specs"] as Array
		for sp_v: Variant in specs:
			var item: Dictionary = sp_v as Dictionary
			if q.is_empty() or matches_query(item, grp_title, q):
				matched_items.append(item)
		if not matched_items.is_empty():
			out.append({
				"id": grp["id"] as StringName,
				"title": grp_title,
				"color": grp["color"] as Color,
				"items": matched_items,
			})
	return out


static func matches_query(item: Dictionary, group_title: String, q_lower: String) -> bool:
	if q_lower.is_empty():
		return true
	var hay: String = "%s %s %s %s %s" % [
		str(item.get("kind", "")),
		str(item.get("title", "")),
		str(item.get("tag", "")),
		str(item.get("aliases", "")),
		group_title,
	]
	return hay.to_lower().contains(q_lower)

#endregion


#region 单条目视觉与文案构造

static func _spec(kind: String, preset: String = PRESET_NONE) -> Dictionary:
	var alias_key: String = "%s:%s" % [kind, preset] if not preset.is_empty() else kind
	var title_s: String = resolve_item_title(kind, preset)
	var tag_s: String = resolve_item_tag(kind, preset)
	return {
		"key": alias_key,
		"kind": kind,
		"preset": preset,
		"title": title_s,
		"tag": tag_s,
		"icon": resolve_item_icon(kind, preset),
		"color": resolve_item_color(kind, preset),
		"aliases": str(KIND_ALIASES.get(alias_key, KIND_ALIASES.get(kind, ""))),
		"tooltip": FlowEditorI18n.t(&"drawer.item_tip", [title_s, tag_s]),
	}


static func resolve_item_title(kind: String, preset: String = PRESET_NONE) -> String:
	if kind == "State":
		if preset == PRESET_INTERRUPT:
			return FlowEditorI18n.t(&"drawer.item_state_interrupt")
		if preset == PRESET_SUBGRAPH:
			return FlowEditorI18n.t(&"drawer.item_state_subgraph")
	return FlowEditorI18n.kind_label(kind)


static func resolve_item_tag(kind: String, preset: String = PRESET_NONE) -> String:
	if kind == "State" and not preset.is_empty():
		return FlowEditorI18n.t(StringName("drawer.tag_State_%s" % preset))
	return FlowEditorI18n.t(StringName("drawer.tag_%s" % kind))


static func resolve_item_icon(kind: String, preset: String = PRESET_NONE) -> Texture2D:
	if kind == "State":
		if preset == PRESET_INTERRUPT:
			return FlowGraphIcons.NODE_ANY
		if preset == PRESET_SUBGRAPH:
			return FlowGraphIcons.NODE_PARALLEL
		return FlowGraphIcons.NODE_ENTRY
	return CanvasThemePalette.resolve_kind_icon(kind, false, false, false)


static func resolve_item_color(kind: String, preset: String = PRESET_NONE) -> Color:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	if kind == "State":
		if preset == PRESET_INTERRUPT:
			return t.cat_interrupt
		if preset == PRESET_SUBGRAPH:
			return t.cat_sequence
		return t.cat_entry
	if kind == "Action" or kind == "Condition" or kind == "Wait":
		return t.accent.lerp(t.cat_leaf, 0.35)
	return CanvasThemePalette.resolve_accent_color(kind, false, false, false)

#endregion
