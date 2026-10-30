class_name SoulsFighterActor
extends Node3D

## 3D 魂系角色实体协调组件（位于 src/test/souls_arena/view/component/fighter/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 组合 [SoulsFighterStats]、[StateMachine]、[SoulsKnightRig3D] 与 [SoulsOverheadHud3D]；[br]
## 2. 支持全 3D 地面（`XZ` 平面圆形竞技场）自由走位、锁定环绕侧步（Circle-Strafe）、8 向翻滚无敌帧与自动朝向插值；[br]
## 3. 支持 Boss 多段连招链（三连狂斩、跳劈二连、红光旋风二连斩）在 `STATE_ATTACK_SLASH` 结束时自动衔接到下一段 `STATE_ATTACK_WINDUP`。


#region 信号定义

signal state_changed(old_state: StringName, new_state: StringName)
signal combat_event_triggered(event_code: StringName, detail_bbcode: String)

#endregion


#region 状态常量别名

const STATE_IDLE: StringName = SoulsCombatConfig.STATE_IDLE
const STATE_MOVE: StringName = SoulsCombatConfig.STATE_MOVE
const STATE_DODGE: StringName = SoulsCombatConfig.STATE_DODGE
const STATE_PARRY: StringName = SoulsCombatConfig.STATE_PARRY
const STATE_BLOCK: StringName = SoulsCombatConfig.STATE_BLOCK
const STATE_ATTACK_WINDUP: StringName = SoulsCombatConfig.STATE_ATTACK_WINDUP
const STATE_ATTACK_SLASH: StringName = SoulsCombatConfig.STATE_ATTACK_SLASH
const STATE_ATTACK_RECOVERY: StringName = SoulsCombatConfig.STATE_ATTACK_RECOVERY
const STATE_RIPOSTE: StringName = SoulsCombatConfig.STATE_RIPOSTE
const STATE_HIT_STUN: StringName = SoulsCombatConfig.STATE_HIT_STUN
const STATE_STAGGERED: StringName = SoulsCombatConfig.STATE_STAGGERED
const STATE_DEAD: StringName = SoulsCombatConfig.STATE_DEAD

#endregion


#region 子组件与 3D 空间运动状态

var _stats: SoulsFighterStats = SoulsFighterStats.new()
var _fsm: StateMachine = null
var _rig_3d: SoulsKnightRig3D = null
var _overhead_hud: SoulsOverheadHud3D = null

## 3D 地面移动方向与朝向角（弧度）
var move_dir_3d: Vector3 = Vector3.ZERO
var dodge_dir_3d: Vector3 = Vector3.RIGHT
var facing_dir_3d: Vector3 = Vector3.RIGHT
var facing_yaw: float = 0.0
var is_lock_strafing: bool = true

var arena_radius: float = SoulsCombatConfig.ARENA_RADIUS
var state_elapsed: float = 0.0
var post_attack_pacing_timer: float = 0.0
var target_opponent: SoulsFighterActor = null

var _flash_timer: float = 0.0
var _hitstop_timer: float = 0.0
var _debug_fsm_id: int = 0

#endregion


#region 属性代理访问器

var actor_title: String:
	get: return _stats.actor_title
var is_boss_actor: bool:
	get: return _stats.is_boss
var max_hp: float:
	get: return _stats.max_hp
var hp: float:
	get: return _stats.hp
	set(v): _stats.hp = v
var max_stamina: float:
	get: return _stats.max_stamina
var stamina: float:
	get: return _stats.stamina
	set(v): _stats.stamina = v
var max_posture: float:
	get: return _stats.max_posture
var posture: float:
	get: return _stats.posture
	set(v): _stats.posture = v
var wants_hold_shield: bool:
	get: return _stats.wants_hold_shield
	set(v): _stats.wants_hold_shield = v
var is_unblockable_attack: bool:
	get: return _stats.is_unblockable_attack
var is_hyper_armor_active: bool:
	get: return _stats.is_hyper_armor_active
var attack_tempo_tag: String:
	get: return _stats.attack_tempo_tag
var current_windup_duration: float:
	get: return _stats.windup_duration
var combo_step_index: int:
	get: return _stats.combo_step_index
var combo_total_steps: int:
	get: return _stats.combo_total_steps

#endregion


#region 初始化与生命周期

