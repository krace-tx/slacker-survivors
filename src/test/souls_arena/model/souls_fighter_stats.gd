class_name SoulsFighterStats
extends RefCounted

## 魂系角色运行时属性、霸体状态、快慢刀参数与多段连招状态模型（位于 src/test/souls_arena/model/，遵循 MSVP 的 `Model` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载单个 3D 角色的生命值（Boss 1800 HP / 玩家 120 HP）、精力值、架势槽与 3D 移速；[br]
## 2. 维护实时防御与霸体标记（无敌帧 `is_invincible_iframe`、弹反窗口 `is_parry_window_active`、持续举盾 `is_block_active`、强霸体免硬直 `is_hyper_armor_active`）；[br]
## 3. 维护招式的完整三阶段时长（前摇 `windup_duration`、挥砍 `slash_duration`、收刀后摇 `recovery_duration`）与快慢刀变速标签（`attack_tempo_tag`）。


#region 基础属性

var actor_title: String = "骑士"
var is_boss: bool = false

var max_hp: float = SoulsCombatConfig.PLAYER_MAX_HP
var hp: float = SoulsCombatConfig.PLAYER_MAX_HP
var max_stamina: float = 100.0
var stamina: float = 100.0
var max_posture: float = 100.0
var posture: float = 0.0
var move_speed: float = 5.6

#endregion


#region 实时防御、霸体、快慢刀与连招上下文

var is_invincible_iframe: bool = false
var is_parry_window_active: bool = false
var is_block_active: bool = false
var is_hyper_armor_active: bool = false
var wants_hold_shield: bool = false

var is_unblockable_attack: bool = false
var attack_tempo_tag: String = ""
var windup_duration: float = 0.45
var slash_duration: float = 0.24
var recovery_duration: float = 0.42
var attack_damage: float = 32.0
var posture_damage: float = 30.0
var attack_range: float = 3.1
var slash_damage_dealt: bool = false

## 多段连招状态（1 = 第1击，2 = 第2击，3 = 第3击终结技）
var combo_step_index: int = 1
var combo_total_steps: int = 1
var combo_chain_id: StringName = &""
var queued_combo_input: bool = false
var combo_window_timer: float = 0.0

#endregion


#region 初始化与重置

func setup(title: String, boss_flag: bool) -> void:
	actor_title = title
	is_boss = boss_flag
	if is_boss:
		max_hp = SoulsCombatConfig.BOSS_MAX_HP
		hp = SoulsCombatConfig.BOSS_MAX_HP
		max_stamina = 100.0
		stamina = 100.0
		max_posture = 100.0
		posture = 0.0
		move_speed = 4.6
	else:
		max_hp = SoulsCombatConfig.PLAYER_MAX_HP
		hp = SoulsCombatConfig.PLAYER_MAX_HP
		max_stamina = 100.0
		stamina = 100.0
		max_posture = 100.0
		posture = 0.0
		move_speed = 5.8


func reset_full() -> void:
	hp = max_hp
	stamina = max_stamina
	posture = 0.0
	clear_defense_flags()
	wants_hold_shield = false
	is_unblockable_attack = false
	attack_tempo_tag = ""
	slash_damage_dealt = false
	combo_step_index = 1
	combo_total_steps = 1
	combo_chain_id = &""
	queued_combo_input = false
	combo_window_timer = 0.0


func clear_defense_flags(clear_hyper_armor: bool = true) -> void:
	is_invincible_iframe = false
	is_parry_window_active = false
	is_block_active = false
	if clear_hyper_armor:
		is_hyper_armor_active = false

#endregion


#region 精力与架势自然恢复 / 扣血判定

func regenerate_idle_or_move(delta: float) -> void:
	stamina = minf(max_stamina, stamina + 26.0 * delta)
	posture = maxf(0.0, posture - 8.5 * delta)


func regenerate_while_blocking(delta: float) -> void:
	stamina = minf(max_stamina, stamina + 7.5 * delta)
	posture = maxf(0.0, posture - 3.0 * delta)


