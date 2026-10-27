@tool
class_name FlowGraphIcons
extends RefCounted

## FlowGraph 编辑器矢量图标预加载契约表（Preloaded SVG Texture Registry）。[br]
##
## 统一基于 [`FlowGraphContracts`](flow_graph_contracts.gd) 预加载单实例 `Texture2D`，供插件主栏、画布调色板、检视器与工作台共享引用。

const PLUGIN_MAIN: Texture2D = preload(FlowGraphContracts.ICON_PLUGIN_MAIN)

const STATUS_LIVE: Texture2D = preload(FlowGraphContracts.ICON_STATUS_LIVE)
const STATUS_OFFLINE: Texture2D = preload(FlowGraphContracts.ICON_STATUS_OFFLINE)
const STATUS_PAUSE: Texture2D = preload(FlowGraphContracts.ICON_STATUS_PAUSE)
const STATUS_PLAY: Texture2D = preload(FlowGraphContracts.ICON_STATUS_PLAY)
const STATUS_STEP: Texture2D = preload(FlowGraphContracts.ICON_STATUS_STEP)
const STATUS_BOLT: Texture2D = preload(FlowGraphContracts.ICON_STATUS_BOLT)

const TB_AUTO_LAYOUT: Texture2D = preload(FlowGraphContracts.ICON_TB_AUTO_LAYOUT)
const TB_CODE_DSL: Texture2D = preload(FlowGraphContracts.ICON_TB_CODE_DSL)
const TB_DIR_SWITCH: Texture2D = preload(FlowGraphContracts.ICON_TB_DIR_SWITCH)
const TB_FIT_VIEW: Texture2D = preload(FlowGraphContracts.ICON_TB_FIT_VIEW)
const TB_LABELS: Texture2D = preload(FlowGraphContracts.ICON_TB_LABELS)
const TB_MINIMAP: Texture2D = preload(FlowGraphContracts.ICON_TB_MINIMAP)
const TB_RESOURCE_LIST: Texture2D = preload(FlowGraphContracts.ICON_TB_RESOURCE_LIST)
const TB_LEFT_DRAWER: Texture2D = preload(FlowGraphContracts.ICON_TB_LEFT_DRAWER)
const TB_SIDEBAR: Texture2D = preload(FlowGraphContracts.ICON_TB_SIDEBAR)
const TB_SNAP: Texture2D = preload(FlowGraphContracts.ICON_TB_SNAP)
const TB_TELEMETRY: Texture2D = preload(FlowGraphContracts.ICON_TB_TELEMETRY)
const TB_WINDOW_FLOAT: Texture2D = preload(FlowGraphContracts.ICON_TB_WINDOW_FLOAT)

const NODE_ENTRY: Texture2D = preload(FlowGraphContracts.ICON_NODE_ENTRY)
const NODE_ANY: Texture2D = preload(FlowGraphContracts.ICON_NODE_ANY)
const NODE_FINAL: Texture2D = preload(FlowGraphContracts.ICON_NODE_FINAL)
const NODE_SELECTOR: Texture2D = preload(FlowGraphContracts.ICON_NODE_SELECTOR)
const NODE_SEQUENCE: Texture2D = preload(FlowGraphContracts.ICON_NODE_SEQUENCE)
const NODE_PARALLEL: Texture2D = preload(FlowGraphContracts.ICON_NODE_PARALLEL)
const NODE_INVERTER: Texture2D = preload(FlowGraphContracts.ICON_NODE_INVERTER)
const NODE_COOLDOWN: Texture2D = preload(FlowGraphContracts.ICON_NODE_COOLDOWN)
const NODE_DECORATOR: Texture2D = preload(FlowGraphContracts.ICON_NODE_DECORATOR)
const NODE_CONDITION: Texture2D = preload(FlowGraphContracts.ICON_NODE_CONDITION)
const NODE_ACTION: Texture2D = preload(FlowGraphContracts.ICON_NODE_ACTION)
const NODE_WAIT: Texture2D = preload(FlowGraphContracts.ICON_NODE_WAIT)

static var _scaled_svg_cache: Dictionary = {}


## 按当前编辑器 `EditorInterface.get_editor_scale()` 与深浅色主题实时光栅化顶部主视口（Main Screen）标签图标，免疫 Headless 导入缓存锁定 `16x16` 的问题。
static func create_main_screen_icon(scale_override: float = -1.0) -> Texture2D:
	var ed_scale: float = scale_override
	if ed_scale <= 0.0:
		ed_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	var is_light: bool = _is_editor_light_theme()
	var tex: Texture2D = load_scaled_svg(FlowGraphContracts.ICON_PLUGIN_MAIN, ed_scale, is_light)
	return tex if tex != null else PLUGIN_MAIN


## 从原始 `.svg` 源码按指定 `scale` 实时光栅化超清矢量 `ImageTexture`（带 `mtime` 自动失效的内存键值缓存）。
static func load_scaled_svg(svg_path: String, scale: float = 1.0, adapt_light_theme: bool = false) -> Texture2D:
	var q_scale: float = snappedf(clampf(scale, 0.75, 4.0), 0.05)
	var mtime: int = FileAccess.get_modified_time(svg_path)
	var cache_key: String = "%s|%d|%.2f|%s" % [svg_path, mtime, q_scale, "L" if adapt_light_theme else "D"]
	if _scaled_svg_cache.has(cache_key):
		return _scaled_svg_cache[cache_key] as Texture2D

	var svg_src: String = FileAccess.get_file_as_string(svg_path)
	if svg_src.is_empty():
		return null
	if adapt_light_theme:
		svg_src = svg_src.replace("#e0e0e0", "#5a5a5a").replace("#E0E0E0", "#5a5a5a")

	var img := Image.new()
	if img.load_svg_from_string(svg_src, q_scale) != OK or img.is_empty():
		return null
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_scaled_svg_cache[cache_key] = tex
	return tex


## 实时原位刷新编辑器顶部主视口栏（Main Screen Bar）中指定插件按钮的图标尺寸，无需重启编辑器或开关插件。
static func sync_editor_main_screen_button(plugin_title: String = "FlowGraph") -> void:
	if not Engine.is_editor_hint():
		return
	var base_ctrl: Control = EditorInterface.get_base_control()
	if base_ctrl == null:
		return
	var target_icon: Texture2D = create_main_screen_icon()
	if target_icon == null:
		return
	for node: Node in base_ctrl.find_children("*", "Button", true, false):
		var btn: Button = node as Button
		if btn != null and btn.text == plugin_title and btn.theme_type_variation == &"MainScreenButton":
			if btn.icon != target_icon:
				btn.icon = target_icon
				btn.update_minimum_size()
				btn.queue_redraw()
			break


static func _is_editor_light_theme() -> bool:
	if not Engine.is_editor_hint():
		return false
	var ed_settings: EditorSettings = EditorInterface.get_editor_settings()
	if ed_settings == null or not ed_settings.has_setting("interface/theme/base_color"):
		return false
	var base_col: Variant = ed_settings.get_setting("interface/theme/base_color")
	if base_col is Color:
		return (base_col as Color).get_luminance() > 0.5
	return false
