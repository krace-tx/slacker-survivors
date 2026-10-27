class_name MermaidTestService
extends RefCounted

## Mermaid 图蓝图演练场领域编排与契约自检服务（位于 `src/test/mermaid_graph/service/`，遵循 MSVP `Service` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 装配并驱动 [GuardFsmAgent] 与 [SlimeBtSquad] 两大标准蓝图示例；[br]
## 2. 将实时运行快照同步至 [MermaidTestState]，并记录关键状态流转日志；[br]
## 3. 执行 5 项端到端蓝图协议与享元行为树契约验证（[method run_verification_suite]）。


#region Constants & Blueprint Resources

const _LOG_TAG: String = "MermaidGraphTest"

const _GUARD_FSM_BLUEPRINT: FsmGraphDef = preload("res://src/test/mermaid_graph/resources/def_fsm_guard_patrol.tres")
const _SLIME_BT_BLUEPRINT: BTGraphDef = preload("res://src/test/mermaid_graph/resources/def_bt_slime_ai.tres")

#endregion


#region Private Fields

var _state: MermaidTestState = null
var _guard_agent: GuardFsmAgent = null
var _slime_squad: SlimeBtSquad = null

#endregion


#region Lifecycle

func _init(state: MermaidTestState) -> void:
	_state = state
	_guard_agent = GuardFsmAgent.new()
	_slime_squad = SlimeBtSquad.new()


## 初始化两大蓝图代理并连接领域流转事件。
func initialize(host_owner: Object) -> Result:
	_guard_agent.transition_occurred.connect(_on_guard_transition_occurred)
	_slime_squad.action_executed.connect(_on_slime_action_executed)

	var fsm_res: Result = _guard_agent.setup(host_owner, _GUARD_FSM_BLUEPRINT)
	if fsm_res.is_err():
		return fsm_res

	var bt_res: Result = _slime_squad.setup(host_owner, _SLIME_BT_BLUEPRINT)
	if bt_res.is_err():
		return bt_res

	# 首帧预热一次 BT 评估，使初始分支状态立即可读
	_slime_squad.tick(0.016)
	sync_live_state()
	return Result.ok(self)


## 每帧推进 FSM 与享元 BT，并同步界面读数。
func tick(delta: float) -> void:
	_guard_agent.tick(delta)
	_slime_squad.tick(delta)
	sync_live_state()


## 退出场景时解绑信号并注销所有调试器会话。
func cleanup_on_exit() -> void:
	if _guard_agent != null:
		if _guard_agent.transition_occurred.is_connected(_on_guard_transition_occurred):
			_guard_agent.transition_occurred.disconnect(_on_guard_transition_occurred)
		_guard_agent.dispose()
	if _slime_squad != null:
		if _slime_squad.action_executed.is_connected(_on_slime_action_executed):
			_slime_squad.action_executed.disconnect(_on_slime_action_executed)
		_slime_squad.dispose()

#endregion


#region Interactive Sandbox Actions

func toggle_guard_enemy_sight() -> void:
	var now_visible: bool = _guard_agent.toggle_enemy_sight()
	_state.append_log(
		"👁 [守卫输入] 切换视野 -> [b][color=%s]enemy_in_sight = %s[/color][/b]" % [
			"#fc8181" if now_visible else "#a0aec0",
			str(now_visible),
		]
	)
	sync_live_state()


func trigger_guard_hit_stun() -> void:
	_guard_agent.request_hit_stun()
	_state.append_log("⚡ [守卫输入] 注入全局重击打断信号 [b]* -> stun[/b]")


func revert_guard_previous_state() -> void:
	if _guard_agent.revert_previous_state():
		_state.append_log("↩ [守卫输入] 调用 [b]revert_to_previous()[/b] 回退至前驱状态")
		sync_live_state()


func damage_slime_alpha() -> void:
	var hp: float = _slime_squad.damage_alpha(0.35)
	_state.append_log("🗡 [史莱姆A] 受到伤害 -> [b]hp_ratio = %.2f[/b]" % hp)
	sync_live_state()


func heal_slime_alpha() -> void:
	var hp: float = _slime_squad.heal_alpha_full()
	_state.append_log("💚 [史莱姆A] 恢复生命 -> [b]hp_ratio = %.2f[/b]" % hp)
	sync_live_state()


func toggle_slime_alpha_distance() -> void:
	var dist: float = _slime_squad.toggle_alpha_distance()
	_state.append_log("📏 [史莱姆A] 调整敌距 -> [b]enemy_dist = %.0fm[/b]" % dist)
	sync_live_state()


func toggle_slime_bravo_profile() -> void:
	var is_melee_now: bool = _slime_squad.toggle_bravo_profile()
	_state.append_log(
		"🔁 [史莱姆B] 切换战术档案 -> [b]%s[/b]" % (
			"满血近战态 (HP=95%, 敌距=120m)" if is_melee_now else "残血逃生态 (HP=22%, 敌距=240m)"
		)
	)
	sync_live_state()

#endregion


#region Automated Contract Verification Suite (5 Cases)

