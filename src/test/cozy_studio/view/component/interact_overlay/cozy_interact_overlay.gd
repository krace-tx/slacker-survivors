class_name CozyInteractOverlay
extends Control

## 2.5D 世界空间投影 SVG 手账交互胶囊与飘浮气泡视图组件（零运行时建树，复用声明式节点池）。

signal interact_requested

const _PROMPT_NORMAL_SBX_PATH: String = "res://src/test/cozy_studio/assets/themes/sbx_cozy_studio_prompt_tag.tres"
const _PROMPT_HOVER_SBX_PATH: String = "res://src/test/cozy_studio/assets/themes/sbx_cozy_studio_pill_hover.tres"

const _ICO_LATTE_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ico_cozy_studio_latte.svg"
const _ICO_SEAT_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ico_cozy_studio_seat.svg"
const _ICO_SOFA_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ico_cozy_studio_sofa.svg"
const _ICO_PAW_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ico_cozy_studio_paw.svg"
const _ICO_STANDUP_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ico_cozy_studio_standup.svg"

const _BUBBLE_HEART_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ui_cozy_studio_heart_bubble.svg"
const _BUBBLE_LATTE_PATH: String = "res://src/test/cozy_studio/assets/textures/hud/ui_cozy_studio_latte_bubble.svg"

class _BubbleState extends RefCounted:
	var active: bool = false
	var world_origin: Vector3 = Vector3.ZERO
	var elapsed: float = 0.0
	var duration: float = 1.25
	var delay: float = 0.0
	var sway_phase: float = 0.0
	var drift_x_px: float = 0.0

@onready var _prompt_card: PanelContainer = %PromptCard as PanelContainer
@onready var _keycap_label: Label = %KeycapLabel as Label
@onready var _action_icon: TextureRect = %ActionIcon as TextureRect
@onready var _action_label: Label = %ActionLabel as Label
@onready var _bubble_0: TextureRect = %Bubble0 as TextureRect
@onready var _bubble_1: TextureRect = %Bubble1 as TextureRect
@onready var _bubble_2: TextureRect = %Bubble2 as TextureRect

var _sbx_normal: StyleBoxTexture = null
var _sbx_hover: StyleBoxTexture = null
var _ico_latte: Texture2D = null
var _ico_seat: Texture2D = null
var _ico_sofa: Texture2D = null
var _ico_paw: Texture2D = null
var _ico_standup: Texture2D = null
var _tex_heart_bubble: Texture2D = null
var _tex_latte_bubble: Texture2D = null

var _bubble_nodes: Array[TextureRect] = []
var _bubble_states: Array[_BubbleState] = []
var _next_bubble_slot: int = 0
var _prompt_visible_target: bool = false
var _prompt_world_pos: Vector3 = Vector3.ZERO
var _prompt_alpha: float = 0.0
var _anim_time: float = 0.0
var _current_spot: CozyStudioState.InteractSpotId = CozyStudioState.InteractSpotId.NONE
var _current_seated_flag: bool = false


func _ready() -> void:
	_sbx_normal = load(_PROMPT_NORMAL_SBX_PATH) as StyleBoxTexture
	_sbx_hover = load(_PROMPT_HOVER_SBX_PATH) as StyleBoxTexture
	_ico_latte = load(_ICO_LATTE_PATH) as Texture2D
	_ico_seat = load(_ICO_SEAT_PATH) as Texture2D
	_ico_sofa = load(_ICO_SOFA_PATH) as Texture2D
	_ico_paw = load(_ICO_PAW_PATH) as Texture2D
	_ico_standup = load(_ICO_STANDUP_PATH) as Texture2D
	_tex_heart_bubble = load(_BUBBLE_HEART_PATH) as Texture2D
	_tex_latte_bubble = load(_BUBBLE_LATTE_PATH) as Texture2D

	_bubble_nodes = [_bubble_0, _bubble_1, _bubble_2]
	_bubble_states.clear()
	for i: int in range(_bubble_nodes.size()):
		var st := _BubbleState.new()
		_bubble_states.append(st)
		if _bubble_nodes[i] != null:
			_bubble_nodes[i].visible = false

	if _prompt_card != null:
		_prompt_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_prompt_card.visible = false
		_prompt_card.gui_input.connect(_on_prompt_gui_input)
		_prompt_card.mouse_entered.connect(_on_prompt_mouse_entered)
		_prompt_card.mouse_exited.connect(_on_prompt_mouse_exited)


func _on_prompt_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			interact_requested.emit()
			accept_event()


func _on_prompt_mouse_entered() -> void:
	if _prompt_card != null and _sbx_hover != null:
		_prompt_card.add_theme_stylebox_override(&"panel", _sbx_hover)


func _on_prompt_mouse_exited() -> void:
	if _prompt_card != null and _sbx_normal != null:
		_prompt_card.add_theme_stylebox_override(&"panel", _sbx_normal)


## 更新当前激活的 3D 交互提示锚点、图标与文案。
func set_prompt_state(
	spot: CozyStudioState.InteractSpotId,
	world_pos: Vector3,
	action_text: String,
	is_seated_here: bool
) -> void:
	_prompt_visible_target = (spot != CozyStudioState.InteractSpotId.NONE and not action_text.is_empty())
	if _prompt_visible_target:
		_prompt_world_pos = world_pos

	if spot != _current_spot or is_seated_here != _current_seated_flag:
		_current_spot = spot
		_current_seated_flag = is_seated_here
		if _action_label != null and not action_text.is_empty():
			_action_label.text = action_text
		if _keycap_label != null:
			_keycap_label.text = "E"
		if _action_icon != null and spot != CozyStudioState.InteractSpotId.NONE:
			_action_icon.texture = _pick_spot_icon(spot, is_seated_here)
	elif _action_label != null and _prompt_visible_target:
		_action_label.text = action_text