func setup_actor(title: String, boss_flag: bool, theme_color: Color, spawn_pos: Vector3) -> void:
	_stats.setup(title, boss_flag)
	position = spawn_pos
	facing_dir_3d = Vector3.FORWARD if not boss_flag else Vector3.BACK
	facing_yaw = atan2(-facing_dir_3d.z, facing_dir_3d.x)

	_rig_3d = get_node_or_null("%KnightRig3D") as SoulsKnightRig3D
	if _rig_3d != null:
		_rig_3d.setup_rig(boss_flag, theme_color)

	_overhead_hud = get_node_or_null("%OverheadHud3D") as SoulsOverheadHud3D
	if _overhead_hud != null:
		_overhead_hud.setup_hud(boss_flag)

	_build_fsm_and_ast()
	if _overhead_hud != null:
		_overhead_hud.tick_hud(
			0.0,
			_stats.actor_title,
			get_current_state_name(),
			_stats.is_unblockable_attack,
			_stats.combo_step_index,
			_stats.combo_total_steps,
			_stats.is_hyper_armor_active,
			_stats.attack_tempo_tag
		)


func _exit_tree() -> void:
	if _debug_fsm_id != 0:
		GraphDebugBridge.unregister(_debug_fsm_id)
		_debug_fsm_id = 0
	target_opponent = null
	if _fsm != null:
		_fsm.clear()
		_fsm = null

#endregion


#region 公开查询与头顶飘字 API

func get_stats() -> SoulsFighterStats:
	return _stats


func get_fsm() -> StateMachine:
	return _fsm


func get_fsm_graph_def() -> FsmGraphDef:
	if _fsm == null:
		return null
	return _fsm.get_ast()


func get_current_state_name() -> StringName:
	if _fsm == null:
		return &""
	return _fsm.get_current_state_id()


func show_floating_callout(text: String, color: Color = Color(1.0, 0.92, 0.35, 1.0), duration: float = 1.65) -> void:
	if _overhead_hud != null:
		_overhead_hud.show_callout(text, color, duration)


func distance_to_opponent() -> float:
	if target_opponent == null:
		return 999.0
	var diff: Vector3 = target_opponent.position - position
	diff.y = 0.0
	return diff.length()

#endregion


#region 3D 战术动作与连招指令接口

func reset_combat_state(spawn_pos: Vector3) -> void:
	position = spawn_pos
	move_dir_3d = Vector3.ZERO
	post_attack_pacing_timer = 0.0
	_flash_timer = 0.0
	_hitstop_timer = 0.0
	_stats.reset_full()
	if target_opponent != null:
		_snap_face_towards(target_opponent.position)
	if _fsm != null:
		_fsm.change_state(STATE_IDLE, {}, true)


## 触发 3D 翻滚闪避（优先沿当前 `WASD` 方向翻滚；若未按方向键则向后撤步翻滚；玩家支持在收刀后摇期间翻滚取消）。
func cmd_dodge_roll(custom_dir: Vector3 = Vector3.ZERO, ignore_stamina: bool = false) -> bool:
	var cur: StringName = get_current_state_name()
	if cur in [
		STATE_DEAD,
		STATE_STAGGERED,
		STATE_HIT_STUN,
		STATE_DODGE,
		STATE_RIPOSTE,
		STATE_ATTACK_WINDUP,
		STATE_ATTACK_SLASH,
	]:
		return false
	if cur == STATE_ATTACK_RECOVERY and _stats.is_boss:
		return false
	if not _stats.try_consume_stamina(SoulsCombatConfig.DODGE_STAMINA_COST, ignore_stamina):
		show_floating_callout("精力不足", Color(1.0, 0.45, 0.4), 0.9)
		return false

	_stats.wants_hold_shield = false
	_stats.queued_combo_input = false
	if custom_dir.length_squared() > 0.01:
		dodge_dir_3d = Vector3(custom_dir.x, 0.0, custom_dir.z).normalized()
	elif move_dir_3d.length_squared() > 0.01:
		dodge_dir_3d = move_dir_3d.normalized()
	else:
		dodge_dir_3d = -facing_dir_3d.normalized()

	facing_dir_3d = dodge_dir_3d
	facing_yaw = atan2(-facing_dir_3d.z, facing_dir_3d.x)
	if _stats.is_boss:
		show_floating_callout("战术闪避", Color(0.32, 0.94, 1.0), 0.9)
	return _fsm.change_state(STATE_DODGE, {}, true)


