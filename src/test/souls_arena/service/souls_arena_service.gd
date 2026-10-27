class_name SoulsArenaService
extends RefCounted

## 3D 魂系演练场业务编排服务（位于 src/test/souls_arena/service/，遵循 MSVP 的 `Service` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 组合并调度 [SoulsBossAiController]（Boss 8 分支享元行为树）、[SoulsSoundService]（程序化物理建模音效与氛围音乐）与 [SoulsVerificationRunner]（6 项契约自检）；[br]
## 2. 维护对局胜负判定（玩家击败 Boss 触发 `MATCH_VICTORY` 薪王讨伐成功，玩家生命归零触发 `MATCH_DEFEAT` 灰烬陨落）；[br]
## 3. 维护 3D 圆形竞技场内双角色碰撞分离、视角锁定状态切换与两个独立弹窗状态同步。


#region 信号定义

signal combat_banner_triggered(bbcode_text: String)
signal camera_shake_requested(intensity: float, duration: float, fov_kick: float)

#endregion


#region 常量与私有变量

const PLAYER_SPAWN_POS: Vector3 = Vector3(0.0, 0.0, 4.2)
const BOSS_SPAWN_POS: Vector3 = Vector3(0.0, 0.0, -4.2)

var _state: SoulsArenaState = null
var _player: SoulsFighterActor = null
var _boss: SoulsFighterActor = null
var _boss_ai: SoulsBossAiController = null
var _sound_service: SoulsSoundService = null
var _is_verifying: bool = false

#endregion


#region 生命周期

func _init(
	state: SoulsArenaState,
	player: SoulsFighterActor,
	boss: SoulsFighterActor,
	boss_ai: SoulsBossAiController
) -> void:
	_state = state
	_player = player
	_boss = boss
	_boss_ai = boss_ai
	_sound_service = SoulsSoundService.new()

	if _player != null:
		_player.combat_event_triggered.connect(_on_actor_combat_event)
		_player.state_changed.connect(_on_player_state_changed)
	if _boss != null:
		_boss.combat_event_triggered.connect(_on_actor_combat_event)
		_boss.state_changed.connect(_on_boss_state_changed)


func cleanup_on_exit() -> void:
	if _player != null:
		if _player.combat_event_triggered.is_connected(_on_actor_combat_event):
			_player.combat_event_triggered.disconnect(_on_actor_combat_event)
		if _player.state_changed.is_connected(_on_player_state_changed):
			_player.state_changed.disconnect(_on_player_state_changed)
	if _boss != null:
		if _boss.combat_event_triggered.is_connected(_on_actor_combat_event):
			_boss.combat_event_triggered.disconnect(_on_actor_combat_event)
		if _boss.state_changed.is_connected(_on_boss_state_changed):
			_boss.state_changed.disconnect(_on_boss_state_changed)
	if _sound_service != null:
		_sound_service.cleanup()
		_sound_service = null
	if _boss_ai != null:
		_boss_ai.clear()
		_boss_ai = null
	_player = null
	_boss = null
	_state = null

#endregion


#region 视角锁定、弹窗开关与舞台重置

func toggle_lock_on() -> bool:
	if _state == null:
		return false
	_state.is_locked_on = not _state.is_locked_on
	if _player != null:
		_player.is_lock_strafing = _state.is_locked_on
	if _sound_service != null:
		_sound_service.play_lock_on_toggle(_state.is_locked_on)
	var status_str: String = "开启" if _state.is_locked_on else "自由"
	_state.append_log("[color=#ffd875][锁定][/color] 视角切换为: [b]%s[/b]" % status_str)
	_state.state_changed.emit()
	return _state.is_locked_on


func set_keybind_help_open(open: bool) -> void:
	if _state == null:
		return
	_state.is_keybind_help_open = open
	if open:
		_state.is_blueprint_open = false
	if _sound_service != null:
		_sound_service.play_lock_on_toggle(open)
	_state.state_changed.emit()


func set_blueprint_open(open: bool) -> void:
	if _state == null:
		return
	_state.is_blueprint_open = open
	if open:
		_state.is_keybind_help_open = false
	if _sound_service != null:
		_sound_service.play_lock_on_toggle(open)
	_state.state_changed.emit()


func reset_arena_positions() -> void:
	if _player == null or _boss == null or _state == null:
		return
	_state.match_result = SoulsCombatConfig.MATCH_ONGOING
	_player.reset_combat_state(PLAYER_SPAWN_POS)
	_boss.reset_combat_state(BOSS_SPAWN_POS)
	if _sound_service != null:
		_sound_service.play_lock_on_toggle(true)
	_sync_state_snapshot()
	_state.append_log("[color=#9ec5ff][重置][/color] 双方状态已恢复并归位")
	combat_banner_triggered.emit("[b][color=#9ec5ff]对局已重置[/color][/b]")

