class_name SoulsVerificationRunner
extends RefCounted

## 魂系演练场 6 项自动化契约验证套件执行器（位于 src/test/souls_arena/service/，遵循 MSVP 的 `Service` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 独立执行覆盖 `FSM AST`、`BT 享元黑板隔离` 与 `魂系 3D 四维受击矩阵（无敌帧/弹反/格挡/处决）` 的 6 项契约自检；[br]
## 2. 将测试结果同步输出至 `App.logger` 与 [SoulsArenaState] 日志流，并在自检完成后无损恢复 3D 舞台角色坐标与状态。


#region 常量

const _LOG_TAG: String = "SoulsArenaTest"

#endregion


#region 公开验证入口

static func run_all(
	state: SoulsArenaState,
	player: SoulsFighterActor,
	boss: SoulsFighterActor,
	boss_ai: SoulsBossAiController
) -> void:
	if state == null or player == null or boss == null or boss_ai == null:
		return

	state.passed_cases = 0
	state.total_cases = 6
	state.append_log("[b][color=#7be0ff]=== 内核契约自检 (6 Cases) ===[/color][/b]")

	# Case 1: FSM AST (FsmGraphDef 12 状态) 契约
	var fsm_graph: FsmGraphDef = player.get_fsm_graph_def()
	var case1_ok: bool = (
		fsm_graph != null
		and fsm_graph.states.size() == 12
		and fsm_graph.find_state_def(SoulsCombatConfig.STATE_PARRY) != null
		and fsm_graph.find_state_def(SoulsCombatConfig.STATE_DODGE) != null
		and fsm_graph.find_state_def(SoulsCombatConfig.STATE_ATTACK_RECOVERY) != null
		and fsm_graph.find_state_def(SoulsCombatConfig.STATE_DEAD) != null
	)
	_record_case(state, 1, "FSM 12 状态 AST 拓扑", case1_ok)

	var saved_p_pos: Vector3 = player.position
	var saved_b_pos: Vector3 = boss.position

	# Case 2: BT 享元行为树与多实体黑板隔离
	var bt_tree: BTTree = boss_ai.get_bt_tree()
	var ctx_a: BTContext = BTContext.new(boss, {
		&"is_staggered": true,
		&"distance_to_player": 5.0,
		&"player_is_attacking": false,
		&"boss_is_attacking": false,
		&"is_pacing_standoff": false,
	})
	var ctx_b: BTContext = BTContext.new(boss, {
		&"is_staggered": false,
		&"distance_to_player": 2.2,
		&"player_is_attacking": true,
		&"boss_is_attacking": false,
		&"is_pacing_standoff": false,
	})
	var ctx_c: BTContext = BTContext.new(boss, {
		&"is_staggered": false,
		&"distance_to_player": 3.0,
		&"player_is_attacking": false,
		&"boss_is_attacking": false,
		&"is_pacing_standoff": true,
	})
	var status_a: int = bt_tree.tick(ctx_a, 0.016)
	var status_b: int = bt_tree.tick(ctx_b, 0.016)
	var status_c: int = bt_tree.tick(ctx_c, 0.016)
	var case2_ok: bool = (
		status_a == BTStatus.Status.RUNNING
		and (status_b == BTStatus.Status.SUCCESS or status_b == BTStatus.Status.RUNNING)
		and status_c == BTStatus.Status.RUNNING
		and ctx_a.blackboard.get_string_name(&"active_leaf_key") == SoulsCombatConfig.BT_LEAF_STAGGERED
		and ctx_b.blackboard.get_string_name(&"active_leaf_key") == SoulsCombatConfig.BT_LEAF_EVADE_DODGE
		and ctx_c.blackboard.get_string_name(&"active_leaf_key") == SoulsCombatConfig.BT_LEAF_PACING_STANDOFF
	)
	_record_case(state, 2, "BT 享元树与黑板隔离", case2_ok)

	# Case 3: 3D 翻滚无敌帧规避红光危技
	player.reset_combat_state(Vector3(-1.0, 0.0, 0.0))
	boss.reset_combat_state(Vector3(1.0, 0.0, 0.0))
	player.cmd_dodge_roll(Vector3.LEFT, true)
	var res_dodge: StringName = player.receive_melee_strike(boss, 46.0, 68.0, true)
	var case3_ok: bool = (res_dodge == SoulsCombatConfig.RESULT_DODGED and is_equal_approx(player.hp, player.max_hp))
	_record_case(state, 3, "翻滚无敌帧 (I-Frame)", case3_ok)

	# Case 4: 0.18s 黄金窗口完美弹反
	player.reset_combat_state(Vector3(-1.0, 0.0, 0.0))
	boss.reset_combat_state(Vector3(1.0, 0.0, 0.0))
	player.cmd_parry_or_block()
	var res_parry: StringName = player.receive_melee_strike(boss, 28.0, 32.0, false)
	var case4_ok: bool = (
		res_parry == SoulsCombatConfig.RESULT_PARRIED
		and is_equal_approx(player.hp, player.max_hp)
		and is_equal_approx(boss.posture, SoulsCombatConfig.PARRY_POSTURE_DEFLECTION)
	)
	_record_case(state, 4, "完美弹反与架势反震", case4_ok)

	# Case 5: 格挡破盾、快慢刀霸体与玩家三段连击
	player.reset_combat_state(Vector3(-1.0, 0.0, 0.0))
	boss.reset_combat_state(Vector3(1.0, 0.0, 0.0))
	player.wants_hold_shield = true
	player.get_fsm().change_state(SoulsCombatConfig.STATE_BLOCK, {}, true)
	var res_block: StringName = player.receive_melee_strike(boss, 30.0, 25.0, false)
	var res_guard_break: StringName = player.receive_melee_strike(boss, 40.0, 50.0, true)
	var started_feint: bool = boss.cmd_delayed_feint_combo()
	var res_hyper_armor: StringName = boss.receive_melee_strike(player, 38.0, 25.0, false)
	var boss_kept_windup: bool = (boss.get_current_state_name() == SoulsCombatConfig.STATE_ATTACK_WINDUP)
	player.reset_combat_state(Vector3(-1.0, 0.0, 0.0))
	var p_combo_1: bool = player.cmd_light_attack_or_riposte() and player.combo_step_index == 1
	player.get_fsm().change_state(SoulsCombatConfig.STATE_ATTACK_RECOVERY, {}, true)
	var p_combo_2: bool = player.cmd_light_attack_or_riposte() and player.combo_step_index == 2
	player.get_fsm().change_state(SoulsCombatConfig.STATE_ATTACK_RECOVERY, {}, true)
	var p_combo_3: bool = player.cmd_light_attack_or_riposte() and player.combo_step_index == 3 and player.is_hyper_armor_active
	var case5_ok: bool = (
		res_block == SoulsCombatConfig.RESULT_BLOCKED
		and res_guard_break == SoulsCombatConfig.RESULT_HIT
		and started_feint
		and res_hyper_armor == SoulsCombatConfig.RESULT_HYPER_ARMOR_TANKED
		and boss_kept_windup
		and p_combo_1
		and p_combo_2
		and p_combo_3
	)
	_record_case(state, 5, "快慢刀霸体与玩家三连击", case5_ok)

	# Case 6: 架势崩溃与致命处决
	player.reset_combat_state(Vector3(-1.0, 0.0, 0.0))
	boss.reset_combat_state(Vector3(1.0, 0.0, 0.0))
	boss.force_staggered_state()
	var triggered_riposte: bool = player.cmd_light_attack_or_riposte()
	var entered_riposte: bool = (player.get_current_state_name() == SoulsCombatConfig.STATE_RIPOSTE)
	player.tick_actor(0.25)
	var case6_ok: bool = (
		triggered_riposte
		and entered_riposte
		and is_equal_approx(boss.hp, boss.max_hp - SoulsCombatConfig.RIPOSTE_DAMAGE)
	)
	_record_case(state, 6, "架势崩溃与致命处决", case6_ok)

	player.reset_combat_state(saved_p_pos)
	boss.reset_combat_state(saved_b_pos)

	var summary_text: String = "Summary: %d/%d passed" % [state.passed_cases, state.total_cases]
	if App != null and App.logger != null:
		App.logger.info(_LOG_TAG, summary_text)
	state.append_log("[b][color=#5cff8a][%s] %s[/color][/b]" % [_LOG_TAG, summary_text])


static func _record_case(state: SoulsArenaState, idx: int, title: String, passed: bool) -> void:
	if passed:
		state.passed_cases += 1
		if App != null and App.logger != null:
			App.logger.info(_LOG_TAG, "[PASS] Case %d: %s" % [idx, title])
		state.append_log("[color=#5cff8a][PASS][/color] Case %d · %s" % [idx, title])
	else:
		if App != null and App.logger != null:
			App.logger.error(_LOG_TAG, "[FAIL] Case %d: %s" % [idx, title])
		state.append_log("[color=#ff5c5c][FAIL][/color] Case %d · %s" % [idx, title])

#endregion
