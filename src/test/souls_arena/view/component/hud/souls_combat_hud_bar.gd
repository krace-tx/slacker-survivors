class_name SoulsCombatHudBar
extends Control

## 魂系极简战斗核心 HUD 组件（位于 src/test/souls_arena/view/component/hud/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心设计：[/b][br]
## 1. 节点树、SVG 纹章图标与雕花边框直接定义于 [`souls_combat_hud_bar.tscn`](file:///d:/code/GodotProject/slacker-survivors/src/test/souls_arena/view/component/hud/souls_combat_hud_bar.tscn)，零脚本 `.new()` 动态拼装；[br]
## 2. 驱动白金延迟扣血残影条、三段连击指示器与胜负结算弹层。


#region 信号定义

signal toggle_lock_on_requested()
signal open_keybind_help_requested()
signal open_blueprint_requested()
signal reset_duel_requested()

#endregion


#region 场景唯一节点绑定 (%UniqueName)

@onready var _boss_combo_badge: Label = %BossComboBadge as Label
@onready var _boss_hp_ghost_bar: ProgressBar = %BossHpGhostBar as ProgressBar
@onready var _boss_hp_bar: ProgressBar = %BossHpBar as ProgressBar
@onready var _boss_hp_text: Label = %BossHpText as Label
@onready var _boss_poise_bar: ProgressBar = %BossPoiseBar as ProgressBar
@onready var _boss_state_badge: Label = %BossStateBadge as Label

@onready var _player_hp_ghost_bar: ProgressBar = %PlayerHpGhostBar as ProgressBar
@onready var _player_hp_bar: ProgressBar = %PlayerHpBar as ProgressBar
@onready var _player_hp_text: Label = %PlayerHpText as Label
@onready var _player_stamina_bar: ProgressBar = %PlayerStaminaBar as ProgressBar
@onready var _player_stamina_text: Label = %PlayerStaminaText as Label
@onready var _player_poise_bar: ProgressBar = %PlayerPoiseBar as ProgressBar
@onready var _player_state_badge: Label = %PlayerStateBadge as Label
@onready var _player_combo_pips_label: RichTextLabel = %PlayerComboPipsLabel as RichTextLabel

@onready var _center_banner_panel: PanelContainer = %CenterBannerPanel as PanelContainer
@onready var _center_banner_label: RichTextLabel = %CenterBannerLabel as RichTextLabel
@onready var _riposte_prompt_panel: PanelContainer = %RipostePromptPanel as PanelContainer

@onready var _match_end_overlay: PanelContainer = %MatchEndOverlay as PanelContainer
@onready var _match_end_title: Label = %MatchEndTitle as Label
@onready var _match_end_subtitle: Label = %MatchEndSubtitle as Label
@onready var _match_end_restart_btn: Button = %MatchEndRestartBtn as Button

@onready var _btn_lock_on: Button = %BtnLockOn as Button
@onready var _btn_keybind_help: Button = %BtnKeybindHelp as Button
@onready var _btn_blueprint: Button = %BtnBlueprint as Button
@onready var _btn_reset: Button = %BtnReset as Button

var _banner_fade_timer: float = 0.0
var _boss_ghost_hp_val: float = SoulsCombatConfig.BOSS_MAX_HP
var _player_ghost_hp_val: float = SoulsCombatConfig.PLAYER_MAX_HP

#endregion


#region 生命周期

func _ready() -> void:
	if _btn_lock_on != null:
		_btn_lock_on.pressed.connect(func() -> void: toggle_lock_on_requested.emit())
	if _btn_keybind_help != null:
		_btn_keybind_help.pressed.connect(func() -> void: open_keybind_help_requested.emit())
	if _btn_blueprint != null:
		_btn_blueprint.pressed.connect(func() -> void: open_blueprint_requested.emit())
	if _btn_reset != null:
		_btn_reset.pressed.connect(func() -> void: reset_duel_requested.emit())
	if _match_end_restart_btn != null:
		_match_end_restart_btn.pressed.connect(func() -> void: reset_duel_requested.emit())


