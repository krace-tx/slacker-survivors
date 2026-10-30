class_name SpineStageHudPanel
extends MarginContainer

## 2.5D「方案 B」舞台响应式 HUD 操控面板（声明式 Slate Dark 玻璃卡片布局）。[br]
##
## [b]核心职责：[/b][br]
## 1. 顶栏展示原型标题、实时骨骼动作语义徽章、连击伤害统计与 3D 光影切换按钮；[br]
## 2. 底栏并列排布 3 把可热切武器槽与 3 套可热切披风/头饰槽，并显示属性副标题与键鼠指引；[br]
## 3. 纯表现被动视图：仅绑定 [code]%UniqueName[/code] 节点，上行发射语义交互信号。

#region Signals
## 请求切换至指定槽位武器皮肤。
signal weapon_selected(index: int)
## 请求切换至指定槽位服饰套装皮肤。
signal outfit_selected(index: int)
## 请求切换 3D 庭院光影预设。
signal lighting_toggle_requested
#endregion

#region Node Refs
@onready var _top_bar_card: PanelContainer = %TopBarCard as PanelContainer
@onready var _action_badge: PanelContainer = %ActionBadge as PanelContainer
@onready var _action_label: Label = %ActionLabel as Label
@onready var _combat_badge: PanelContainer = %CombatBadge as PanelContainer
@onready var _combat_stat_label: Label = %CombatStatLabel as Label
@onready var _lighting_button: Button = %LightingButton as Button

@onready var _weapon_group_card: PanelContainer = %WeaponGroupCard as PanelContainer
@onready var _weapon_subtitle_label: Label = %WeaponSubtitleLabel as Label
@onready var _weapon_slot_0: SpineLoadoutSlotButton = %WeaponSlot0 as SpineLoadoutSlotButton
@onready var _weapon_slot_1: SpineLoadoutSlotButton = %WeaponSlot1 as SpineLoadoutSlotButton
@onready var _weapon_slot_2: SpineLoadoutSlotButton = %WeaponSlot2 as SpineLoadoutSlotButton

@onready var _outfit_group_card: PanelContainer = %OutfitGroupCard as PanelContainer
@onready var _outfit_subtitle_label: Label = %OutfitSubtitleLabel as Label
@onready var _outfit_slot_0: SpineLoadoutSlotButton = %OutfitSlot0 as SpineLoadoutSlotButton
@onready var _outfit_slot_1: SpineLoadoutSlotButton = %OutfitSlot1 as SpineLoadoutSlotButton
@onready var _outfit_slot_2: SpineLoadoutSlotButton = %OutfitSlot2 as SpineLoadoutSlotButton

@onready var _hint_card: PanelContainer = %HintCard as PanelContainer

var _weapon_buttons: Array[SpineLoadoutSlotButton] = []
var _outfit_buttons: Array[SpineLoadoutSlotButton] = []
#endregion


#region Lifecycle
func _ready() -> void:
	_apply_slate_dark_styles()
	_weapon_buttons = [_weapon_slot_0, _weapon_slot_1, _weapon_slot_2]
	_outfit_buttons = [_outfit_slot_0, _outfit_slot_1, _outfit_slot_2]

	for i: int in range(_weapon_buttons.size()):
		var w_btn: SpineLoadoutSlotButton = _weapon_buttons[i]
		if w_btn != null:
			w_btn.slot_index = i
			w_btn.slot_selected.connect(_on_weapon_slot_clicked)

	for j: int in range(_outfit_buttons.size()):
		var o_btn: SpineLoadoutSlotButton = _outfit_buttons[j]
		if o_btn != null:
			o_btn.slot_index = j
			o_btn.slot_selected.connect(_on_outfit_slot_clicked)

	if _lighting_button != null:
		_lighting_button.focus_mode = Control.FOCUS_NONE
		_lighting_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_lighting_button.pressed.connect(_on_lighting_pressed)
#endregion