func cmd_parry_or_block() -> bool:
	var cur: StringName = get_current_state_name()
	if cur in [
		STATE_DEAD,
		STATE_STAGGERED,
		STATE_HIT_STUN,
		STATE_DODGE,
		STATE_RIPOSTE,
		STATE_PARRY,
		STATE_ATTACK_WINDUP,
		STATE_ATTACK_SLASH,
	]:
		return false
	if cur == STATE_ATTACK_RECOVERY and _stats.is_boss:
		return false
	if target_opponent != null:
		_snap_face_towards(target_opponent.position)
	_stats.wants_hold_shield = true
	_stats.queued_combo_input = false
	if _stats.is_boss:
		show_floating_callout("振刀格挡", Color(0.98, 0.86, 0.35), 0.9)
	return _fsm.change_state(STATE_PARRY, {}, true)


func cmd_release_shield() -> void:
	_stats.wants_hold_shield = false
	if get_current_state_name() == STATE_BLOCK:
		_fsm.change_state(STATE_IDLE)


func cmd_light_attack_or_riposte() -> bool:
	var cur: StringName = get_current_state_name()
	if cur in [
		STATE_DEAD,
		STATE_STAGGERED,
		STATE_HIT_STUN,
		STATE_DODGE,
		STATE_RIPOSTE,
	]:
		return false

	# 玩家三段连击：若当前正在前摇或挥砍中再次按下左键/J，进入「连击预输入缓冲 (Input Buffer)」
	if not _stats.is_boss and cur in [STATE_ATTACK_WINDUP, STATE_ATTACK_SLASH]:
		if _stats.combo_step_index < 3:
			_stats.queued_combo_input = true
			return true
		return false

	if _stats.is_boss and cur in [STATE_ATTACK_WINDUP, STATE_ATTACK_SLASH, STATE_ATTACK_RECOVERY]:
		return false

	_stats.wants_hold_shield = false
	if target_opponent != null:
		_snap_face_towards(target_opponent.position)
		if target_opponent.get_current_state_name() == STATE_STAGGERED:
			if distance_to_opponent() <= SoulsCombatConfig.RIPOSTE_MAX_DISTANCE:
				_stats.combo_window_timer = 0.0
				_stats.queued_combo_input = false
				return _fsm.change_state(STATE_RIPOSTE, {}, true)

	# 计算玩家当前应触发的三连击段数（1 -> 2 -> 3）：支持收刀后摇取消或 0.68s 续连窗口
	var target_combo_step: int = 1
	if not _stats.is_boss:
		if (cur == STATE_ATTACK_RECOVERY or _stats.combo_window_timer > 0.0) and _stats.combo_chain_id == &"player_triple_combo" and _stats.combo_step_index < 3:
			target_combo_step = _stats.combo_step_index + 1

	var stamina_cost: float = 12.0 if target_combo_step > 1 else 14.0
	if not _stats.try_consume_stamina(stamina_cost):
		show_floating_callout("精力不足", Color(1.0, 0.45, 0.4), 0.9)
		return false

	if _stats.is_boss:
		_stats.configure_light_slash()
	else:
		_stats.configure_player_combo_step(target_combo_step)
		if target_combo_step == 3:
			show_floating_callout("霸体 · 破军劈", Color(1.0, 0.72, 0.22), 1.0)
	return _fsm.change_state(STATE_ATTACK_WINDUP, {}, true)


## Boss 专属：发起红光不可防御二连旋风斩。
func cmd_unblockable_red_nova() -> bool:
	var cur: StringName = get_current_state_name()
	if cur in [
		STATE_DEAD,
		STATE_STAGGERED,
		STATE_HIT_STUN,
		STATE_ATTACK_WINDUP,
		STATE_ATTACK_SLASH,
		STATE_ATTACK_RECOVERY,
	]:
		return false
	_stats.wants_hold_shield = false
	if target_opponent != null:
		_snap_face_towards(target_opponent.position)
	_stats.configure_unblockable_red_nova(1)
	show_floating_callout("危 · 旋风斩", Color(1.0, 0.22, 0.28), 1.1)
	return _fsm.change_state(STATE_ATTACK_WINDUP, {}, true)


## Boss 专属：远距离突进跳劈 + 横扫追击二连。
func cmd_gap_closer_leap() -> bool:
	var cur: StringName = get_current_state_name()
	if cur in [
		STATE_DEAD,
		STATE_STAGGERED,
		STATE_HIT_STUN,
		STATE_ATTACK_WINDUP,
		STATE_ATTACK_SLASH,
		STATE_ATTACK_RECOVERY,
	]:
		return false
	_stats.wants_hold_shield = false
	if target_opponent != null:
		_snap_face_towards(target_opponent.position)
	_stats.configure_gap_closer_leap()
	show_floating_callout("霸体 · 跳劈", Color(1.0, 0.72, 0.28), 1.0)
	return _fsm.change_state(STATE_ATTACK_WINDUP, {}, true)


