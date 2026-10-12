class_name UpgradeSelectionDialog
extends BaseDialog

## 肉鸽选卡 · 弹窗视图 (View)。[br]
## 继承 [BaseDialog]，负责卡牌按钮生成、弹窗动效与用户选择事件。

signal card_chosen(card_id: String)
signal reroll_pressed()

@onready var cards_container: HBoxContainer = %CardsContainer
@onready var reroll_btn: Button = %RerollButton


func _ready() -> void:
	if reroll_btn != null:
		reroll_btn.pressed.connect(func(): reroll_pressed.emit())


## 刷新渲染待选卡牌
func render_cards(cards: Array[Dictionary], rerolls_left: int) -> void:
	if reroll_btn != null:
		reroll_btn.text = "🎲 刷新卡池 (余 %d 次)" % rerolls_left
		reroll_btn.disabled = rerolls_left <= 0
	
	if cards_container == null:
		return
	
	# 清空现有子节点
	for child in cards_container.get_children():
		child.queue_free()
	
	# 动态创建 3 张技能卡
	for card_data in cards:
		var card_btn := Button.new()
		card_btn.custom_minimum_size = Vector2(160, 220)
		card_btn.text = "%s\n\n%s\n\n%s" % [
			card_data.get("icon", "✨"),
			card_data.get("title", ""),
			card_data.get("description", "")
		]
		
		var c_id: String = card_data.get("id", "")
		card_btn.pressed.connect(func(): card_chosen.emit(c_id))
		cards_container.add_child(card_btn)