func try_consume_stamina(cost: float, ignore_cost: bool = false) -> bool:
	if ignore_cost or is_boss:
		return true
	if stamina < cost:
		return false
	stamina = maxf(0.0, stamina - cost)
	return true


func add_posture(amount: float) -> bool:
	posture = minf(max_posture, posture + amount)
	return posture >= max_posture


## 扣减生命值，若生命值归零则返回 `true`（触发角色战败死亡）。
func apply_hp_damage(dmg: float) -> bool:
	hp = maxf(0.0, hp - dmg)
	return hp <= 0.0

#endregion


#region 招式前后摇、快慢刀与霸体连招参数配置

## 玩家三段连击起手或 Boss 三连狂斩第 1 段。
func configure_light_slash() -> void:
	if is_boss:
		configure_boss_triple_combo_step(1)
	else:
		configure_player_combo_step(1)


## 玩家专属：三段进阶连击 Combo（第 1 段迅捷斜斩 -> 第 2 段极速反手连斩 -> 第 3 段黄金霸体破军重劈）。
func configure_player_combo_step(step: int) -> void:
	combo_chain_id = &"player_triple_combo"
	combo_step_index = clampi(step, 1, 3)
	combo_total_steps = 3
	is_unblockable_attack = false
	slash_damage_dealt = false
	queued_combo_input = false
	combo_window_timer = 0.72
	match combo_step_index:
		1:
			is_hyper_armor_active = false
			attack_tempo_tag = "一段·迅捷斜斩"
			windup_duration = 0.20
			slash_duration = 0.18
			recovery_duration = 0.34
			attack_damage = 55.0
			posture_damage = 32.0
			attack_range = 3.10
		2:
			is_hyper_armor_active = false
			attack_tempo_tag = "二段·回旋反手斩"
			windup_duration = 0.16
			slash_duration = 0.18
			recovery_duration = 0.38
			attack_damage = 68.0
			posture_damage = 38.0
			attack_range = 3.25
		3:
			# 玩家连招第 3 段终结技：赋予玩家黄金霸体 + 踏步重劈高额伤害与削韧
			is_hyper_armor_active = true
			attack_tempo_tag = "三段·霸体破军重劈"
			windup_duration = 0.28
			slash_duration = 0.24
			recovery_duration = 0.48
			attack_damage = 98.0
			posture_damage = 56.0
			attack_range = 3.50


## Boss 专属：快慢变速三连狂斩（第 1 击标准斜劈 0.46s -> 第 2 击瞬发快刀 0.22s -> 第 3 击霸体慢刀重砸 0.86s）。
func configure_boss_triple_combo_step(step: int) -> void:
	combo_chain_id = &"boss_triple_combo"
	combo_step_index = clampi(step, 1, 3)
	combo_total_steps = 3
	is_unblockable_attack = false
	slash_damage_dealt = false
	match combo_step_index:
		1:
			is_hyper_armor_active = false
			attack_tempo_tag = "起手斜劈"
			windup_duration = 0.46
			slash_duration = 0.22
			recovery_duration = 0.45
			attack_damage = 22.0
			posture_damage = 26.0
			attack_range = 3.25
		2:
			# 第 2 击：极速反手快刀（仅 0.22s 前摇）
			is_hyper_armor_active = false
			attack_tempo_tag = "极速快刀"
			windup_duration = 0.22
			slash_duration = 0.20
			recovery_duration = 0.50
			attack_damage = 24.0
			posture_damage = 28.0
			attack_range = 3.35
		3:
			# 第 3 击：霸体悬停慢刀终结重砸（0.86s 长前摇抓翻滚 + 黄金霸体免打断 + 0.88s 大后摇）
			is_hyper_armor_active = true
			attack_tempo_tag = "霸体慢刀重砸"
			windup_duration = 0.86
			slash_duration = 0.28
			recovery_duration = 0.88
			attack_damage = 38.0
			posture_damage = 45.0
			attack_range = 3.65


