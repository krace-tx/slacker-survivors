class_name SoulsBossAiController
extends RefCounted

## 深渊铁卫 Boss 3D 享元行为树控制器（位于 src/test/souls_arena/service/，遵循 MSVP 的 `Service` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 默认全自动运行享元行为树 AI，使用流式 [BTBuilder] 编排 Boss 的 9 条 3D 攻防与节奏控制分支：[br]
##    - 状态锁死：`1.架势崩溃/收刀后摇破绽期`；[br]
##    - 反应防御：`2.响应式 3D 闪避无敌帧 (Dodge)`、`3.响应式振刀弹反与举盾格挡 (Parry & Block)`；[br]
##    - 节奏呼吸：`4.连招后撤步与审视对峙 (Pacing Standoff)`（打完连招后主动拉开距离横向审视，绝不无脑死追）；[br]
##    - 多段进攻：`5.远距霸体跳劈二连`、`6.红光霸体旋风二连斩`、`7.霸体快慢刀悬停二连斩`、`8.近身深渊三连狂斩`、`9.中距审视踱步与择机逼近`；[br]
## 2. 将 AST 编译为无状态享元执行树 [BTTree]，每帧将距离、玩家出刀、收刀后摇、对峙计时器写入 [BTBlackboard] 驱动决策。


#region 私有变量

var _boss: SoulsFighterActor = null
var _player: SoulsFighterActor = null
var _bt_graph_def: BTGraphDef = null
var _bt_tree: BTTree = null
var _bt_compiler: BTCompiler = null
var _bt_ctx: BTContext = null
var _strafe_clock: float = 0.0
var _dodge_side_sign: float = 1.0

#endregion


#region 生命周期与构建

func _init(boss: SoulsFighterActor, player: SoulsFighterActor) -> void:
	_boss = boss
	_player = player
	_build_boss_bt_ast_and_compile()


func clear() -> void:
	_boss = null
	_player = null
	_bt_tree = null
	_bt_compiler = null
	_bt_ctx = null
	_bt_graph_def = null


func get_bt_graph_def() -> BTGraphDef:
	return _bt_graph_def


func get_bt_tree() -> BTTree:
	return _bt_tree


func get_bt_compiler() -> BTCompiler:
	return _bt_compiler


func get_blackboard() -> BTBlackboard:
	if _bt_ctx == null:
		return null
	return _bt_ctx.blackboard


func get_active_leaf_id() -> StringName:
	if _bt_ctx == null or _bt_ctx.blackboard == null:
		return SoulsCombatConfig.BT_LEAF_STALK_APPROACH
	return _bt_ctx.blackboard.get_string_name(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_STALK_APPROACH)

#endregion


#region 行为树帧驱动

func tick_ai(delta: float) -> int:
	if _boss == null or _player == null or _bt_tree == null or _bt_ctx == null:
		return BTStatus.Status.FAILURE

	_strafe_clock += delta
	var diff: Vector3 = _player.position - _boss.position
	diff.y = 0.0
	var dist_3d: float = diff.length()

	var player_state: StringName = _player.get_current_state_name()
	var boss_state: StringName = _boss.get_current_state_name()
	var player_is_attacking: bool = player_state in [
		SoulsCombatConfig.STATE_ATTACK_WINDUP,
		SoulsCombatConfig.STATE_ATTACK_SLASH,
	]
	# 注意：当 Boss 处于前摇、挥砍、收刀大后摇（STATE_ATTACK_RECOVERY）、受击或崩溃时，不可闪避或格挡取消！
	var boss_is_busy: bool = boss_state in [
		SoulsCombatConfig.STATE_DEAD,
		SoulsCombatConfig.STATE_ATTACK_WINDUP,
		SoulsCombatConfig.STATE_ATTACK_SLASH,
		SoulsCombatConfig.STATE_ATTACK_RECOVERY,
		SoulsCombatConfig.STATE_RIPOSTE,
		SoulsCombatConfig.STATE_HIT_STUN,
		SoulsCombatConfig.STATE_STAGGERED,
	]
	var is_locked_vuln: bool = boss_state in [
		SoulsCombatConfig.STATE_DEAD,
		SoulsCombatConfig.STATE_STAGGERED,
		SoulsCombatConfig.STATE_ATTACK_RECOVERY,
	]

	_bt_ctx.blackboard.set_var(&"distance_to_player", dist_3d)
	_bt_ctx.blackboard.set_var(&"is_staggered", is_locked_vuln)
	_bt_ctx.blackboard.set_var(&"player_is_attacking", player_is_attacking)
	_bt_ctx.blackboard.set_var(&"boss_is_attacking", boss_is_busy)
	_bt_ctx.blackboard.set_var(&"is_pacing_standoff", _boss.post_attack_pacing_timer > 0.0)
	return _bt_tree.tick(_bt_ctx, delta)

