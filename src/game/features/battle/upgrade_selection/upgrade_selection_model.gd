class_name UpgradeSelectionModel
extends GameModel

## 肉鸽选卡 · 数据模型 (Model)。[br]
## 记录当前可供玩家选择的技能升级卡列表与剩余刷新次数。

var candidate_cards: Array[Dictionary] = []
var rerolls_left: int = 1


func set_candidates(cards: Array[Dictionary], rerolls: int) -> void:
	candidate_cards = cards
	rerolls_left = rerolls
	notify_changed()


func _on_reset() -> void:
	candidate_cards.clear()
	rerolls_left = 1
