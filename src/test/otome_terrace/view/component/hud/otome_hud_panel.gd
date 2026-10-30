@tool
class_name OtomeHudPanel
extends Control

## 乙女向户外庭院「晴风湖畔 · 花树咖啡露台」暖奶油玫瑰金 HUD 总面板。[br]
##
## [b]界面构成：[/b][br]
## 1. [code]%BubbleLayer[/code]：承载 3 枚跟随 3D 场景锚点投影的 [OtomeHotspotBubble] 悬浮互动气泡；[br]
## 2. 顶栏左：男主铭牌与樱花粉心动羁绊等级进度卡（[code]%AffinityCard[/code]）；顶栏右：天光与镜头胶囊按钮；[br]
## 3. 底栏：穿搭/神态/温柔招呼/就近互动胶囊栏 + [OtomeDialogueCard] 半透明浪漫对话卡 + 轻量键鼠提示条。

#region Signals
signal hotspot_clicked(hotspot_id: int)
signal outfit_cycle_requested
signal expr_cycle_requested
signal greet_requested
signal interact_requested
signal weather_toggle_requested
signal camera_toggle_requested
signal choice_selected(choice_index: int)
#endregion

#region Node Refs & Private State
@onready var _hotspot_bubble_0: OtomeHotspotBubble = %HotspotBubble0 as OtomeHotspotBubble
@onready var _hotspot_bubble_1: OtomeHotspotBubble = %HotspotBubble1 as OtomeHotspotBubble
@onready var _hotspot_bubble_2: OtomeHotspotBubble = %HotspotBubble2 as OtomeHotspotBubble
@onready var _bust_overlay: OtomeBustOverlay = get_node_or_null("%BustOverlay") as OtomeBustOverlay

@onready var _affinity_card: PanelContainer = %AffinityCard as PanelContainer
@onready var _hero_title_label: Label = %HeroTitleLabel as Label
@onready var _affinity_level_label: Label = %AffinityLevelLabel as Label
@onready var _affinity_progress_bar: ProgressBar = %AffinityProgressBar as ProgressBar
@onready var _status_badge_label: Label = %StatusBadgeLabel as Label

@onready var _weather_button: OtomeActionPill = %WeatherButton as OtomeActionPill
@onready var _camera_mode_button: OtomeActionPill = %CameraModeButton as OtomeActionPill

@onready var _outfit_pill: OtomeActionPill = %OutfitPill as OtomeActionPill
@onready var _expr_pill: OtomeActionPill = %ExprPill as OtomeActionPill
@onready var _greet_pill: OtomeActionPill = %GreetPill as OtomeActionPill
@onready var _interact_pill: OtomeActionPill = %InteractPill as OtomeActionPill

@onready var _dialogue_card: OtomeDialogueCard = %DialogueCard as OtomeDialogueCard
@onready var _hint_card: PanelContainer = %HintCard as PanelContainer
@onready var _hint_label: Label = %HintLabel as Label

var _bubbles: Array[OtomeHotspotBubble] = []
#endregion


#region Lifecycle
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubbles = [_hotspot_bubble_0, _hotspot_bubble_1, _hotspot_bubble_2]
	_apply_cream_rose_gold_theme()

	for i: int in range(_bubbles.size()):
		var b: OtomeHotspotBubble = _bubbles[i]
		if b != null:
			b.hotspot_id = i
			if i < OtomeTerraceConfig.HOTSPOT_BUBBLE_TEXTS.size():
				b.set_bubble_display(OtomeTerraceConfig.HOTSPOT_BUBBLE_TEXTS[i], false)
			if not Engine.is_editor_hint():
				b.hotspot_clicked.connect(_on_hotspot_bubble_clicked)

	if not Engine.is_editor_hint():
		if _weather_button != null:
			_weather_button.pressed.connect(func() -> void: weather_toggle_requested.emit())
		if _camera_mode_button != null:
			_camera_mode_button.pressed.connect(func() -> void: camera_toggle_requested.emit())
		if _outfit_pill != null:
			_outfit_pill.pressed.connect(func() -> void: outfit_cycle_requested.emit())
		if _expr_pill != null:
			_expr_pill.pressed.connect(func() -> void: expr_cycle_requested.emit())
		if _greet_pill != null:
			_greet_pill.pressed.connect(func() -> void: greet_requested.emit())
		if _interact_pill != null:
			_interact_pill.pressed.connect(func() -> void: interact_requested.emit())
		if _dialogue_card != null:
			_dialogue_card.choice_selected.connect(func(idx: int) -> void: choice_selected.emit(idx))