## Boss 专属：发动招牌「深渊快慢刀 · 悬停假动作二连」（第1击 1.05s 霸体慢刀抓早滚 -> 第2击 0.20s 极速快刀）。
func cmd_delayed_feint_combo() -> bool:
	var cur: StringName = get_current_state_name()
	if cur in [
		STATE_DEAD,
		STATE_STAGGERED,
		STATE_HIT_STUN,
		STATE_ATTACK_WINDUP,
		STATE_ATTACK_SLASH,
		STATE_ATTACK_RECOVERY,
	]:
		return false
	_stats.wants_hold_shield = false
	if target_opponent != null:
		_snap_face_towards(target_opponent.position)
	_stats.configure_boss_delayed_feint_combo(1)
	show_floating_callout("霸体 · 快慢刀", Color(1.0, 0.68, 0.18), 1.1)
	return _fsm.change_state(STATE_ATTACK_WINDUP, {}, true)


func force_staggered_state() -> void:
	_stats.posture = _stats.max_posture
	_stats.combo_total_steps = 1
	_stats.combo_step_index = 1
	_fsm.change_state(STATE_STAGGERED, {}, true)
	show_floating_callout("架势崩溃", Color(1.0, 0.35, 0.25), 1.6)

#endregion


#region 四维受击结算矩阵（Dodge I-Frame vs Parry vs Block vs Direct Hit）

func receive_melee_strike(
	attacker: SoulsFighterActor,
	raw_damage: float,
	posture_dmg: float,
	unblockable: bool
) -> StringName:
	if get_current_state_name() == STATE_DEAD:
		return SoulsCombatConfig.RESULT_HIT

	# 1. 翻滚无敌帧 (I-Frame 0.30s)
	if _stats.is_invincible_iframe:
		show_floating_callout("无敌闪避", Color(0.25, 0.96, 1.0), 1.2)
		combat_event_triggered.emit(
			SoulsCombatConfig.RESULT_DODGED,
			"[color=#3ce8ff][无敌闪避][/color] %s 闪避 [%s] 斩击" % [
				_stats.actor_title,
				attacker.actor_title,
			]
		)
		return SoulsCombatConfig.RESULT_DODGED

	# 2. 完美弹反窗口 (Parry Window 0.18s)
	if _stats.is_parry_window_active and not unblockable:
		show_floating_callout("完美弹反", Color(1.0, 0.90, 0.25), 1.4)
		apply_hitstop(0.085)
		attacker.apply_hitstop(0.085)
		attacker.apply_parry_deflection(SoulsCombatConfig.PARRY_POSTURE_DEFLECTION)
		combat_event_triggered.emit(
			SoulsCombatConfig.RESULT_PARRIED,
			"[color=#ffe042][完美弹反][/color] %s 振刀打断 [%s] (+55 架势)" % [
				_stats.actor_title,
				attacker.actor_title,
			]
		)
		return SoulsCombatConfig.RESULT_PARRIED

	# 3. 持续举盾格挡 (Standard Block 80% 减伤)
	if (_stats.is_block_active or _stats.is_parry_window_active) and not unblockable:
		var chip_dmg: float = roundf(raw_damage * SoulsCombatConfig.BLOCK_CHIP_DAMAGE_RATIO)
		var died_from_chip: bool = _stats.apply_hp_damage(chip_dmg)
		_stats.try_consume_stamina(SoulsCombatConfig.BLOCK_STAMINA_COST, true)
		_flash_timer = 0.12
		if died_from_chip:
			_enter_death_state(attacker.actor_title)
			return SoulsCombatConfig.RESULT_DEATH
		if _stats.add_posture(posture_dmg * SoulsCombatConfig.BLOCK_POSTURE_RATIO):
			_fsm.change_state(STATE_STAGGERED, {}, true)
			show_floating_callout("破防崩溃", Color(1.0, 0.38, 0.28), 1.4)
		else:
			show_floating_callout("格挡 -%d" % int(chip_dmg), Color(0.52, 0.84, 1.0), 1.1)
		combat_event_triggered.emit(
			SoulsCombatConfig.RESULT_BLOCKED,
			"[color=#6eb8ff][举盾格挡][/color] %s 挡下斩击 (-%d HP)" % [
				_stats.actor_title,
				int(chip_dmg),
			]
		)
		return SoulsCombatConfig.RESULT_BLOCKED

	# 4. 直接命中（或红光危技强制破盾）
	var died_from_hit: bool = _stats.apply_hp_damage(raw_damage)
	_flash_timer = 0.22
	apply_hitstop(0.055)
	attacker.apply_hitstop(0.055)
	if died_from_hit:
		_enter_death_state(attacker.actor_title)
		return SoulsCombatConfig.RESULT_DEATH

	if _stats.add_posture(posture_dmg):
		_stats.is_hyper_armor_active = false
		_fsm.change_state(STATE_STAGGERED, {}, true)
		show_floating_callout("架势崩溃 -%d" % int(raw_damage), Color(1.0, 0.30, 0.25), 1.5)
	elif _stats.is_hyper_armor_active:
		show_floating_callout("霸体 -%d" % int(raw_damage), Color(1.0, 0.72, 0.22), 1.2)
		combat_event_triggered.emit(
			SoulsCombatConfig.RESULT_HYPER_ARMOR_TANKED,
			"[color=#ffb833][霸体硬抗][/color] %s 霸体承伤 -%.0f HP" % [
				_stats.actor_title,
				raw_damage,
			]
		)
		return SoulsCombatConfig.RESULT_HYPER_ARMOR_TANKED
	else:
		_fsm.change_state(STATE_HIT_STUN, {}, true)
		show_floating_callout("-%d HP" % int(raw_damage), Color(1.0, 0.42, 0.42), 1.1)

	combat_event_triggered.emit(
		SoulsCombatConfig.RESULT_HIT,
		"[color=#ff6b6b][命中][/color] [%s] -> %s (-%.0f HP)" % [
			attacker.actor_title,
			_stats.actor_title,
			raw_damage,
		]
	)
	return SoulsCombatConfig.RESULT_HIT


