class_name BattleHudModel
extends GameModel

## 战斗 HUD · 数据模型 (Model)。[br]
## 记录战斗中角色的生命、等级、经验值、时间与杀敌统计。

var current_hp: float = 100.0
var max_hp: float = 100.0
var current_exp: int = 0
var max_exp: int = 100
var level: int = 1
var kill_count: int = 0
var survived_seconds: float = 0.0


func set_hp(current: float, maximum: float) -> void:
	current_hp = clampf(current, 0.0, maximum)
	max_hp = maximum
	notify_changed()


func set_exp(current: int, maximum: int, current_lvl: int) -> void:
	current_exp = current
	max_exp = maximum
	level = current_lvl
	notify_changed()


func update_stats(kills: int, seconds: float) -> void:
	kill_count = kills
	survived_seconds = seconds
	notify_changed()


func _on_reset() -> void:
	current_hp = 100.0
	max_hp = 100.0
	current_exp = 0
	max_exp = 100
	level = 1
	kill_count = 0
	survived_seconds = 0.0
