class_name StorageStatPill
extends PanelContainer

## 顶栏状态胶囊叶组件（`src/test/storage/view/component/pill/`）。

@onready var _key_label: Label = %KeyLabel as Label
@onready var _value_label: Label = %ValueLabel as Label


func render_pill(key_text: String, val_text: String, val_color: Color = Color("#F1F5F9")) -> void:
	if _key_label != null:
		_key_label.text = key_text
	if _value_label != null:
		_value_label.text = val_text
		_value_label.add_theme_color_override("font_color", val_color)
