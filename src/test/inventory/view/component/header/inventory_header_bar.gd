class_name InventoryHeaderBar
extends PanelContainer

## 演练场顶部状态、货币胶囊与全局操作栏预制体脚本（`src/test/inventory/view/component/header/`）。[br]
##
## [b]设计职责：[/b]绑定 `inventory_header_bar.tscn` 声明式节点与按钮样式资源，展示契约通过数、钱包余额并转发全局按钮意图。


#region Signals

## 点击「补给」按钮。
signal supply_requested

## 点击「锻造」按钮。
signal craft_requested

## 点击「重置」按钮。
signal reset_requested

#endregion


#region Exports & Node References

@export_group("Craft Button Styles")
## 锻造资源充足时的紫晶高亮常态样式。
@export var craft_ready_normal: StyleBoxFlat = null
## 锻造资源充足时的紫晶悬停样式。
@export var craft_ready_hover: StyleBoxFlat = null
## 锻造资源充足时的紫晶按压样式。
@export var craft_ready_pressed: StyleBoxFlat = null
## 锻造资源不足时的普通暗岩常态样式。
@export var craft_idle_normal: StyleBoxFlat = null
## 锻造资源不足时的普通暗岩悬停样式。
@export var craft_idle_hover: StyleBoxFlat = null
## 锻造资源不足时的普通暗岩按压样式。
@export var craft_idle_pressed: StyleBoxFlat = null

@onready var _pass_badge_label: Label = %PassBadgeLabel as Label
@onready var _gold_value_label: Label = %GoldValueLabel as Label
@onready var _gem_value_label: Label = %GemValueLabel as Label
@onready var _supply_btn: Button = %SupplyButton as Button
@onready var _craft_btn: Button = %CraftButton as Button
@onready var _reset_btn: Button = %ResetButton as Button

#endregion


#region Lifecycle & Rendering

func _ready() -> void:
	if _supply_btn != null:
		_supply_btn.pressed.connect(func() -> void: supply_requested.emit())
	if _craft_btn != null:
		_craft_btn.pressed.connect(func() -> void: craft_requested.emit())
	if _reset_btn != null:
		_reset_btn.pressed.connect(func() -> void: reset_requested.emit())


## 刷新顶栏契约自检徽章、钱包数量与锻造按钮可合成态。
func render_header(
	passed_cases: int,
	total_cases: int,
	gold_count: int,
	gem_count: int,
	craft_ready: bool
) -> void:
	if _pass_badge_label != null:
		_pass_badge_label.text = "PASS %d/%d" % [passed_cases, total_cases]
	if _gold_value_label != null:
		_gold_value_label.text = _format_number(gold_count)
	if _gem_value_label != null:
		_gem_value_label.text = _format_number(gem_count)
	if _craft_btn != null:
		if craft_ready and craft_ready_normal != null:
			_craft_btn.add_theme_stylebox_override("normal", craft_ready_normal)
			_craft_btn.add_theme_stylebox_override("hover", craft_ready_hover)
			_craft_btn.add_theme_stylebox_override("pressed", craft_ready_pressed)
			_craft_btn.add_theme_color_override("font_color", Color(0.93, 0.89, 1.0, 1.0))
		elif craft_idle_normal != null:
			_craft_btn.add_theme_stylebox_override("normal", craft_idle_normal)
			_craft_btn.add_theme_stylebox_override("hover", craft_idle_hover)
			_craft_btn.add_theme_stylebox_override("pressed", craft_idle_pressed)
			_craft_btn.add_theme_color_override("font_color", Color(0.84, 0.90, 0.98, 1.0))


static func _format_number(val: int) -> String:
	var s: String = str(absi(val))
	var out: String = ""
	var cnt: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		if cnt > 0 and cnt % 3 == 0:
			out = "," + out
		out = s.substr(i, 1) + out
		cnt += 1
	return ("-" + out) if val < 0 else out

#endregion
