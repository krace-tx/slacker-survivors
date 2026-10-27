@tool
extends RefCounted

## Mermaid 节点与标签像素度量契约（Typography & Capsule Metrics）。[br]
##
## 统一提供布局层与画布渲染层共享的 CJK/ASCII 文本像素估算、节点胶囊尺寸、本地回流终端宽度及图范式枚举常量。

const NODE_HEIGHT: float = 40.0
const NODE_MIN_W: float = 168.0
const NODE_MAX_W: float = 368.0
const ORIGIN_PAD: Vector2 = Vector2(72.0, 72.0)

const ARCHETYPE_FSM_HUB: StringName = &"fsm_hub"
const ARCHETYPE_BT_TREE: StringName = &"bt_tree"
const ARCHETYPE_DAG_PIPELINE: StringName = &"dag_pipeline"


## 估算文本像素宽度（区分 CJK 宽字符与 ASCII 字符）。
static func estimate_text_px(txt: String, cjk_px: float = 13.8, ascii_px: float = 7.4) -> float:
	var w: float = 0.0
	for i: int in range(txt.length()):
		var cp: int = txt.unicode_at(i)
		w += cjk_px if cp >= 0x2E80 else ascii_px
	return w


## 估算紧凑胶囊节点在 1.0x 世界坐标系下的确定性尺寸（精确预留左侧图标与右侧 RUNNING/FAILURE 状态胶囊空间，杜绝标题截断）。
static func estimate_node_size(nd: Dictionary) -> Vector2:
	var title_txt: String = str(nd.get("title", nd.get("id", "")))
	var title_w: float = estimate_text_px(title_txt, 14.2, 7.6)
	var badge_reserve: float = 72.0
	var font: Font = ThemeDB.fallback_font
	if font != null:
		title_w = maxf(title_w, font.get_string_size(title_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6.0)
		badge_reserve = maxf(badge_reserve, font.get_string_size("RUNNING", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 20.0)
	# 30px (左侧色条+图标) + title_w + 12px (安全间距) + badge_reserve (右侧状态胶囊)
	var px_w: float = 42.0 + title_w + badge_reserve
	return Vector2(clampf(ceilf(px_w), NODE_MIN_W, NODE_MAX_W), NODE_HEIGHT)


## 估算本地回流终端胶囊 `[-> Hub · label]` 的精确像素宽度（不含连接短柄）。
static func estimate_portal_pill_width(hub_short: String, raw_label: String) -> float:
	var clean_lbl: String = raw_label.strip_edges()
	var p_txt: String = "-> %s" % hub_short
	if not clean_lbl.is_empty():
		var short_l: String = clean_lbl if clean_lbl.length() <= 10 else (clean_lbl.substr(0, 9) + "..")
		p_txt = "-> %s · %s" % [hub_short, short_l]
	return estimate_text_px(p_txt, 10.4, 6.0) + 26.0


## 估算普通条件标签胶囊的近似像素宽度。
static func estimate_label_pill_width(raw_label: String) -> float:
	return 12.0 + estimate_text_px(raw_label, 10.5, 6.1)


## 提取紧凑状态短名（如 `"待机 (Idle)"` -> `"Idle"`）。
static func extract_short_name(title_str: String, fallback_id: String) -> String:
	var open_p: int = title_str.rfind("(")
	var close_p: int = title_str.rfind(")")
	if open_p >= 0 and close_p > open_p + 1:
		var inner: String = title_str.substr(open_p + 1, close_p - open_p - 1).strip_edges()
		if not inner.is_empty() and inner.length() <= 14:
			return inner
	if title_str.length() <= 10 and not title_str.is_empty():
		return title_str
	if fallback_id.length() <= 12:
		return fallback_id
	return fallback_id.substr(0, 10) + ".."
