class_name MermaidTestState
extends RefCounted

## Mermaid 图蓝图演练场运行时响应式状态模型（位于 `src/test/mermaid_graph/model/`，遵循 `*State` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载守卫状态机（[GuardFsmAgent]）与双史莱姆享元行为树（[SlimeBtSquad]）的实时界面快照；[br]
## 2. 维护契约自检统计与事件日志队列，通过 [signal state_changed] 与 [signal log_appended] 驱动被动视图刷新。


#region Signals & Constants

signal state_changed()
signal log_appended(bbcode_line: String)

const MAX_LOG_LINES: int = 60

#endregion


#region Runtime Fields

## 守卫 FSM 实时读数
var guard_state_id: StringName = &"idle"
var guard_prev_id: StringName = &""
var guard_state_time: float = 0.0
var guard_enemy_visible: bool = false
var guard_action_desc: String = "站岗警戒中"

## 史莱姆 Alpha（近战态）实时读数
var alpha_hp_ratio: float = 0.85
var alpha_enemy_dist: float = 115.0
var alpha_tick_count: int = 0
var alpha_action_desc: String = "准备就绪"

## 史莱姆 Bravo（残血态）实时读数
var bravo_hp_ratio: float = 0.22
var bravo_enemy_dist: float = 240.0
var bravo_tick_count: int = 0
var bravo_action_desc: String = "准备就绪"

## 自动化契约验证统计
var passed_cases: int = 0
var failed_cases: int = 0
var log_lines: PackedStringArray = PackedStringArray()

#endregion


#region State Mutation & Formatting

## 触发视图状态同步通知。
func notify_changed() -> void:
	state_changed.emit()


## 追加单行 BBCode 教学或流转日志。
func append_log(bbcode_line: String) -> void:
	log_lines.append(bbcode_line)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.remove_at(0)
	log_appended.emit(bbcode_line)


## 清空历史日志与验证计数。
func clear_logs() -> void:
	log_lines.clear()
	passed_cases = 0
	failed_cases = 0
	state_changed.emit()


## 生成顶部单行实时诊断胶囊摘要文本。
func get_status_pill_text() -> String:
	var sight_str: String = "已索敌" if guard_enemy_visible else "无敌情"
	return "守卫FSM：[%s · %.1fs · %s]   |   史莱姆A：[HP %d%% · %.0fm]   |   史莱姆B：[HP %d%% · %.0fm]   |   自检：[%d 通过 / %d 失败]" % [
		String(guard_state_id),
		guard_state_time,
		sight_str,
		roundi(alpha_hp_ratio * 100.0),
		alpha_enemy_dist,
		roundi(bravo_hp_ratio * 100.0),
		bravo_enemy_dist,
		passed_cases,
		failed_cases,
	]

#endregion