func _pick_spot_icon(spot: CozyStudioState.InteractSpotId, is_seated_here: bool) -> Texture2D:
	if is_seated_here:
		return _ico_standup
	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			return _ico_latte
		CozyStudioState.InteractSpotId.WORKSTATION_CHAIR:
			return _ico_seat
		CozyStudioState.InteractSpotId.LOUNGE_SOFA:
			return _ico_sofa
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			return _ico_paw
	return _ico_latte


## 在 3D 世界坐标处喷出 SVG 治愈气泡（橘猫粉红爱心气泡 / 意式咖啡拿铁香气泡）。
func spawn_spot_bubbles(spot: CozyStudioState.InteractSpotId, world_origin: Vector3) -> void:
	if _bubble_nodes.is_empty():
		return
	var is_cat: bool = (spot == CozyStudioState.InteractSpotId.SLEEPING_CAT)
	var tex: Texture2D = _tex_heart_bubble if is_cat else _tex_latte_bubble
	var count: int = 3

	for i: int in range(count):
		var slot: int = _next_bubble_slot % _bubble_nodes.size()
		_next_bubble_slot += 1
		var node: TextureRect = _bubble_nodes[slot]
		var st: _BubbleState = _bubble_states[slot]
		if node == null or st == null:
			continue
		node.texture = tex
		st.active = true
		st.world_origin = world_origin + Vector3(float(i - 1) * 0.11, float(i) * 0.08, float(1 - i) * 0.06)
		st.elapsed = 0.0
		st.delay = float(i) * 0.09
		st.duration = 1.32 + float(i) * 0.12
		st.sway_phase = float(i) * 2.1
		st.drift_x_px = float(i - 1) * 26.0
		node.visible = false


## 每帧将 3D 交互锚点与活跃气泡实时投影到 2D 视口，保持矢量 SVG 锐利零变形。
func tick_overlay(delta: float, camera: Camera3D) -> void:
	_anim_time += delta
	if camera == null:
		return

	# 1. 悬浮交互胶囊平滑淡入淡出与 3D 投影定位
	var target_a: float = 1.0 if _prompt_visible_target else 0.0
	_prompt_alpha = lerpf(_prompt_alpha, target_a, 1.0 - exp(-14.0 * delta))
	if _prompt_card != null:
		if _prompt_alpha > 0.02 and not camera.is_position_behind(_prompt_world_pos):
			_prompt_card.visible = true
			_prompt_card.reset_size()
			var screen_pt: Vector2 = camera.unproject_position(_prompt_world_pos)
			var card_sz: Vector2 = _prompt_card.size
			var bob_y: float = sin(_anim_time * 3.8) * 3.2
			var vp_sz: Vector2 = get_viewport_rect().size
			var target_px := Vector2(
				clampf(screen_pt.x - card_sz.x * 0.5, 20.0, maxf(20.0, vp_sz.x - card_sz.x - 20.0)),
				clampf(screen_pt.y - card_sz.y - 8.0 + bob_y, 72.0, maxf(72.0, vp_sz.y - card_sz.y - 54.0))
			)
			_prompt_card.position = target_px
			_prompt_card.pivot_offset = card_sz * 0.5
			var pop_scale: float = lerpf(0.88, 1.0, _prompt_alpha)
			_prompt_card.scale = Vector2(pop_scale, pop_scale)
			_prompt_card.modulate = Color(1.0, 1.0, 1.0, _prompt_alpha)
		else:
			_prompt_card.visible = false

	# 2. SVG 治愈爱心/咖啡气泡上升摇摆动画
	for idx: int in range(_bubble_nodes.size()):
		var b_node: TextureRect = _bubble_nodes[idx]
		var st: _BubbleState = _bubble_states[idx]
		if b_node == null or st == null or not st.active:
			continue

		if st.delay > 0.0:
			st.delay -= delta
			continue

		st.elapsed += delta
		var p: float = st.elapsed / maxf(0.1, st.duration)
		if p >= 1.0 or camera.is_position_behind(st.world_origin):
			st.active = false
			b_node.visible = false
			continue

		b_node.visible = true
		var rise_world: Vector3 = st.world_origin + Vector3(0.0, p * 0.68, 0.0)
		var base_2d: Vector2 = camera.unproject_position(rise_world)
		var sway_x: float = sin(p * PI * 2.6 + st.sway_phase) * 9.5 + st.drift_x_px * p
		var b_sz: Vector2 = b_node.size
		b_node.position = base_2d - b_sz * 0.5 + Vector2(sway_x, 0.0)
		b_node.pivot_offset = b_sz * 0.5

		var sc: float = 1.0
		if p < 0.18:
			var k_in: float = p / 0.18
			sc = lerpf(0.25, 1.14, sin(k_in * PI * 0.5))
		elif p < 0.34:
			sc = lerpf(1.14, 1.0, (p - 0.18) / 0.16)
		else:
			sc = lerpf(1.0, 0.90, (p - 0.34) / 0.66)

		var alpha: float = 1.0 if p < 0.62 else clampf(1.0 - (p - 0.62) / 0.38, 0.0, 1.0)
		b_node.scale = Vector2(sc, sc)
		b_node.modulate = Color(1.0, 1.0, 1.0, alpha)