#endregion


#region Public Render API
## 从场景级 [SpinePool] 挂载近景动态半身立绘组件。
func mount_bust_from_pool(pool: SpinePool, skel_res: Resource) -> void:
	if _bust_overlay != null:
		_bust_overlay.mount_from_pool(pool, skel_res)


## 释放内部近景动态半身立绘实例。
func release_bust_spine() -> void:
	if _bust_overlay != null:
		_bust_overlay.release_spine()


## 根据最新 [OtomeTerraceState] 幂等刷新所有 HUD 卡片、近景动态半身像、胶囊按钮与对话内容。
func render_state(state: OtomeTerraceState) -> void:
	if state == null:
		return

	if _bust_overlay != null:
		var show_bust: bool = (
			state.is_closeup_camera
			or state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE
		)
		_bust_overlay.render_bust_state(show_bust, state.expr_index, state.weather_mode)

	if _hero_title_label != null:
		_hero_title_label.text = "✦ %s · %s" % [OtomeTerraceConfig.HERO_NAME, OtomeTerraceConfig.HERO_TITLE]
	if _affinity_level_label != null:
		_affinity_level_label.text = "♥ 心动羁绊 Lv.%d  (%d / %d)" % [
			state.affinity_level,
			state.affinity_points,
			state.affinity_max,
		]
	if _affinity_progress_bar != null:
		_affinity_progress_bar.max_value = float(maxi(1, state.affinity_max))
		_affinity_progress_bar.value = float(state.affinity_points)
	if _status_badge_label != null:
		_status_badge_label.text = state.status_badge_text

	var w_idx: int = clampi(state.weather_mode, 0, OtomeTerraceConfig.WEATHER_NAMES.size() - 1)
	if _weather_button != null:
		_weather_button.set_pill_display(
			"%s [L]" % OtomeTerraceConfig.WEATHER_NAMES[w_idx],
			w_idx == OtomeTerraceConfig.WeatherMode.SUNSET_LIGHTS
		)
	if _camera_mode_button != null:
		_camera_mode_button.set_pill_display(
			"镜头 · 半身特写 [C]" if state.is_closeup_camera else "镜头 · 庭院全景 [C]",
			state.is_closeup_camera
		)

	var o_idx: int = clampi(state.outfit_index, 0, OtomeTerraceConfig.OUTFIT_NAMES.size() - 1)
	if _outfit_pill != null:
		_outfit_pill.set_pill_display("穿搭 · %s [1]" % OtomeTerraceConfig.OUTFIT_NAMES[o_idx], false)

	var e_idx: int = clampi(state.expr_index, 0, OtomeTerraceConfig.EXPR_NAMES.size() - 1)
	if _expr_pill != null:
		_expr_pill.set_pill_display("神态 · %s [2]" % OtomeTerraceConfig.EXPR_NAMES[e_idx], state.expr_index == 2)

	if _greet_pill != null:
		_greet_pill.set_pill_display("温柔招呼 [G]", false)

	if _interact_pill != null:
		if state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE:
			_interact_pill.set_pill_display("漫步离开 [C]", true)
		elif state.nearby_hotspot_id != OtomeTerraceConfig.HotspotId.NONE:
			_interact_pill.set_pill_display(
				"进入 · %s [E]" % OtomeTerraceConfig.HOTSPOT_TITLES[state.nearby_hotspot_id],
				true
			)
		else:
			_interact_pill.set_pill_display("走近热点互动 [E]", false)

	if _dialogue_card != null:
		_dialogue_card.visible = state.dialogue_visible
		_dialogue_card.render_dialogue(
			state.dialogue_speaker,
			state.dialogue_spot_tag,
			state.dialogue_body,
			state.choices_visible,
			state.choice_a_text,
			state.choice_b_text
		)


