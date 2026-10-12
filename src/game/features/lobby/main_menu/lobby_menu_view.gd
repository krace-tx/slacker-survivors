class_name LobbyMenuView
extends BaseUIView

## 大厅主选单 · 界面视图 (View)。[br]
## 继承 [BaseUIView]，负责大厅 UI 控件渲染、交互事件转发，绝无任何业务规则。

signal start_battle_pressed()
signal add_gold_pressed()

@onready var nickname_label: Label = %NicknameLabel
@onready var gold_label: Label = %GoldLabel
@onready var level_label: Label = %LevelLabel
@onready var best_time_label: Label = %BestTimeLabel
@onready var start_btn: Button = %StartButton
@onready var add_gold_btn: Button = %AddGoldButton


func _ready() -> void:
	super._ready()
	
	if start_btn != null:
		start_btn.pressed.connect(func(): start_battle_pressed.emit())
	if add_gold_btn != null:
		add_gold_btn.pressed.connect(func(): add_gold_pressed.emit())


## 纯净渲染方法：接收呈现数据并刷新 UI 控件
func render_profile(nickname: String, gold: int, level: int, best_time: float) -> void:
	if nickname_label != null:
		nickname_label.text = nickname
	if gold_label != null:
		gold_label.text = "💰 金币: %d" % gold
	if level_label != null:
		level_label.text = "⭐ 等级: Lv.%d" % level
	if best_time_label != null:
		var mins := int(best_time) / 60
		var secs := int(best_time) % 60
		best_time_label.text = "⏱️ 最高存活: %02d:%02d" % [mins, secs]