#region Public Render API
## 根据最新 [SpineStageState] 一次性刷新顶栏状态徽章与底栏武器/护甲激活态。
func render_state(state: SpineStageState) -> void:
	if state == null:
		return

	if _action_label != null:
		_action_label.text = state.action_status_text
	if _combat_stat_label != null:
		_combat_stat_label.text = "命中 %d  ·  总伤 %d" % [state.combo_hits, state.total_damage]
	if _lighting_button != null:
		var light_idx: int = clampi(state.lighting_mode, 0, SpineStageConfig.LIGHTING_NAMES.size() - 1)
		_lighting_button.text = "光影: %s [L]" % SpineStageConfig.LIGHTING_NAMES[light_idx]

	var w_idx: int = SpineStageConfig.clamp_weapon_index(state.weapon_index)
	if _weapon_subtitle_label != null:
		_weapon_subtitle_label.text = "武器热切 [1-3]  ·  %s" % SpineStageConfig.WEAPON_SUBTITLES[w_idx]
	for i: int in range(_weapon_buttons.size()):
		var btn: SpineLoadoutSlotButton = _weapon_buttons[i]
		if btn != null:
			btn.set_slot_display(
				str(i + 1),
				SpineStageConfig.WEAPON_NAMES[i],
				SpineStageConfig.WEAPON_ACCENTS[i],
				i == w_idx
			)

	var o_idx: int = SpineStageConfig.clamp_outfit_index(state.outfit_index)
	if _outfit_subtitle_label != null:
		_outfit_subtitle_label.text = "披风/头饰 [Q/E]  ·  %s" % SpineStageConfig.OUTFIT_SUBTITLES[o_idx]
	var outfit_keys: Array[String] = ["4", "5", "6"]
	for j: int in range(_outfit_buttons.size()):
		var obtn: SpineLoadoutSlotButton = _outfit_buttons[j]
		if obtn != null:
			obtn.set_slot_display(
				outfit_keys[j],
				SpineStageConfig.OUTFIT_NAMES[j],
				SpineStageConfig.OUTFIT_ACCENTS[j],
				j == o_idx
			)
#endregion


#region Internal Styling & Callbacks
func _apply_slate_dark_styles() -> void:
	var surface_card: StyleBoxFlat = _make_card_style(
		Color(0.06, 0.09, 0.16, 0.86),
		Color("#334155"),
		12,
		14.0,
		10.0
	)
	if _top_bar_card != null:
		_top_bar_card.add_theme_stylebox_override("panel", surface_card)
	if _weapon_group_card != null:
		_weapon_group_card.add_theme_stylebox_override("panel", surface_card.duplicate() as StyleBoxFlat)
	if _outfit_group_card != null:
		_outfit_group_card.add_theme_stylebox_override("panel", surface_card.duplicate() as StyleBoxFlat)

	var pill_badge: StyleBoxFlat = _make_card_style(
		Color(0.11, 0.16, 0.26, 0.90),
		Color("#475569"),
		8,
		10.0,
		5.0
	)
	if _action_badge != null:
		_action_badge.add_theme_stylebox_override("panel", pill_badge)
	if _combat_badge != null:
		_combat_badge.add_theme_stylebox_override("panel", pill_badge.duplicate() as StyleBoxFlat)

	var hint_style: StyleBoxFlat = _make_card_style(
		Color(0.06, 0.09, 0.16, 0.78),
		Color("#1E293B"),
		8,
		14.0,
		6.0
	)
	if _hint_card != null:
		_hint_card.add_theme_stylebox_override("panel", hint_style)

	if _lighting_button != null:
		var light_normal: StyleBoxFlat = _make_card_style(
			Color(0.12, 0.18, 0.30, 0.92),
			Color("#38BDF8"),
			8,
			12.0,
			6.0
		)
		var light_hover: StyleBoxFlat = _make_card_style(
			Color(0.17, 0.25, 0.40, 0.96),
			Color("#7DD3FC"),
			8,
			12.0,
			6.0
		)
		_lighting_button.add_theme_stylebox_override("normal", light_normal)
		_lighting_button.add_theme_stylebox_override("hover", light_hover)
		_lighting_button.add_theme_stylebox_override("pressed", light_hover)
		_lighting_button.add_theme_color_override("font_color", Color("#F8FAFC"))
		_lighting_button.add_theme_font_size_override("font_size", 13)


func _make_card_style(
	bg: Color,
	border: Color,
	radius_px: int,
	pad_h: float,
	pad_v: float
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius_px)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	return box


func _on_weapon_slot_clicked(idx: int) -> void:
	weapon_selected.emit(idx)


func _on_outfit_slot_clicked(idx: int) -> void:
	outfit_selected.emit(idx)


func _on_lighting_pressed() -> void:
	lighting_toggle_requested.emit()
#endregion
