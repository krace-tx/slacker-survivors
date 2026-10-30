class_name StorageInspectorPanel
extends PanelContainer

## 中栏磁盘物理字节实时透视面板（对比 `saves/*.sav` 密文与 `config/*.json` 明文）。

@onready var _save_path_label: Label = %SavePathLabel as Label
@onready var _save_badge_label: Label = %SaveBadgeLabel as Label
@onready var _save_hex_label: Label = %SaveHexLabel as Label
@onready var _save_ascii_label: Label = %SaveAsciiLabel as Label
@onready var _save_model_label: Label = %SaveModelLabel as Label

@onready var _cfg_path_label: Label = %CfgPathLabel as Label
@onready var _cfg_badge_label: Label = %CfgBadgeLabel as Label
@onready var _cfg_raw_label: Label = %CfgRawLabel as Label


func render_panel(state: StorageDemoState) -> void:
	if state == null:
		return
	if _save_path_label != null:
		var bak_tag: String = " + .bak" if state.save_has_backup else ""
		_save_path_label.text = "%s (%d B%s)" % [state.save_disk_path, state.save_size_bytes, bak_tag]
	if _save_badge_label != null:
		_save_badge_label.text = state.save_format_badge
		_save_badge_label.add_theme_color_override(
			"font_color",
			Color("#34D399") if state.save_is_encrypted_on_disk else Color("#FBBF24")
		)
	if _save_hex_label != null:
		_save_hex_label.text = "HEX: " + state.save_hex_preview
	if _save_ascii_label != null:
		_save_ascii_label.text = "RAW: " + state.save_raw_preview
	if _save_model_label != null:
		_save_model_label.text = state.save_decoded_summary

	if _cfg_path_label != null:
		_cfg_path_label.text = "%s (%d B)" % [state.config_disk_path, state.config_size_bytes]
	if _cfg_badge_label != null:
		_cfg_badge_label.text = "JSON · 自动豁免加密"
		_cfg_badge_label.add_theme_color_override("font_color", Color("#38BDF8"))
	if _cfg_raw_label != null:
		_cfg_raw_label.text = state.config_raw_preview
