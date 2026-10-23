class_name SoulsArenaState
extends RefCounted

## 3D 魂系演练场响应式状态模型（位于 src/test/souls_arena/model/，遵循 MSVP 的 `Model` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 维护 3D 视角锁定状态（`is_locked_on`）、独立键位教学弹窗开关（`is_keybind_help_open`）与独立 AST 蓝图弹窗开关（`is_blueprint_open`）；[br]
## 2. 镜像同步 3D 玩家骑士与深渊薪王 Boss（1800 HP）的生命值、精力值、架势槽（Posture）、连招段数、FSM 状态及 BT 激活叶节点；[br]
## 3. 维护 6 项自动化契约验证统计与 BBCode 战斗日志流。


#region 信号定义

signal state_changed()
signal log_appended(bbcode_line: String)

#endregion


#region 常量与状态字段

const MAX_LOG_LINES: int = 80

## 视角锁定、对局胜负与两个独立弹窗状态
var is_locked_on: bool = true
var is_keybind_help_open: bool = false
var is_blueprint_open: bool = false
var match_result: int = SoulsCombatConfig.MATCH_ONGOING

## 顶部极简动作提示
var hud_hint_text: String = "[WASD] 3D 走位  ·  [空格] 翻滚无敌帧  ·  [右键/K] 弹反  ·  [左键/J] 挥砍/处决  ·  [Q] 锁定切换  ·  [H] 键位教学  ·  [B] AST 蓝图"
var hud_hint_color: Color = Color(0.76, 0.88, 0.98, 0.92)

## 玩家骑士实时状态快照
var player_hp: float = SoulsCombatConfig.PLAYER_MAX_HP
var player_max_hp: float = SoulsCombatConfig.PLAYER_MAX_HP
var player_stamina: float = 100.0
var player_max_stamina: float = 100.0
var player_posture: float = 0.0
var player_max_posture: float = 100.0
var player_fsm_state: StringName = &"idle"
var player_holding_shield: bool = false
var player_combo_step: int = 1
var player_combo_total: int = 1
var player_hyper_armor: bool = false
var player_tempo_tag: String = ""

## 深渊薪王 Boss 实时状态快照（1800 HP）
var boss_hp: float = SoulsCombatConfig.BOSS_MAX_HP
var boss_max_hp: float = SoulsCombatConfig.BOSS_MAX_HP
var boss_posture: float = 0.0
var boss_max_posture: float = 100.0
var boss_fsm_state: StringName = &"idle"
var boss_bt_leaf: StringName = &"act_stalk_approach"
var boss_unblockable_warning: bool = false
var boss_hyper_armor: bool = false
var boss_tempo_tag: String = ""
var boss_combo_step: int = 1
var boss_combo_total: int = 1

## 自动化契约验证统计
var passed_cases: int = 0
var total_cases: int = 0
var log_lines: PackedStringArray = PackedStringArray()

#endregion


#region 状态更新与格式化辅助

func set_banner(title: String, _subtitle: String = "", color: Color = Color(0.78, 0.88, 0.98, 0.95)) -> void:
	hud_hint_text = title
	hud_hint_color = color
	state_changed.emit()


func append_log(bbcode_msg: String) -> void:
	var time_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var formatted: String = "[color=#7b8ba6][%05.2fs][/color] %s" % [time_sec, bbcode_msg]
	log_lines.append(formatted)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.remove_at(0)
	log_appended.emit(formatted)


static func get_fsm_state_cn_name(state_name: StringName) -> String:
	match state_name:
		&"idle":
			return "待机"
		&"move":
			return "走位"
		&"dodge":
			return "翻滚"
		&"parry":
			return "弹反"
		&"block":
			return "格挡"
		&"attack_windup":
			return "蓄力"
		&"attack_slash":
			return "斩击"
		&"attack_recovery":
			return "收刀破绽"
		&"riposte":
			return "致命处决"
		&"hit_stun":
			return "硬直"
		&"staggered":
			return "架势崩溃"
		&"dead":
			return "陨落"
		_:
			return String(state_name)


static func get_bt_leaf_cn_name(leaf_id: StringName) -> String:
	match leaf_id:
		SoulsCombatConfig.BT_LEAF_STAGGERED:
			return "架势崩溃"
		SoulsCombatConfig.BT_LEAF_EVADE_DODGE:
			return "战术闪避"
		SoulsCombatConfig.BT_LEAF_DEFEND_PARRY_BLOCK:
			return "振刀格挡"
		SoulsCombatConfig.BT_LEAF_PACING_STANDOFF:
			return "撤步对峙"
		SoulsCombatConfig.BT_LEAF_GAP_CLOSE:
			return "突进跳劈"
		SoulsCombatConfig.BT_LEAF_RED_NOVA:
			return "危 · 旋风斩"
		SoulsCombatConfig.BT_LEAF_DELAYED_FEINT:
			return "霸体快慢刀"
		SoulsCombatConfig.BT_LEAF_COMBO_SLASH:
			return "三连狂斩"
		SoulsCombatConfig.BT_LEAF_STALK_APPROACH:
			return "审视逼近"
		_:
			return String(leaf_id)

#endregion