func apply_parry_deflection(posture_surge: float) -> void:
	_flash_timer = 0.25
	_stats.combo_total_steps = 1
	_stats.combo_step_index = 1
	post_attack_pacing_timer = 2.4
	if _stats.add_posture(posture_surge):
		_fsm.change_state(STATE_STAGGERED, {}, true)
		show_floating_callout("架势崩溃", Color(1.0, 0.32, 0.22), 1.6)
	else:
		_fsm.change_state(STATE_HIT_STUN, {}, true)
		show_floating_callout("被弹反 +%d架势" % int(posture_surge), Color(1.0, 0.78, 0.28), 1.2)


func receive_riposte_execution(execution_dmg: float) -> void:
	var died_from_riposte: bool = _stats.apply_hp_damage(execution_dmg)
	_stats.posture = 0.0
	_stats.combo_total_steps = 1
	_stats.combo_step_index = 1
	post_attack_pacing_timer = 2.8
	_flash_timer = 0.35
	combat_event_triggered.emit(
		SoulsCombatConfig.RESULT_RIPOSTE,
		"[color=#ff9e3d][致命处决][/color] 重创 [%s] (-%.0f HP)" % [
			_stats.actor_title,
			execution_dmg,
		]
	)
	if died_from_riposte:
		_enter_death_state("致命处决")
		return
	_fsm.change_state(STATE_HIT_STUN, {}, true)
	show_floating_callout("致命处决 -%.0f" % execution_dmg, Color(1.0, 0.25, 0.20), 1.6)


func _enter_death_state(killer_title: String) -> void:
	move_dir_3d = Vector3.ZERO
	_stats.wants_hold_shield = false
	_stats.clear_defense_flags()
	_fsm.change_state(STATE_DEAD, {}, true)
	show_floating_callout("陨落", Color(1.0, 0.22, 0.22), 2.4)
	combat_event_triggered.emit(
		SoulsCombatConfig.RESULT_DEATH,
		"[b][color=#ff5252][陨落][/color] [%s] 被 [%s] 击败[/b]" % [
			_stats.actor_title,
			killer_title,
		]
	)

#endregion


#region 3D 坐标钳制、朝向更新与帧驱动

func _clamp_to_arena_circle(pos: Vector3) -> Vector3:
	var flat: Vector2 = Vector2(pos.x, pos.z)
	if flat.length() > arena_radius:
		flat = flat.normalized() * arena_radius
	return Vector3(flat.x, 0.0, flat.y)


func _snap_face_towards(target_pos: Vector3) -> void:
	var diff: Vector3 = target_pos - position
	diff.y = 0.0
	if diff.length_squared() > 0.01:
		facing_dir_3d = diff.normalized()
		facing_yaw = atan2(-facing_dir_3d.z, facing_dir_3d.x)


