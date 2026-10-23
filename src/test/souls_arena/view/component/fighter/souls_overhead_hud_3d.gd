class_name SoulsOverheadHud3D
extends Node3D

## 3D 角色头顶战术预警与战斗飘字组件（位于 src/test/souls_arena/view/component/fighter/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 节点树直接定义于 [`souls_fighter_actor.tscn`](file:///d:/code/GodotProject/slacker-survivors/src/test/souls_arena/view/component/fighter/souls_fighter_actor.tscn)（`%StatusLabel3D` 与 `%PopupLabel3D`），脚本零 `.new()` 动态拼装；[br]
## 2. 平时隐藏冗余头顶铭牌以保持 3D 画面纯净，仅在危技蓄力、快慢刀、霸体、破绽或受击飘字时按需浮现。


#region 场景唯一节点绑定 (%UniqueName)

@onready var _status_label: Label3D = %StatusLabel3D as Label3D
@onready var _popup_label: Label3D = %PopupLabel3D as Label3D

var _is_boss_hud: bool = false
var _popup_timer: float = 0.0
var _popup_base_y: float = 3.05

#endregion


#region 初始化与配置

func setup_hud(is_boss: bool) -> void:
	_is_boss_hud = is_boss
	var status_y: float = 2.95 if is_boss else 2.40
	_popup_base_y = 3.45 if is_boss else 2.85
	if _status_label == null:
		_status_label = get_node_or_null("%StatusLabel3D") as Label3D
	if _popup_label == null:
		_popup_label = get_node_or_null("%PopupLabel3D") as Label3D
	if _status_label != null:
		_status_label.position = Vector3(0.0, status_y, 0.0)
		_status_label.visible = false
	if _popup_label != null:
		_popup_label.position = Vector3(0.0, _popup_base_y, 0.0)
		_popup_label.visible = false

#endregion


#region 飘字与状态刷新 API

func show_callout(text: String, color: Color = Color(1.0, 0.92, 0.35, 1.0), duration: float = 1.25) -> void:
	if _popup_label == null:
		return
	_popup_label.text = text
	_popup_label.modulate = color
	_popup_label.position.y = _popup_base_y
	_popup_label.visible = true
	_popup_timer = duration


func tick_hud(
	delta: float,
	_actor_title: String,
	state_name: StringName,
	is_unblockable_attack: bool,
	combo_step: int = 1,
	combo_total: int = 1,
	is_hyper_armor_active: bool = false,
	attack_tempo_tag: String = ""
) -> void:
	if _popup_timer > 0.0:
		_popup_timer = maxf(0.0, _popup_timer - delta)
		if _popup_label != null:
			_popup_label.position.y += delta * 0.26
			if _popup_timer <= 0.0:
				_popup_label.visible = false

	if _status_label == null:
		return

	# 玩家不常驻头顶状态标签，保持 3D 越肩视野干净
	if not _is_boss_hud:
		_status_label.visible = false
		return

	var badge: String = ""
	var col: Color = Color(0.95, 0.88, 0.68, 0.95)
	var combo_str: String = (" %d/%d" % [combo_step, combo_total]) if combo_total > 1 else ""
	var armor_prefix: String = "霸体 · " if is_hyper_armor_active else ""
	var tempo_str: String = attack_tempo_tag if not attack_tempo_tag.is_empty() else "蓄力"

	match state_name:
		SoulsCombatConfig.STATE_ATTACK_WINDUP:
			if is_unblockable_attack:
				badge = "危 · %s%s" % [tempo_str, combo_str]
				col = Color(1.0, 0.26, 0.28)
			else:
				badge = "%s%s%s" % [armor_prefix, tempo_str, combo_str]
				col = Color(1.0, 0.74, 0.24) if is_hyper_armor_active else Color(0.98, 0.84, 0.45)
		SoulsCombatConfig.STATE_ATTACK_RECOVERY:
			badge = "收刀破绽"
			col = Color(0.75, 0.92, 1.0)
		SoulsCombatConfig.STATE_STAGGERED:
			badge = "架势崩溃 · 可处决"
			col = Color(1.0, 0.36, 0.26)
		_:
			badge = ""

	if badge.is_empty():
		_status_label.visible = false
	else:
		_status_label.visible = true
		_status_label.text = badge
		_status_label.modulate = col

#endregion