func _process(delta: float) -> void:
	if _banner_fade_timer > 0.0:
		_banner_fade_timer = maxf(0.0, _banner_fade_timer - delta)
		if _center_banner_panel != null:
			_center_banner_panel.modulate.a = clampf(_banner_fade_timer / 0.4, 0.0, 1.0)
			if _banner_fade_timer <= 0.0:
				_center_banner_panel.visible = false

	if _boss_hp_ghost_bar != null and _boss_hp_bar != null:
		if _boss_ghost_hp_val > _boss_hp_bar.value:
			_boss_ghost_hp_val = move_toward(_boss_ghost_hp_val, _boss_hp_bar.value, delta * 185.0)
		else:
			_boss_ghost_hp_val = _boss_hp_bar.value
		_boss_hp_ghost_bar.value = _boss_ghost_hp_val

	if _player_hp_ghost_bar != null and _player_hp_bar != null:
		if _player_ghost_hp_val > _player_hp_bar.value:
			_player_ghost_hp_val = move_toward(_player_ghost_hp_val, _player_hp_bar.value, delta * 42.0)
		else:
			_player_ghost_hp_val = _player_hp_bar.value
		_player_hp_ghost_bar.value = _player_ghost_hp_val

#endregion


#region 外部视图刷新 API

func refresh_from_state(state: SoulsArenaState) -> void:
	if state == null or _boss_hp_bar == null:
		return

	# 1. 顶部 Boss 血条与架势槽
	if _boss_hp_ghost_bar != null:
		_boss_hp_ghost_bar.max_value = state.boss_max_hp
		if state.boss_hp >= state.boss_max_hp:
			_boss_ghost_hp_val = state.boss_max_hp
			_boss_hp_ghost_bar.value = state.boss_max_hp
	_boss_hp_bar.max_value = state.boss_max_hp
	_boss_hp_bar.value = state.boss_hp
	_boss_hp_text.text = "%d / %d" % [roundi(state.boss_hp), roundi(state.boss_max_hp)]

	_boss_poise_bar.max_value = state.boss_max_posture
	_boss_poise_bar.value = state.boss_posture
	_boss_state_badge.text = _format_boss_state_text(state)

	if state.boss_combo_total > 1 and state.boss_combo_step > 0:
		_boss_combo_badge.visible = true
		var ha_tag: String = "霸体 · " if state.boss_hyper_armor else ""
		_boss_combo_badge.text = "%s%d/%d" % [ha_tag, state.boss_combo_step, state.boss_combo_total]
	elif state.boss_hyper_armor:
		_boss_combo_badge.visible = true
		_boss_combo_badge.text = "霸体"
	else:
		_boss_combo_badge.visible = false

	# 2. 左下角玩家状态卡
	if _player_hp_ghost_bar != null:
		_player_hp_ghost_bar.max_value = state.player_max_hp
		if state.player_hp >= state.player_max_hp:
			_player_ghost_hp_val = state.player_max_hp
			_player_hp_ghost_bar.value = state.player_max_hp
	_player_hp_bar.max_value = state.player_max_hp
	_player_hp_bar.value = state.player_hp
	_player_hp_text.text = "%d / %d" % [roundi(state.player_hp), roundi(state.player_max_hp)]

	_player_stamina_bar.max_value = state.player_max_stamina
	_player_stamina_bar.value = state.player_stamina
	_player_stamina_text.text = "%d / %d" % [roundi(state.player_stamina), roundi(state.player_max_stamina)]

	_player_poise_bar.max_value = state.player_max_posture
	_player_poise_bar.value = state.player_posture
	_player_state_badge.text = _format_player_state_text(state)
	if _player_combo_pips_label != null:
		_player_combo_pips_label.text = _format_player_combo_pips_bbcode(state)

	# 3. 处决提示
	if _riposte_prompt_panel != null:
		_riposte_prompt_panel.visible = (
			state.match_result == SoulsCombatConfig.MATCH_ONGOING
			and state.boss_fsm_state == SoulsCombatConfig.STATE_STAGGERED
		)

	# 4. 胜负结算弹层
	if _match_end_overlay != null:
		if state.match_result == SoulsCombatConfig.MATCH_VICTORY:
			_match_end_overlay.visible = true
			_match_end_title.text = "薪 王 讨 伐 成 功   ·   HEIR OF FIRE DESTROYED"
			_match_end_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
			_match_end_subtitle.text = "深渊铁卫 · 玛尔斯已化作余烬"
			_match_end_restart_btn.text = "再战一局 [R]"
		elif state.match_result == SoulsCombatConfig.MATCH_DEFEAT:
			_match_end_overlay.visible = true
			_match_end_title.text = "灰 烬 陨 落   ·   Y O U   D I E D"
			_match_end_title.add_theme_color_override("font_color", Color(0.92, 0.22, 0.22))
			_match_end_subtitle.text = "洞悉快慢刀与收刀破绽，再度挑战"
			_match_end_restart_btn.text = "篝火重生 [R]"
		else:
			_match_end_overlay.visible = false

	# 5. 右上角视角锁定按钮
	if _btn_lock_on != null:
		if state.is_locked_on:
			_btn_lock_on.text = "锁定 [Q]"
			_btn_lock_on.modulate = Color(1.0, 0.92, 0.68)
		else:
			_btn_lock_on.text = "自由 [Q]"
			_btn_lock_on.modulate = Color(0.82, 0.86, 0.92)