## 执行 5 项蓝图协议、源码锚点与享元行为树契约验证。
func run_verification_suite(reset_profiles: bool = false) -> bool:
	if reset_profiles and _slime_squad != null:
		_slime_squad.reset_to_default_profiles()
		_slime_squad.tick(0.016)
	_state.clear_logs()
	_state.append_log("[b][color=#63b3ed]=== 开始执行 Mermaid 蓝图 × FSM / BT 契约自检 (共 5 项) ===[/color][/b]")

	var fsm: StateMachine = _guard_agent.get_fsm()
	var fsm_ir: Dictionary = fsm.get_ast().to_mermaid_ir() if fsm != null else {}
	var case_1_ok: bool = (
		str(fsm_ir.get("schema", "")) == "fsm"
		and (fsm_ir.get("nodes", []) as Array).size() == 4
		and (fsm_ir.get("edges", []) as Array).size() == 7
	)
	_record_assertion(case_1_ok, "CASE 1: FsmGraphDef (.tres) 标准图 IR 导出完整 (4 状态 / 7 转换边)")

	var idle_def: FsmStateDef = fsm.get_ast().find_state_def(&"idle") if fsm != null else null
	var case_2_ok: bool = (
		idle_def != null
		and (not OS.is_debug_build() or (idle_def.debug_source_file.ends_with("guard_fsm_agent.gd") and idle_def.debug_source_line > 0))
	)
	_record_assertion(case_2_ok, "CASE 2: StateMachine 编译挂载与 guard_fsm_agent.gd 源码行号锚定正常")

	var tree: BTTree = _slime_squad.get_shared_tree()
	var bt_ir: Dictionary = tree.get_ast().to_mermaid_ir() if tree != null else {}
	var case_3_ok: bool = (
		str(bt_ir.get("schema", "")) == "bt"
		and (bt_ir.get("nodes", []) as Array).size() == 11
	)
	_record_assertion(case_3_ok, "CASE 3: BTGraphDef (.tres) 树形拓扑编译完整 (11 节点 / Selector+Sequence+Cooldown+Wait)")

	var ctx_a: BTContext = _slime_squad.get_alpha_context()
	var ctx_b: BTContext = _slime_squad.get_bravo_context()
	var case_4_ok: bool = (
		tree != null
		and ctx_a != null
		and ctx_b != null
		and ctx_a != ctx_b
		and not is_equal_approx(ctx_a.blackboard.get_float(&"hp_ratio"), ctx_b.blackboard.get_float(&"hp_ratio"))
	)
	_record_assertion(case_4_ok, "CASE 4: Flyweight 享元单树驱动双独立黑板实例 (Alpha & Bravo) 零串扰")

	var case_5_ok: bool = (
		ctx_b != null
		and ctx_b.get_active_leaf_title() == "反向逃跑回血"
	)
	_record_assertion(case_5_ok, "CASE 5: 黑板声明式条件分流准确 (残血 Bravo 自动命中『反向逃跑回血』分支)")

	var summary: String = "=== 自检完成：%d 项通过，%d 项失败 ===" % [_state.passed_cases, _state.failed_cases]
	if _state.failed_cases == 0:
		_state.append_log("[b][color=#68d391]%s[/color][/b]" % summary)
		App.logger.info(_LOG_TAG, summary)
	else:
		_state.append_log("[b][color=#fc8181]%s[/color][/b]" % summary)
		App.logger.error(_LOG_TAG, summary)

	sync_live_state()
	return _state.failed_cases == 0


func sync_live_state() -> void:
	var fsm: StateMachine = _guard_agent.get_fsm()
	if fsm != null:
		_state.guard_state_id = fsm.get_current_state_id()
		_state.guard_prev_id = fsm.get_previous_state_id()
		_state.guard_state_time = fsm.get_state_time()
		_state.guard_enemy_visible = _guard_agent.enemy_visible
		_state.guard_action_desc = _guard_agent.action_summary

	var ctx_a: BTContext = _slime_squad.get_alpha_context()
	if ctx_a != null:
		_state.alpha_hp_ratio = ctx_a.blackboard.get_float(&"hp_ratio", 0.85)
		_state.alpha_enemy_dist = ctx_a.blackboard.get_float(&"enemy_dist", 115.0)
		_state.alpha_tick_count = ctx_a.tick_count
		_state.alpha_action_desc = _slime_squad.alpha_summary

	var ctx_b: BTContext = _slime_squad.get_bravo_context()
	if ctx_b != null:
		_state.bravo_hp_ratio = ctx_b.blackboard.get_float(&"hp_ratio", 0.22)
		_state.bravo_enemy_dist = ctx_b.blackboard.get_float(&"enemy_dist", 240.0)
		_state.bravo_tick_count = ctx_b.tick_count
		_state.bravo_action_desc = _slime_squad.bravo_summary

	_state.notify_changed()


func _record_assertion(condition: bool, title: String) -> void:
	if condition:
		_state.passed_cases += 1
		_state.append_log("[color=#68d391][PASS][/color] %s" % title)
		App.logger.info(_LOG_TAG, "[PASS] %s" % title)
	else:
		_state.failed_cases += 1
		_state.append_log("[color=#fc8181][FAIL][/color] %s" % title)
		App.logger.error(_LOG_TAG, "[FAIL] %s" % title)


func _on_guard_transition_occurred(from_state: StringName, to_state: StringName) -> void:
	var from_str: String = String(from_state) if not from_state.is_empty() else "[*]"
	_state.append_log("🛡 [守卫FSM] 状态跃迁：[color=#90cdf4]%s[/color] -> [color=#fbd38d]%s[/color]" % [from_str, String(to_state)])


func _on_slime_action_executed(unit_tag: String, summary: String) -> void:
	_state.append_log("🟢 [史莱姆%s] 触发关键技能：[color=#6ee7b7]%s[/color]" % [unit_tag, summary])

#endregion
