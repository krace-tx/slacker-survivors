class_name MermaidPlaygroundView
extends BaseView

## Mermaid 图蓝图演练场被动视图（挂载于场景 `$UI` 节点，继承 [BaseView]）。[br]
##
## [b]核心职责：[/b][br]
## 1. 仅负责采集声明式 `.tscn` 按钮点击并发射语义信号，零业务逻辑与零 `App.*` 调用；[br]
## 2. 提供纯净的 [method render_state] 与日志渲染接口供 [MermaidPlaygroundPresenter] 驱动。


#region Signals

signal guard_sight_toggle_requested()
signal guard_stun_requested()
signal guard_revert_requested()
signal alpha_damage_requested()
signal alpha_heal_requested()
signal alpha_distance_toggle_requested()
signal bravo_profile_toggle_requested()
signal rerun_verification_requested()

#endregion


#region Node References

@onready var _status_pill_label: Label = %StatusPillLabel as Label
@onready var _rerun_verify_btn: Button = %RerunVerifyBtn as Button

@onready var _guard_info_text: RichTextLabel = %GuardInfoText as RichTextLabel
@onready var _toggle_enemy_btn: Button = %ToggleEnemyBtn as Button
@onready var _trigger_stun_btn: Button = %TriggerStunBtn as Button
@onready var _revert_state_btn: Button = %RevertStateBtn as Button

@onready var _slime_info_text: RichTextLabel = %SlimeInfoText as RichTextLabel
@onready var _alpha_damage_btn: Button = %AlphaDamageBtn as Button
@onready var _alpha_heal_btn: Button = %AlphaHealBtn as Button
@onready var _alpha_dist_btn: Button = %AlphaDistBtn as Button
@onready var _bravo_mode_btn: Button = %BravoModeBtn as Button

@onready var _log_output: RichTextLabel = %LogOutput as RichTextLabel

#endregion


#region Lifecycle

func _ready() -> void:
	super._ready()
	_rerun_verify_btn.pressed.connect(func() -> void: rerun_verification_requested.emit())
	_toggle_enemy_btn.pressed.connect(func() -> void: guard_sight_toggle_requested.emit())
	_trigger_stun_btn.pressed.connect(func() -> void: guard_stun_requested.emit())
	_revert_state_btn.pressed.connect(func() -> void: guard_revert_requested.emit())
	_alpha_damage_btn.pressed.connect(func() -> void: alpha_damage_requested.emit())
	_alpha_heal_btn.pressed.connect(func() -> void: alpha_heal_requested.emit())
	_alpha_dist_btn.pressed.connect(func() -> void: alpha_distance_toggle_requested.emit())
	_bravo_mode_btn.pressed.connect(func() -> void: bravo_profile_toggle_requested.emit())

#endregion


#region Passive Render API

## 根据最新 [MermaidTestState] 刷新状态胶囊、双面板详情与交互按钮文案。
func render_state(state: MermaidTestState) -> void:
	_status_pill_label.text = state.get_status_pill_text()

	_toggle_enemy_btn.text = (
		"👁 视野：已发现敌人 (点击脱离)"
		if state.guard_enemy_visible
		else "👁 视野：安全无敌情 (点击索敌)"
	)
	_revert_state_btn.disabled = state.guard_prev_id.is_empty()
	_alpha_dist_btn.text = (
		"📏 史莱姆A：近距 %.0fm (点击拉远)" % state.alpha_enemy_dist
		if state.alpha_enemy_dist <= 160.0
		else "📏 史莱姆A：远距 %.0fm (点击贴近)" % state.alpha_enemy_dist
	)
	_bravo_mode_btn.text = (
		"🔁 史莱姆B：残血逃生态 (点击切近战)"
		if state.bravo_hp_ratio <= 0.30
		else "🔁 史莱姆B：满血近战态 (点击切残血)"
	)

	var prev_str: String = String(state.guard_prev_id) if not state.guard_prev_id.is_empty() else "无"
	_guard_info_text.text = "\n".join([
		"[color=#7d8899]蓝图资产[/color]  [color=#70bafa]resources/def_fsm_guard_patrol.tres[/color]",
		"[color=#7d8899]代码模板[/color]  [color=#90cdf4]service/guard_fsm_agent.gd[/color]",
		"",
		"[color=#7d8899]当前状态[/color]  [b][color=#68d391]%s[/color][/b]   (驻留 [color=#fbd38d]%.2fs[/color] · 前驱: %s)" % [
			String(state.guard_state_id),
			state.guard_state_time,
			prev_str,
		],
		"[color=#7d8899]索敌条件[/color]  %s" % (
			"[color=#fc8181]enemy_in_sight = true[/color]"
			if state.guard_enemy_visible
			else "[color=#a0aec0]enemy_in_sight = false[/color]"
		),
		"[color=#7d8899]实时动作[/color]  [color=#e2e8f0]%s[/color]" % state.guard_action_desc,
	])

	_slime_info_text.text = "\n".join([
		"[color=#7d8899]蓝图资产[/color]  [color=#70bafa]resources/def_bt_slime_ai.tres[/color]",
		"[color=#7d8899]代码模板[/color]  [color=#90cdf4]service/slime_bt_squad.gd[/color]  [color=#718096](1 棵 BTTree 享元驱动 2 实体)[/color]",
		"",
		"[color=#68d391]● 史莱姆 A[/color]  HP=[color=#fbd38d]%d%%[/color]  敌距=[color=#90cdf4]%.0fm[/color]  [color=#718096](Tick #%d)[/color]" % [
			roundi(state.alpha_hp_ratio * 100.0),
			state.alpha_enemy_dist,
			state.alpha_tick_count,
		],
		"  └─ [color=#e2e8f0]%s[/color]" % state.alpha_action_desc,
		"[color=#f6ad55]● 史莱姆 B[/color]  HP=[color=#fbd38d]%d%%[/color]  敌距=[color=#90cdf4]%.0fm[/color]  [color=#718096](Tick #%d)[/color]" % [
			roundi(state.bravo_hp_ratio * 100.0),
			state.bravo_enemy_dist,
			state.bravo_tick_count,
		],
		"  └─ [color=#e2e8f0]%s[/color]" % state.bravo_action_desc,
	])


## 重新渲染完整日志列表。
func render_all_logs(lines: PackedStringArray) -> void:
	_log_output.clear()
	for line: String in lines:
		_log_output.append_text(line + "\n")


## 增量追加单行日志。
func append_log_line(bbcode_line: String) -> void:
	_log_output.append_text(bbcode_line + "\n")

#endregion