#endregion


#region 玩家手动 3D 动作触发入口

func player_trigger_attack_or_riposte() -> void:
	if _player != null and _is_match_ongoing():
		_player.cmd_light_attack_or_riposte()


func player_trigger_parry() -> void:
	if _player != null and _is_match_ongoing():
		_player.cmd_parry_or_block()


func player_release_shield() -> void:
	if _player != null:
		_player.cmd_release_shield()


func player_trigger_dodge(custom_dir_3d: Vector3 = Vector3.ZERO) -> void:
	if _player != null and _is_match_ongoing():
		_player.cmd_dodge_roll(custom_dir_3d)


func player_toggle_hold_shield() -> void:
	if _player == null or not _is_match_ongoing():
		return
	if _player.wants_hold_shield:
		_player.cmd_release_shield()
	else:
		_player.wants_hold_shield = true
		_player.get_fsm().change_state(SoulsCombatConfig.STATE_BLOCK)


func _is_match_ongoing() -> bool:
	return _state != null and _state.match_result == SoulsCombatConfig.MATCH_ONGOING

#endregion


#region 3D 帧主循环与契约自检委派

func tick_arena(delta: float, manual_move_dir_3d: Vector3) -> void:
	if _player == null or _boss == null or _state == null:
		return

	# 若任意弹窗打开，暂停角色移动输入但保持状态同步
	if _state.is_keybind_help_open or _state.is_blueprint_open:
		_player.move_dir_3d = Vector3.ZERO
		_boss.move_dir_3d = Vector3.ZERO
		_sync_state_snapshot()
		return

	# 若对局已分出胜负（胜利或失败），停止移动与 AI 决策，仅驱动倒地骨骼动画
	if _state.match_result != SoulsCombatConfig.MATCH_ONGOING:
		_player.move_dir_3d = Vector3.ZERO
		_boss.move_dir_3d = Vector3.ZERO
		_player.tick_actor(delta)
		_boss.tick_actor(delta)
		_sync_state_snapshot()
		return

	_player.is_lock_strafing = _state.is_locked_on
	_player.move_dir_3d = manual_move_dir_3d

	if _boss_ai != null:
		_boss_ai.tick_ai(delta)

	_player.tick_actor(delta)
	_boss.tick_actor(delta)

	# 3D XZ 平面圆柱体碰撞分离与圆形场地半径约束
	var min_sep: float = 1.30
	var diff: Vector3 = _boss.position - _player.position
	diff.y = 0.0
	var dist: float = diff.length()
	if dist < min_sep:
		var push_dir: Vector3 = diff / maxf(dist, 0.001) if dist > 0.001 else Vector3.FORWARD
		var push: float = (min_sep - dist) * 0.5
		_player.position -= push_dir * push
		_boss.position += push_dir * push
		_clamp_to_arena(_player)
		_clamp_to_arena(_boss)

	_evaluate_match_victory_or_defeat()
	_sync_state_snapshot()


func _evaluate_match_victory_or_defeat() -> void:
	if _is_verifying or _state == null or _state.match_result != SoulsCombatConfig.MATCH_ONGOING:
		return
	if _boss.hp <= 0.0 or _boss.get_current_state_name() == SoulsCombatConfig.STATE_DEAD:
		_state.match_result = SoulsCombatConfig.MATCH_VICTORY
		_player.move_dir_3d = Vector3.ZERO
		_boss.move_dir_3d = Vector3.ZERO
		if _sound_service != null:
			_sound_service.play_victory_fanfare()
		_state.append_log("[b][color=#ffe066]【讨伐成功 HEIR OF FIRE DESTROYED】深渊铁卫 · 玛尔斯已被击败！[/color][/b]")
	elif _player.hp <= 0.0 or _player.get_current_state_name() == SoulsCombatConfig.STATE_DEAD:
		_state.match_result = SoulsCombatConfig.MATCH_DEFEAT
		_player.move_dir_3d = Vector3.ZERO
		_boss.move_dir_3d = Vector3.ZERO
		if _sound_service != null:
			_sound_service.play_defeat_toll()
		_state.append_log("[b][color=#ff5252]【灰烬陨落 YOU DIED】你在深渊铁卫的巨剑下力竭倒下...[/color][/b]")


func _clamp_to_arena(actor: SoulsFighterActor) -> void:
	var planar := Vector2(actor.position.x, actor.position.z)
	if planar.length() > actor.arena_radius:
		planar = planar.normalized() * actor.arena_radius
		actor.position.x = planar.x
		actor.position.z = planar.y


func run_verification_suite() -> void:
	_is_verifying = true
	SoulsVerificationRunner.run_all(_state, _player, _boss, _boss_ai)
	_state.match_result = SoulsCombatConfig.MATCH_ONGOING
	_is_verifying = false
	if _sound_service != null:
		_sound_service.start_arena_bgm()
	_sync_state_snapshot()


