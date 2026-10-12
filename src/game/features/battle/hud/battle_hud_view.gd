class_name BattleHudView
extends BaseUIView

## 战斗 HUD · 界面视图 (View)。[br]
## 继承 [BaseUIView]，负责实时展示生命、经验、杀敌、计时及暂停交互。

signal pause_pressed()

@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_label: Label = %HpLabel
@onready var exp_bar: ProgressBar = %ExpBar
@onready var level_label: Label = %LevelLabel
@onready var timer_label: Label = %TimerLabel
@onready var kills_label: Label = %KillsLabel
@onready var pause_btn: Button = %PauseButton


func _ready() -> void:
	super._ready()
	if pause_btn != null:
		pause_btn.pressed.connect(func(): pause_pressed.emit())


## 刷新所有战斗 HUD 状态
func render_hud(cur_hp: float, max_hp: float, cur_exp: int, max_exp: int, lvl: int, kills: int, seconds: float) -> void:
	if hp_bar != null:
		hp_bar.max_value = max_hp
		hp_bar.value = cur_hp
	if hp_label != null:
		hp_label.text = "%d / %d" % [int(cur_hp), int(max_hp)]
	
	if exp_bar != null:
		exp_bar.max_value = max_exp
		exp_bar.value = cur_exp
	if level_label != null:
		level_label.text = "Lv.%d" % lvl
	
	if kills_label != null:
		kills_label.text = "💀 %d" % kills
	
	if timer_label != null:
		var mins := int(seconds) / 60
		var secs := int(seconds) % 60
		timer_label.text = "%02d:%02d" % [mins, secs]
