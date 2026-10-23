class_name SoulsCombatConfig
extends RefCounted

## 魂系演练场 3D 战斗数值、前后摇参数、胜负枚举与状态标识常量表（位于 src/test/souls_arena/model/，遵循 MSVP 的 `Model` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一收敛角色有限状态机（FSM）的 12 个标准状态 ID（含前摇 `attack_windup`、挥砍 `attack_slash`、收刀后摇 `attack_recovery` 与死亡终态 `dead`）；[br]
## 2. 统一收敛行为树（BT）的 8 个战术叶节点 ID（含连招后撤步对峙 `act_pacing_standoff`）；[br]
## 3. 定义 3D 圆形竞技场活动半径（`16.5m`）、Boss 生命值（`1800 HP`）与对局胜负状态枚举。


#region 对局胜负状态常量

const MATCH_ONGOING: int = 0
const MATCH_VICTORY: int = 1
const MATCH_DEFEAT: int = 2

#endregion


#region FSM 状态标识常量 (12 状态)

const STATE_IDLE: StringName = &"idle"
const STATE_MOVE: StringName = &"move"
const STATE_DODGE: StringName = &"dodge"
const STATE_PARRY: StringName = &"parry"
const STATE_BLOCK: StringName = &"block"
const STATE_ATTACK_WINDUP: StringName = &"attack_windup"
const STATE_ATTACK_SLASH: StringName = &"attack_slash"
const STATE_ATTACK_RECOVERY: StringName = &"attack_recovery"
const STATE_RIPOSTE: StringName = &"riposte"
const STATE_HIT_STUN: StringName = &"hit_stun"
const STATE_STAGGERED: StringName = &"staggered"
const STATE_DEAD: StringName = &"dead"

#endregion


#region BT 行为树叶节点标识常量

const BT_LEAF_STAGGERED: StringName = &"act_staggered"
const BT_LEAF_EVADE_DODGE: StringName = &"act_boss_dodge"
const BT_LEAF_DEFEND_PARRY_BLOCK: StringName = &"act_boss_defend"
const BT_LEAF_PACING_STANDOFF: StringName = &"act_pacing_standoff"
const BT_LEAF_GAP_CLOSE: StringName = &"act_gap_close"
const BT_LEAF_RED_NOVA: StringName = &"act_red_nova"
const BT_LEAF_DELAYED_FEINT: StringName = &"act_delayed_feint"
const BT_LEAF_COMBO_SLASH: StringName = &"act_combo_slash"
const BT_LEAF_STALK_APPROACH: StringName = &"act_stalk_approach"

#endregion


#region 战斗结算结果枚举标识

const RESULT_DODGED: StringName = &"DODGED"
const RESULT_PARRIED: StringName = &"PARRIED"
const RESULT_BLOCKED: StringName = &"BLOCKED"
const RESULT_HYPER_ARMOR_TANKED: StringName = &"HYPER_ARMOR"
const RESULT_HIT: StringName = &"HIT"
const RESULT_RIPOSTE: StringName = &"RIPOSTE"
const RESULT_DEATH: StringName = &"DEATH"

#endregion


#region 3D 竞技场与角色基础属性常量

## 3D 圆形竞技场可活动半径（外圈石柱半径为 18.0m）。
const ARENA_RADIUS: float = 16.5

## 深渊铁卫 Boss 最大生命值与玩家最大生命值。
const BOSS_MAX_HP: float = 1800.0
const PLAYER_MAX_HP: float = 120.0

## 翻滚总时长（秒）与前段无敌帧（I-Frame）持续时长（秒）。
const DODGE_DURATION: float = 0.44
const DODGE_IFRAME_DURATION: float = 0.30
const DODGE_STAMINA_COST: float = 16.0

## 振刀弹反动作总时长（秒）与黄金完美弹反窗口（秒）。
const PARRY_TOTAL_DURATION: float = 0.34
const PARRY_WINDOW_DURATION: float = 0.18
const PARRY_POSTURE_DEFLECTION: float = 55.0

## 持续架盾格挡减伤比例（80% 减伤，仅受 20% 穿透伤）。
const BLOCK_CHIP_DAMAGE_RATIO: float = 0.20
const BLOCK_STAMINA_COST: float = 14.0
const BLOCK_POSTURE_RATIO: float = 0.40

## 致命处决（Riposte）动作时长与真实伤害。
const RIPOSTE_DURATION: float = 0.60
const RIPOSTE_HIT_TIME: float = 0.22
const RIPOSTE_DAMAGE: float = 360.0
const RIPOSTE_MAX_DISTANCE: float = 3.5

## 受击硬直与架势崩溃跪地持续时长（秒）。
const HIT_STUN_DURATION: float = 0.28
const STAGGERED_DURATION: float = 3.00

#endregion