func show_combat_banner(bbcode_text: String, duration: float = 1.65) -> void:
	if _center_banner_panel == null or _center_banner_label == null:
		return
	_center_banner_label.text = "[center]%s[/center]" % bbcode_text
	_center_banner_panel.visible = true
	_center_banner_panel.modulate.a = 1.0
	_banner_fade_timer = duration

#endregion


#region 状态文案格式化

func _format_boss_state_text(state: SoulsArenaState) -> String:
	if state.boss_unblockable_warning:
		return "危 · 旋风斩"
	if state.boss_fsm_state in [
		SoulsCombatConfig.STATE_ATTACK_WINDUP,
		SoulsCombatConfig.STATE_ATTACK_SLASH,
	]:
		if not state.boss_tempo_tag.is_empty():
			return state.boss_tempo_tag
		return SoulsArenaState.get_bt_leaf_cn_name(state.boss_bt_leaf)
	if state.boss_fsm_state in [
		SoulsCombatConfig.STATE_ATTACK_RECOVERY,
		SoulsCombatConfig.STATE_STAGGERED,
		SoulsCombatConfig.STATE_DODGE,
		SoulsCombatConfig.STATE_PARRY,
		SoulsCombatConfig.STATE_BLOCK,
		SoulsCombatConfig.STATE_DEAD,
	]:
		return SoulsArenaState.get_fsm_state_cn_name(state.boss_fsm_state)
	return SoulsArenaState.get_bt_leaf_cn_name(state.boss_bt_leaf)


func _format_player_state_text(state: SoulsArenaState) -> String:
	var base_name := SoulsArenaState.get_fsm_state_cn_name(state.player_fsm_state)
	if state.player_combo_total > 1 and state.player_fsm_state in [
		SoulsCombatConfig.STATE_ATTACK_WINDUP,
		SoulsCombatConfig.STATE_ATTACK_SLASH,
		SoulsCombatConfig.STATE_ATTACK_RECOVERY,
	]:
		var prefix: String = "霸体 · " if state.player_hyper_armor else ""
		return "%s连击 %d/%d" % [prefix, state.player_combo_step, state.player_combo_total]
	if state.player_holding_shield:
		return "持盾"
	return base_name


func _format_player_combo_pips_bbcode(state: SoulsArenaState) -> String:
	var active_combo: bool = (
		state.player_combo_total > 1
		and state.player_fsm_state in [
			SoulsCombatConfig.STATE_ATTACK_WINDUP,
			SoulsCombatConfig.STATE_ATTACK_SLASH,
			SoulsCombatConfig.STATE_ATTACK_RECOVERY,
		]
	)
	var step: int = state.player_combo_step if active_combo else 0
	var s1 := "[b][color=#66e6ff]I 斜斩[/color][/b]" if step == 1 else "[color=#637085]I 斜斩[/color]"
	var s2 := "[b][color=#66e6ff]II 反手[/color][/b]" if step == 2 else "[color=#637085]II 反手[/color]"
	var s3 := "[b][color=#ffbe3d]III 霸体破军[/color][/b]" if step == 3 else "[color=#637085]III 霸体破军[/color]"
	return "[color=#7b8ba1]连击[/color]   %s  ·  %s  ·  %s" % [s1, s2, s3]

#endregion