## Boss 专属：招牌「深渊快慢刀 · 悬停假动作二连」（第 1 击 1.05s 霸体慢刀悬停抓早滚 -> 第 2 击 0.20s 零帧瞬发快刀）。
func configure_boss_delayed_feint_combo(step: int = 1) -> void:
	combo_chain_id = &"boss_delayed_feint"
	combo_step_index = clampi(step, 1, 2)
	combo_total_steps = 2
	is_unblockable_attack = false
	slash_damage_dealt = false
	if combo_step_index == 1:
		is_hyper_armor_active = true
		attack_tempo_tag = "霸体·慢刀悬停(勿早滚)"
		windup_duration = 1.05
		slash_duration = 0.25
		recovery_duration = 0.45
		attack_damage = 36.0
		posture_damage = 42.0
		attack_range = 3.60
	else:
		is_hyper_armor_active = true
		attack_tempo_tag = "霸体·瞬发快刀追击"
		windup_duration = 0.20
		slash_duration = 0.22
		recovery_duration = 0.86
		attack_damage = 26.0
		posture_damage = 30.0
		attack_range = 3.45


## Boss 专属：红光不可防御二连旋风斩（全程强霸体 + 第 2 击结束后 0.95s 大后摇破绽）。
func configure_unblockable_red_nova(step: int = 1) -> void:
	combo_chain_id = &"boss_red_whirlwind"
	combo_step_index = clampi(step, 1, 2)
	combo_total_steps = 2
	is_unblockable_attack = true
	is_hyper_armor_active = true
	slash_damage_dealt = false
	if combo_step_index == 1:
		attack_tempo_tag = "危·霸体旋风斩"
		windup_duration = 0.66
		slash_duration = 0.24
		recovery_duration = 0.55
		attack_damage = 38.0
		posture_damage = 55.0
		attack_range = 3.70
	else:
		attack_tempo_tag = "危·霸体裂地斩"
		windup_duration = 0.50
		slash_duration = 0.28
		recovery_duration = 0.95
		attack_damage = 46.0
		posture_damage = 68.0
		attack_range = 3.90


## Boss 专属：远距离霸体突进跳劈 + 极速横扫二连。
func configure_gap_closer_leap() -> void:
	combo_chain_id = &"boss_leap_combo"
	combo_step_index = 1
	combo_total_steps = 2
	is_unblockable_attack = false
	is_hyper_armor_active = true
	attack_tempo_tag = "霸体跳劈"
	windup_duration = 0.52
	slash_duration = 0.25
	recovery_duration = 0.78
	attack_damage = 30.0
	posture_damage = 36.0
	attack_range = 3.65
	slash_damage_dealt = false


## 检查当前挥砍结束后是否还有后续连招段数，若有则自动装载下一段参数并返回 `true`。
func try_advance_next_combo_step() -> bool:
	# 玩家三段连击：仅当挥砍期间存在预输入缓冲（queued_combo_input）时才自动无缝衔接下一刀；
	# 若未预输入，则进入收刀后摇并保留 combo_window_timer 窗口供玩家手动按键续连招！
	if combo_chain_id == &"player_triple_combo":
		if queued_combo_input and combo_step_index < combo_total_steps:
			if try_consume_stamina(12.0):
				configure_player_combo_step(combo_step_index + 1)
				return true
		queued_combo_input = false
		if combo_step_index >= combo_total_steps:
			combo_window_timer = 0.0
		else:
			combo_window_timer = 0.68
		return false

	if combo_step_index >= combo_total_steps:
		combo_step_index = 1
		combo_total_steps = 1
		combo_chain_id = &""
		is_hyper_armor_active = false
		attack_tempo_tag = ""
		return false

	var next_step: int = combo_step_index + 1
	match combo_chain_id:
		&"boss_triple_combo":
			configure_boss_triple_combo_step(next_step)
			return true
		&"boss_delayed_feint":
			configure_boss_delayed_feint_combo(next_step)
			return true
		&"boss_red_whirlwind":
			configure_unblockable_red_nova(next_step)
			return true
		&"boss_leap_combo":
			configure_boss_triple_combo_step(2)
			combo_chain_id = &"boss_leap_combo"
			combo_step_index = 2
			combo_total_steps = 2
			recovery_duration = 0.78
			return true
	return false

#endregion