func _sync_state_snapshot() -> void:
	if _state == null or _player == null or _boss == null:
		return
	_state.player_hp = _player.hp
	_state.player_max_hp = _player.max_hp
	_state.player_stamina = _player.stamina
	_state.player_max_stamina = _player.max_stamina
	_state.player_posture = _player.posture
	_state.player_max_posture = _player.max_posture
	_state.player_fsm_state = _player.get_current_state_name()
	_state.player_holding_shield = _player.wants_hold_shield
	_state.player_combo_step = _player.combo_step_index
	_state.player_combo_total = _player.combo_total_steps
	_state.player_hyper_armor = _player.is_hyper_armor_active
	_state.player_tempo_tag = _player.attack_tempo_tag

	_state.boss_hp = _boss.hp
	_state.boss_max_hp = _boss.max_hp
	_state.boss_posture = _boss.posture
	_state.boss_max_posture = _boss.max_posture
	_state.boss_fsm_state = _boss.get_current_state_name()
	_state.boss_combo_step = _boss.combo_step_index
	_state.boss_combo_total = _boss.combo_total_steps
	_state.boss_hyper_armor = _boss.is_hyper_armor_active
	_state.boss_tempo_tag = _boss.attack_tempo_tag
	_state.boss_unblockable_warning = (
		_boss.get_current_state_name() == SoulsCombatConfig.STATE_ATTACK_WINDUP
		and _boss.is_unblockable_attack
	)
	if _boss_ai != null:
		var leaf: StringName = _boss_ai.get_active_leaf_id()
		if not leaf.is_empty():
			_state.boss_bt_leaf = leaf

	_state.state_changed.emit()


func _on_player_state_changed(_old_state: StringName, new_state: StringName) -> void:
	if _is_verifying or _sound_service == null or _player == null:
		return
	_trigger_actor_state_sfx(_player, new_state)


func _on_boss_state_changed(_old_state: StringName, new_state: StringName) -> void:
	if _is_verifying or _sound_service == null or _boss == null:
		return
	_trigger_actor_state_sfx(_boss, new_state)


func _trigger_actor_state_sfx(actor: SoulsFighterActor, new_state: StringName) -> void:
	match new_state:
		SoulsCombatConfig.STATE_DODGE:
			_sound_service.play_dodge_roll(actor.is_boss_actor)
		SoulsCombatConfig.STATE_PARRY:
			_sound_service.play_shield_raise(actor.is_boss_actor)
		SoulsCombatConfig.STATE_ATTACK_WINDUP:
			if actor.is_unblockable_attack:
				_sound_service.play_unblockable_danger_warning()
		SoulsCombatConfig.STATE_ATTACK_SLASH:
			_sound_service.play_sword_swing(actor.is_boss_actor, actor.combo_step_index)
		SoulsCombatConfig.STATE_STAGGERED:
			_sound_service.play_posture_break()


func _on_actor_combat_event(event_code: StringName, detail_bbcode: String) -> void:
	if _is_verifying:
		return
	if _state != null:
		_state.append_log(detail_bbcode)
	match event_code:
		SoulsCombatConfig.RESULT_PARRIED:
			if _sound_service != null:
				_sound_service.play_parry_clang()
			camera_shake_requested.emit(0.24, 0.25, -4.0)
			combat_banner_triggered.emit("[b][color=#ffe066]精准弹反  ·  架势反震[/color][/b]")
		SoulsCombatConfig.RESULT_BLOCKED:
			if _sound_service != null:
				_sound_service.play_shield_block()
			camera_shake_requested.emit(0.10, 0.14, -1.2)
		SoulsCombatConfig.RESULT_RIPOSTE:
			if _sound_service != null:
				_sound_service.play_riposte_execution()
			camera_shake_requested.emit(0.32, 0.34, -5.5)
			combat_banner_triggered.emit("[b][color=#ff9248]致命处决[/color][/b]")
		SoulsCombatConfig.RESULT_DODGED:
			if _sound_service != null:
				_sound_service.play_iframe_evade_chime()
			camera_shake_requested.emit(0.06, 0.10, 2.2)
			combat_banner_triggered.emit("[b][color=#7ce8ff]无敌闪避[/color][/b]")
		SoulsCombatConfig.RESULT_HIT:
			if _sound_service != null:
				_sound_service.play_melee_hit()
			camera_shake_requested.emit(0.16, 0.18, -2.5)
		SoulsCombatConfig.RESULT_HYPER_ARMOR_TANKED:
			if _sound_service != null:
				_sound_service.play_hyper_armor_tank()
			camera_shake_requested.emit(0.20, 0.20, -2.8)
			combat_banner_triggered.emit("[b][color=#ffae42]黄金霸体硬抗[/color][/b]")

#endregion