func _smooth_update_facing(delta: float) -> void:
	var cur: StringName = get_current_state_name()
	if cur in [STATE_DEAD, STATE_DODGE, STATE_STAGGERED, STATE_HIT_STUN, STATE_ATTACK_RECOVERY]:
		return

	var desired_dir: Vector3 = Vector3.ZERO
	if (_stats.is_boss or is_lock_strafing or cur == STATE_ATTACK_WINDUP) and target_opponent != null:
		var to_opp: Vector3 = target_opponent.position - position
		to_opp.y = 0.0
		if to_opp.length_squared() > 0.04:
			desired_dir = to_opp.normalized()
	elif move_dir_3d.length_squared() > 0.01:
		desired_dir = move_dir_3d.normalized()

	if desired_dir.length_squared() > 0.01:
		facing_dir_3d = facing_dir_3d.lerp(desired_dir, clampf(delta * 10.0, 0.0, 1.0)).normalized()
		var target_yaw: float = atan2(-facing_dir_3d.z, facing_dir_3d.x)
		facing_yaw = lerp_angle(facing_yaw, target_yaw, clampf(delta * 12.0, 0.0, 1.0))


func apply_hitstop(duration: float = 0.055) -> void:
	_hitstop_timer = maxf(_hitstop_timer, duration)


func tick_actor(delta: float) -> void:
	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(0.0, _hitstop_timer - delta)
		if _rig_3d != null:
			_rig_3d.update_pose(
				0.0,
				get_current_state_name(),
				state_elapsed,
				facing_yaw,
				_stats.is_invincible_iframe,
				_stats.is_unblockable_attack,
				_stats.windup_duration,
				_flash_timer,
				_stats.combo_step_index,
				_stats.is_hyper_armor_active
			)
		return

	state_elapsed += delta
	if post_attack_pacing_timer > 0.0:
		post_attack_pacing_timer = maxf(0.0, post_attack_pacing_timer - delta)
	_smooth_update_facing(delta)

	var cur_state: StringName = get_current_state_name()
	if not _stats.is_boss and cur_state not in [STATE_ATTACK_WINDUP, STATE_ATTACK_SLASH]:
		if _stats.combo_window_timer > 0.0:
			_stats.combo_window_timer = maxf(0.0, _stats.combo_window_timer - delta)
			if _stats.combo_window_timer <= 0.0 and cur_state in [STATE_IDLE, STATE_MOVE, STATE_BLOCK]:
				_stats.combo_step_index = 1
				_stats.combo_total_steps = 1
				_stats.combo_chain_id = &""
				_stats.attack_tempo_tag = ""
	if cur_state in [STATE_IDLE, STATE_MOVE]:
		_stats.regenerate_idle_or_move(delta)
	elif cur_state == STATE_BLOCK:
		_stats.regenerate_while_blocking(delta)

	if _fsm != null:
		_fsm.update(delta)

	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)

	if _rig_3d != null:
		_rig_3d.update_pose(
			delta,
			get_current_state_name(),
			state_elapsed,
			facing_yaw,
			_stats.is_invincible_iframe,
			_stats.is_unblockable_attack,
			_stats.windup_duration,
			_flash_timer,
			_stats.combo_step_index,
			_stats.is_hyper_armor_active
		)

	if _overhead_hud != null:
		_overhead_hud.tick_hud(
			delta,
			_stats.actor_title,
			get_current_state_name(),
			_stats.is_unblockable_attack,
			_stats.combo_step_index,
			_stats.combo_total_steps,
			_stats.is_hyper_armor_active,
			_stats.attack_tempo_tag
		)

#endregion


#region FSM 10 状态与多段连招状态机