## 每帧将 3D 场景中的三处热点锚点投影同步至 2D 悬浮气泡控件（特写对话态自动隐藏避免遮挡立绘）。
func update_hotspot_bubbles(
	screen_positions: Array[Vector2],
	nearby_id: int,
	hide_all: bool
) -> void:
	var view_size: Vector2 = size
	if view_size.x <= 1.0 or view_size.y <= 1.0:
		view_size = Vector2(1920.0, 1080.0)

	for i: int in range(_bubbles.size()):
		var bubble: OtomeHotspotBubble = _bubbles[i]
		if bubble == null:
			continue
		if hide_all or i >= screen_positions.size():
			bubble.visible = false
			continue
		var sp: Vector2 = screen_positions[i]
		if sp.x < -1000.0 or sp.y < -1000.0:
			bubble.visible = false
			continue

		var bsize: Vector2 = bubble.size
		if bsize.x < 10.0:
			bsize = bubble.custom_minimum_size
		var target_pos := Vector2(sp.x - bsize.x * 0.5, sp.y - bsize.y * 0.5)
		if target_pos.x < 24.0 or target_pos.y < 86.0 or target_pos.x + bsize.x > view_size.x - 24.0 or target_pos.y + bsize.y > view_size.y - 220.0:
			bubble.visible = false
			continue

		bubble.visible = true
		bubble.position = target_pos
		bubble.set_bubble_display(OtomeTerraceConfig.HOTSPOT_BUBBLE_TEXTS[i], i == nearby_id)
#endregion


#region Internal Styling & Callbacks
func _apply_cream_rose_gold_theme() -> void:
	if _affinity_card != null:
		var card_box := StyleBoxFlat.new()
		card_box.bg_color = Color(1.0, 0.992, 0.978, 0.93)
		card_box.border_color = Color("#D9A796")
		card_box.set_border_width_all(2)
		card_box.set_corner_radius_all(16)
		card_box.content_margin_left = 18.0
		card_box.content_margin_right = 18.0
		card_box.content_margin_top = 10.0
		card_box.content_margin_bottom = 10.0
		card_box.shadow_color = Color(0.32, 0.20, 0.18, 0.12)
		card_box.shadow_size = 8
		card_box.shadow_offset = Vector2(0.0, 3.0)
		_affinity_card.add_theme_stylebox_override("panel", card_box)

	if _hero_title_label != null:
		_hero_title_label.add_theme_color_override("font_color", Color("#563733"))
		_hero_title_label.add_theme_font_size_override("font_size", 15)
	if _affinity_level_label != null:
		_affinity_level_label.add_theme_color_override("font_color", Color("#C2596E"))
		_affinity_level_label.add_theme_font_size_override("font_size", 13)
	if _status_badge_label != null:
		_status_badge_label.add_theme_color_override("font_color", Color("#7A5852"))
		_status_badge_label.add_theme_font_size_override("font_size", 12)

	if _affinity_progress_bar != null:
		var bg_bar := StyleBoxFlat.new()
		bg_bar.bg_color = Color(0.95, 0.88, 0.86, 0.95)
		bg_bar.set_corner_radius_all(6)
		var fill_bar := StyleBoxFlat.new()
		fill_bar.bg_color = Color("#E58A9A")
		fill_bar.set_corner_radius_all(6)
		_affinity_progress_bar.add_theme_stylebox_override("background", bg_bar)
		_affinity_progress_bar.add_theme_stylebox_override("fill", fill_bar)

	if _hint_card != null:
		var hint_box := StyleBoxFlat.new()
		hint_box.bg_color = Color(1.0, 0.992, 0.98, 0.84)
		hint_box.border_color = Color("#E4BFB2")
		hint_box.set_border_width_all(1)
		hint_box.set_corner_radius_all(12)
		hint_box.content_margin_left = 16.0
		hint_box.content_margin_right = 16.0
		hint_box.content_margin_top = 5.0
		hint_box.content_margin_bottom = 5.0
		_hint_card.add_theme_stylebox_override("panel", hint_box)

	if _hint_label != null:
		_hint_label.add_theme_color_override("font_color", Color("#6B4E49"))
		_hint_label.add_theme_font_size_override("font_size", 12)


func _on_hotspot_bubble_clicked(spot_id: int) -> void:
	hotspot_clicked.emit(spot_id)
#endregion