#endregion


#region 构建 Boss 8 分支享元行为树 AST (BTBuilder -> BTGraphDef -> BTTree)

func _build_boss_bt_ast_and_compile() -> void:
	var builder: BTBuilder = BTBuilder.create(&"souls_boss_3d_tactical_bt")

	builder.selector("Boss 3D 攻防与节奏根选择器")

	# 分支 1：架势崩溃跪地或连招收刀大后摇破绽期（最高优先级锁死，暴露给玩家输出/处决）
	builder.sequence("1.破防跪地或收刀后摇破绽", true)
	builder.condition(
		"处于破防或收刀后摇?",
		func(ctx: BTContext) -> bool:
			return ctx.blackboard.get_bool(&"is_staggered", false),
		&"check_staggered"
	)
	builder.action(
		"硬直破绽暴露中",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_STAGGERED)
			if _boss != null:
				_boss.move_dir_3d = Vector3.ZERO
				_boss.cmd_release_shield()
			return BTStatus.Status.RUNNING,
		SoulsCombatConfig.BT_LEAF_STAGGERED
	)
	builder.end()

	# 分支 2：响应式 3D 战术闪避无敌帧（当玩家近身挥剑且 Boss 未处于前后摇时，侧后翻滚规避，冷却 3.2s）
	builder.sequence("2.响应式闪避无敌帧", true)
	builder.condition(
		"玩家近身出刀且可闪避?",
		func(ctx: BTContext) -> bool:
			var dist: float = ctx.blackboard.get_float(&"distance_to_player", 99.0)
			var p_atk: bool = ctx.blackboard.get_bool(&"player_is_attacking", false)
			var b_busy: bool = ctx.blackboard.get_bool(&"boss_is_attacking", false)
			return p_atk and (not b_busy) and dist <= 3.6,
		&"check_evade_dodge"
	)
	builder.cooldown(3.2, "战术闪避冷却 3.2s")
	builder.action(
		"发动 3D 侧闪翻滚 (无敌帧)",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_EVADE_DODGE)
			if _boss == null or _player == null:
				return BTStatus.Status.FAILURE
			_boss.move_dir_3d = Vector3.ZERO
			var cur: StringName = _boss.get_current_state_name()
			if cur == SoulsCombatConfig.STATE_DODGE:
				return BTStatus.Status.SUCCESS
			var to_player: Vector3 = _player.position - _boss.position
			to_player.y = 0.0
			var forward_dir: Vector3 = to_player.normalized() if to_player.length_squared() > 0.01 else Vector3.FORWARD
			var tangent_dir: Vector3 = Vector3(-forward_dir.z, 0.0, forward_dir.x)
			_dodge_side_sign = -_dodge_side_sign
			var evade_dir: Vector3 = (-forward_dir * 0.45 + tangent_dir * _dodge_side_sign * 0.90).normalized()
			if _boss.cmd_dodge_roll(evade_dir, true):
				return BTStatus.Status.SUCCESS
			return BTStatus.Status.FAILURE,
		SoulsCombatConfig.BT_LEAF_EVADE_DODGE
	)
	builder.end()
	builder.end()

	# 分支 3：响应式振刀弹反与举盾格挡（当闪避冷却且玩家近身挥剑时，Boss 振刀弹反或举盾减伤，冷却 2.4s）
	builder.sequence("3.响应式弹反与举盾格挡", true)
	builder.condition(
		"玩家近身出刀且可格挡?",
		func(ctx: BTContext) -> bool:
			var dist: float = ctx.blackboard.get_float(&"distance_to_player", 99.0)
			var p_atk: bool = ctx.blackboard.get_bool(&"player_is_attacking", false)
			var b_busy: bool = ctx.blackboard.get_bool(&"boss_is_attacking", false)
			return p_atk and (not b_busy) and dist <= 3.5,
		&"check_defend_parry"
	)
	builder.cooldown(2.4, "弹反格挡冷却 2.4s")
	builder.action(
		"发动振刀弹反与重盾格挡",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_DEFEND_PARRY_BLOCK)
			if _boss == null or _player == null:
				return BTStatus.Status.FAILURE
			_boss.move_dir_3d = Vector3.ZERO
			var cur: StringName = _boss.get_current_state_name()
			if cur in [SoulsCombatConfig.STATE_PARRY, SoulsCombatConfig.STATE_BLOCK]:
				return BTStatus.Status.SUCCESS
			if _player.state_elapsed >= 0.08 or _player.get_current_state_name() == SoulsCombatConfig.STATE_ATTACK_SLASH:
				if _boss.cmd_parry_or_block():
					return BTStatus.Status.SUCCESS
				return BTStatus.Status.FAILURE
			return BTStatus.Status.RUNNING,
		SoulsCombatConfig.BT_LEAF_DEFEND_PARRY_BLOCK
	)
	builder.end()
	builder.end()

	# 分支 4：连招后战术撤步与审视对峙（打完连招后 2.8s 内绝不莽撞追击，而是后撤拉开距离并横向踱步审视）
	builder.sequence("4.连招后撤步与审视对峙", true)
	builder.condition(
		"处于连招后对峙期?",
		func(ctx: BTContext) -> bool:
			var pacing: bool = ctx.blackboard.get_bool(&"is_pacing_standoff", false)
			var b_busy: bool = ctx.blackboard.get_bool(&"boss_is_attacking", false)
			return pacing and (not b_busy),
		&"check_pacing_standoff"
	)
	builder.action(
		"后撤拉开距离并横向审视",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_PACING_STANDOFF)
			if _boss == null or _player == null:
				return BTStatus.Status.FAILURE
			var to_player: Vector3 = _player.position - _boss.position
			to_player.y = 0.0
			var dist: float = to_player.length()
			var forward_dir: Vector3 = to_player.normalized() if dist > 0.05 else Vector3.FORWARD
			var tangent_dir: Vector3 = Vector3(-forward_dir.z, 0.0, forward_dir.x)
			var side_sign: float = 1.0 if sin(_strafe_clock * 0.75) >= 0.0 else -1.0

			if dist < 3.4:
				# 离玩家太近时：持盾向后缓步撤退并侧移，给玩家喘息与博弈空间
				_boss.wants_hold_shield = true
				_boss.move_dir_3d = (-forward_dir * 0.65 + tangent_dir * side_sign * 0.58).normalized()
			elif dist < 5.6:
				# 中距离：不往前追，仅横向慢步环绕审视
				_boss.wants_hold_shield = false
				_boss.move_dir_3d = (tangent_dir * side_sign * 0.55).normalized()
			else:
				# 远距离：原地横剑驻足凝视
				_boss.wants_hold_shield = false
				_boss.move_dir_3d = Vector3.ZERO
			return BTStatus.Status.RUNNING,
		SoulsCombatConfig.BT_LEAF_PACING_STANDOFF
	)
	builder.end()

	# 分支 5：远距离突进跳劈二连（距离 4.4m ~ 7.0m，冷却 4.8s）
	builder.sequence("5.远距跳劈二连追击", true)
	builder.condition(
		"3D 距离 4.4m ~ 7.0m",
		func(ctx: BTContext) -> bool:
			var dist: float = ctx.blackboard.get_float(&"distance_to_player", 0.0)
			return dist > 4.4 and dist <= 7.0,
		&"check_far_range"
	)
	builder.cooldown(4.8, "跳劈二连冷却 4.8s")
	builder.action(
		"发动突进跳劈二连",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_GAP_CLOSE)
			if _boss == null:
				return BTStatus.Status.FAILURE
			_boss.move_dir_3d = Vector3.ZERO
			var cur: StringName = _boss.get_current_state_name()
			if cur in [SoulsCombatConfig.STATE_ATTACK_WINDUP, SoulsCombatConfig.STATE_ATTACK_SLASH]:
				return BTStatus.Status.RUNNING
			if _boss.cmd_gap_closer_leap():
				return BTStatus.Status.SUCCESS
			return BTStatus.Status.FAILURE,
		SoulsCombatConfig.BT_LEAF_GAP_CLOSE
	)
	builder.end()
	builder.end()

	# 分支 6：近身红光危技旋风二连斩（不可防御，冷却 6.5s）
	builder.sequence("6.红光危技旋风二连斩", true)
	builder.condition(
		"3D 距离 <= 3.3m",
		func(ctx: BTContext) -> bool:
			return ctx.blackboard.get_float(&"distance_to_player", 0.0) <= 3.3,
		&"check_melee_range"
	)
	builder.cooldown(6.5, "红光二连冷却 6.5s")
	builder.action(
		"释放红光旋风二连斩",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_RED_NOVA)
			if _boss == null:
				return BTStatus.Status.FAILURE
			_boss.move_dir_3d = Vector3.ZERO
			var cur: StringName = _boss.get_current_state_name()
			if cur in [SoulsCombatConfig.STATE_ATTACK_WINDUP, SoulsCombatConfig.STATE_ATTACK_SLASH]:
				return BTStatus.Status.RUNNING
			if _boss.cmd_unblockable_red_nova():
				return BTStatus.Status.SUCCESS
			return BTStatus.Status.FAILURE,
		SoulsCombatConfig.BT_LEAF_RED_NOVA
	)
	builder.end()
	builder.end()

	# 分支 7：近身霸体快慢刀悬停二连斩（第 1 刀 1.05s 黄金霸体高举悬停抓早滚 + 第 2 刀 0.20s 极速快刀追斩，冷却 5.2s）
	builder.sequence("7.霸体快慢刀悬停二连斩", true)
	builder.condition(
		"3D 距离 <= 3.3m",
		func(ctx: BTContext) -> bool:
			return ctx.blackboard.get_float(&"distance_to_player", 0.0) <= 3.3,
		&"check_feint_range"
	)
	builder.cooldown(5.2, "快慢刀二连冷却 5.2s")
	builder.action(
		"发动霸体慢刀悬停 + 极速快刀二连",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_DELAYED_FEINT)
			if _boss == null:
				return BTStatus.Status.FAILURE
			_boss.move_dir_3d = Vector3.ZERO
			var cur: StringName = _boss.get_current_state_name()
			if cur in [SoulsCombatConfig.STATE_ATTACK_WINDUP, SoulsCombatConfig.STATE_ATTACK_SLASH]:
				return BTStatus.Status.RUNNING
			if _boss.cmd_delayed_feint_combo():
				return BTStatus.Status.SUCCESS
			return BTStatus.Status.FAILURE,
		SoulsCombatConfig.BT_LEAF_DELAYED_FEINT
	)
	builder.end()
	builder.end()

	# 分支 8：近身深渊三连狂斩（普通起手 -> 极速快刀 -> 霸体慢刀终结劈，冷却 3.0s）
	builder.sequence("8.近身深渊三连狂斩", true)
	builder.condition(
		"3D 距离 <= 3.1m",
		func(ctx: BTContext) -> bool:
			return ctx.blackboard.get_float(&"distance_to_player", 0.0) <= 3.1,
		&"check_slash_range"
	)
	builder.cooldown(3.0, "三连斩冷却 3.0s")
	builder.action(
		"发动深渊三连狂斩",
		func(ctx: BTContext) -> int:
			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_COMBO_SLASH)
			if _boss == null:
				return BTStatus.Status.FAILURE
			_boss.move_dir_3d = Vector3.ZERO
			var cur: StringName = _boss.get_current_state_name()
			if cur in [SoulsCombatConfig.STATE_ATTACK_WINDUP, SoulsCombatConfig.STATE_ATTACK_SLASH]:
				return BTStatus.Status.RUNNING
			if _boss.cmd_light_attack_or_riposte():
				return BTStatus.Status.SUCCESS
			return BTStatus.Status.FAILURE,
		SoulsCombatConfig.BT_LEAF_COMBO_SLASH
	)
	builder.end()
	builder.end()

	# 分支 9：兜底中距审视踱步与择机逼近（交替横向环绕对峙与踏步逼近，避免像僵尸一样直线死追）
	builder.action(
		"9.中距审视踱步与择机逼近",
		func(ctx: BTContext) -> int:
			var cur: StringName = _boss.get_current_state_name() if _boss != null else &""
			if cur in [
				SoulsCombatConfig.STATE_DEAD,
				SoulsCombatConfig.STATE_DODGE,
				SoulsCombatConfig.STATE_PARRY,
				SoulsCombatConfig.STATE_ATTACK_WINDUP,
				SoulsCombatConfig.STATE_ATTACK_SLASH,
				SoulsCombatConfig.STATE_ATTACK_RECOVERY,
				SoulsCombatConfig.STATE_HIT_STUN,
			]:
				_boss.move_dir_3d = Vector3.ZERO
				return BTStatus.Status.RUNNING

			ctx.blackboard.set_var(&"active_leaf_key", SoulsCombatConfig.BT_LEAF_STALK_APPROACH)
			if _boss == null or _player == null:
				return BTStatus.Status.FAILURE

			var to_player: Vector3 = _player.position - _boss.position
			to_player.y = 0.0
			var dist: float = to_player.length()
			var forward_dir: Vector3 = to_player.normalized() if dist > 0.05 else Vector3.FORWARD
			var tangent_dir: Vector3 = Vector3(-forward_dir.z, 0.0, forward_dir.x)
			var side_sign: float = 1.0 if sin(_strafe_clock * 0.8) >= 0.0 else -1.0
			var rhythm_wave: float = sin(_strafe_clock * 1.15)

			if dist > 5.2:
				# 远距离：稳步走近玩家
				_boss.wants_hold_shield = false
				_boss.move_dir_3d = (forward_dir * 0.82 + tangent_dir * side_sign * 0.32).normalized()
			elif dist > 2.6:
				# 中距离博弈区：一半时间横向持盾踱步审视（不往前莽），一半时间斜向切入寻机出刀
				if rhythm_wave > 0.15:
					_boss.wants_hold_shield = true
					_boss.move_dir_3d = (tangent_dir * side_sign * 0.68).normalized()
				else:
					_boss.wants_hold_shield = false
					_boss.move_dir_3d = (forward_dir * 0.72 + tangent_dir * side_sign * 0.42).normalized()
			else:
				# 近身对峙：横向侧步观察
				_boss.wants_hold_shield = true
				_boss.move_dir_3d = (tangent_dir * side_sign * 0.62 - forward_dir * 0.20).normalized()
			return BTStatus.Status.RUNNING,
		SoulsCombatConfig.BT_LEAF_STALK_APPROACH
	)

	builder.end()

	_bt_tree = builder.build()
	_bt_graph_def = _bt_tree.get_ast()
	_bt_compiler = builder.get_compiler()
	_bt_ctx = BTContext.new(_boss)

#endregion