func _build_fsm_and_ast() -> void:
	_fsm = StateMachine.new(self, &"souls_fighter_fsm")
	_fsm.state_changed.connect(func(new_s: StringName, old_s: StringName, _msg: Dictionary) -> void:
		state_changed.emit(old_s, new_s)
	)

	_fsm.add_callable(
		STATE_IDLE,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags()
			if _stats.wants_hold_shield:
				_fsm.change_state(STATE_BLOCK)
			elif move_dir_3d.length_squared() > 0.01:
				_fsm.change_state(STATE_MOVE),
		func(_dt: float) -> void:
			if _stats.wants_hold_shield:
				_fsm.change_state(STATE_BLOCK)
			elif move_dir_3d.length_squared() > 0.01:
				_fsm.change_state(STATE_MOVE),
		Callable(),
		Callable(),
		"待机 (Idle)"
	)

	_fsm.add_callable(
		STATE_MOVE,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags(),
		func(dt: float) -> void:
			if _stats.wants_hold_shield:
				_fsm.change_state(STATE_BLOCK)
				return
			if move_dir_3d.length_squared() <= 0.01:
				_fsm.change_state(STATE_IDLE)
				return
			var step_vec: Vector3 = move_dir_3d.normalized() * _stats.move_speed * dt
			position = _clamp_to_arena_circle(position + step_vec),
		Callable(),
		Callable(),
		"3D 走位 (Move)"
	)

	_fsm.add_callable(
		STATE_DODGE,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags()
			_stats.is_invincible_iframe = true,
		func(dt: float) -> void:
			_stats.is_invincible_iframe = state_elapsed <= SoulsCombatConfig.DODGE_IFRAME_DURATION
			var roll_speed: float = _stats.move_speed * 1.90
			position = _clamp_to_arena_circle(position + dodge_dir_3d * roll_speed * dt)
			if state_elapsed >= SoulsCombatConfig.DODGE_DURATION:
				_stats.is_invincible_iframe = false
				_fsm.change_state(STATE_IDLE),
		func() -> void:
			_stats.is_invincible_iframe = false,
		Callable(),
		"翻滚无敌帧 (Dodge)"
	)

	_fsm.add_callable(
		STATE_PARRY,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags()
			_stats.is_parry_window_active = true,
		func(_dt: float) -> void:
			_stats.is_parry_window_active = state_elapsed <= SoulsCombatConfig.PARRY_WINDOW_DURATION
			if state_elapsed >= SoulsCombatConfig.PARRY_TOTAL_DURATION:
				_stats.is_parry_window_active = false
				if _stats.wants_hold_shield:
					_fsm.change_state(STATE_BLOCK)
				else:
					_fsm.change_state(STATE_IDLE),
		func() -> void:
			_stats.is_parry_window_active = false,
		Callable(),
		"完美弹反 (Parry)"
	)

	_fsm.add_callable(
		STATE_BLOCK,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags()
			_stats.is_block_active = true,
		func(dt: float) -> void:
			_stats.is_block_active = true
			if move_dir_3d.length_squared() > 0.01:
				var slow_step: Vector3 = move_dir_3d.normalized() * (_stats.move_speed * 0.45) * dt
				position = _clamp_to_arena_circle(position + slow_step)
			if not _stats.wants_hold_shield:
				_fsm.change_state(STATE_IDLE),
		func() -> void:
			_stats.is_block_active = false,
		Callable(),
		"举盾格挡 (Block)"
	)

	_fsm.add_callable(
		STATE_ATTACK_WINDUP,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags(false)
			_stats.slash_damage_dealt = false,
		func(dt: float) -> void:
			# 连招蓄力或跳劈期间向目标踏步追击
			if target_opponent != null:
				var to_target: Vector3 = target_opponent.position - position
				to_target.y = 0.0
				var dist: float = to_target.length()
				var lunge_speed: float = (
					_stats.move_speed * 2.45
					if _stats.combo_chain_id == &"boss_leap_combo" and _stats.combo_step_index == 1
					else _stats.move_speed * 0.95
				)
				if dist > 1.75:
					position = _clamp_to_arena_circle(position + to_target.normalized() * lunge_speed * dt)
			if state_elapsed >= _stats.windup_duration:
				_fsm.change_state(STATE_ATTACK_SLASH),
		Callable(),
		Callable(),
		"蓄力前摇 (Windup)"
	)

	_fsm.add_callable(
		STATE_ATTACK_SLASH,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags(false)
			_stats.slash_damage_dealt = false,
		func(_dt: float) -> void:
			if not _stats.slash_damage_dealt and state_elapsed >= 0.05:
				_stats.slash_damage_dealt = true
				_try_deliver_slash_hit()
			if state_elapsed >= _stats.slash_duration:
				# 若存在后续连招段数（且对手仍在合理追击范围内），衔接下一段前摇；否则进入收刀后摇破绽期！
				if _stats.try_advance_next_combo_step() and (_stats.is_boss == false or distance_to_opponent() <= 4.4):
					_fsm.change_state(STATE_ATTACK_WINDUP, {}, true)
				else:
					if _stats.is_boss or _stats.combo_step_index >= _stats.combo_total_steps:
						_stats.combo_step_index = 1
						_stats.combo_total_steps = 1
						_stats.combo_chain_id = &""
					_stats.is_unblockable_attack = false
					_fsm.change_state(STATE_ATTACK_RECOVERY, {}, true),
		func() -> void:
			pass,
		Callable(),
		"挥剑斩击 (Slash)"
	)

	_fsm.add_callable(
		STATE_ATTACK_RECOVERY,
		func() -> void:
			state_elapsed = 0.0
			move_dir_3d = Vector3.ZERO
			_stats.clear_defense_flags()
			_stats.is_unblockable_attack = false,
		func(_dt: float) -> void:
			if state_elapsed >= _stats.recovery_duration:
				if _stats.is_boss:
					post_attack_pacing_timer = 2.8
				_fsm.change_state(STATE_IDLE),
		Callable(),
		Callable(),
		"收刀后摇 (Recovery)"
	)

	_fsm.add_callable(
		STATE_RIPOSTE,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags()
			_stats.is_invincible_iframe = true
			_stats.slash_damage_dealt = false
			show_floating_callout("致命处决", Color(1.0, 0.84, 0.25), 1.2),
		func(_dt: float) -> void:
			if not _stats.slash_damage_dealt and state_elapsed >= SoulsCombatConfig.RIPOSTE_HIT_TIME:
				_stats.slash_damage_dealt = true
				if target_opponent != null:
					target_opponent.receive_riposte_execution(SoulsCombatConfig.RIPOSTE_DAMAGE)
			if state_elapsed >= SoulsCombatConfig.RIPOSTE_DURATION:
				_stats.is_invincible_iframe = false
				_fsm.change_state(STATE_IDLE),
		func() -> void:
			_stats.is_invincible_iframe = false,
		Callable(),
		"致命处决 (Riposte)"
	)

	_fsm.add_callable(
		STATE_HIT_STUN,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags()
			_stats.is_unblockable_attack = false,
		func(dt: float) -> void:
			position = _clamp_to_arena_circle(position - facing_dir_3d * 1.8 * dt)
			if state_elapsed >= SoulsCombatConfig.HIT_STUN_DURATION:
				_fsm.change_state(STATE_IDLE),
		Callable(),
		Callable(),
		"受击硬直 (HitStun)"
	)

	_fsm.add_callable(
		STATE_STAGGERED,
		func() -> void:
			state_elapsed = 0.0
			_stats.clear_defense_flags()
			_stats.is_unblockable_attack = false,
		func(_dt: float) -> void:
			if state_elapsed >= SoulsCombatConfig.STAGGERED_DURATION:
				_stats.posture = 0.0
				_fsm.change_state(STATE_IDLE),
		Callable(),
		Callable(),
		"架势崩溃 (Staggered)"
	)

	_fsm.add_callable(
		STATE_DEAD,
		func() -> void:
			state_elapsed = 0.0
			move_dir_3d = Vector3.ZERO
			_stats.wants_hold_shield = false
			_stats.clear_defense_flags()
			_stats.is_unblockable_attack = false,
		func(_dt: float) -> void:
			move_dir_3d = Vector3.ZERO,
		Callable(),
		Callable(),
		"战败陨落 (Dead)"
	)

	_fsm.add_visual_edge(STATE_IDLE, STATE_MOVE, "WASD")
	_fsm.add_visual_edge(STATE_MOVE, STATE_IDLE, "stop")
	_fsm.add_visual_edge(STATE_IDLE, STATE_DODGE, "Space")
	_fsm.add_visual_edge(STATE_DODGE, STATE_IDLE, "0.42s")
	_fsm.add_visual_edge(STATE_IDLE, STATE_PARRY, "RMB")
	_fsm.add_visual_edge(STATE_PARRY, STATE_BLOCK, "hold")
	_fsm.add_visual_edge(STATE_BLOCK, STATE_IDLE, "release")
	_fsm.add_visual_edge(STATE_IDLE, STATE_ATTACK_WINDUP, "LMB")
	_fsm.add_visual_edge(STATE_ATTACK_WINDUP, STATE_ATTACK_SLASH, "slash")
	_fsm.add_visual_edge(STATE_ATTACK_SLASH, STATE_ATTACK_RECOVERY, "recover")
	_fsm.add_visual_edge(STATE_ATTACK_RECOVERY, STATE_IDLE, "done")
	_fsm.add_visual_edge(STATE_STAGGERED, STATE_IDLE, "recover")
	_fsm.add_visual_edge(STATE_HIT_STUN, STATE_IDLE, "recover")

	_fsm.start(STATE_IDLE)
	_debug_fsm_id = GraphDebugBridge.register(_fsm, self, "%s · FSM" % _stats.actor_title)


func _try_deliver_slash_hit() -> void:
	if target_opponent == null:
		return
	if distance_to_opponent() <= _stats.attack_range:
		target_opponent.receive_melee_strike(
			self,
			_stats.attack_damage,
			_stats.posture_damage,
			_stats.is_unblockable_attack
		)

#endregion
