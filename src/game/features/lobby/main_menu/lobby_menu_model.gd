class_name LobbyMenuModel
extends GameModel

## 大厅主选单 · 数据模型 (Model)。[br]
## 仅持有大厅界面所需的数据状态，纯数据类，零 UI 依赖。

var nickname: String = "Survivor"
var gold: int = 0
var level: int = 1
var best_survived_seconds: float = 0.0


func update_profile(new_nickname: String, new_gold: int, new_level: int, best_time: float) -> void:
	nickname = new_nickname
	gold = new_gold
	level = new_level
	best_survived_seconds = best_time
	notify_changed()


func set_gold(new_gold: int) -> void:
	if gold != new_gold:
		gold = new_gold
		notify_changed()


func _on_reset() -> void:
	nickname = "Survivor"
	gold = 0
	level = 1
	best_survived_seconds = 0.0
