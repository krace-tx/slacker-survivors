class_name StorageControlPanel
extends PanelContainer

## 左栏环境加密开关与攻防模拟操作面板（`src/test/storage/view/component/control/`）。

signal toggle_encryption_requested
signal toggle_bind_device_requested
signal toggle_fallback_requested
signal write_save_requested
signal write_config_requested
signal read_verify_requested
signal tamper_primary_requested
signal foreign_device_requested
signal cross_slot_requested

@onready var _enc_switch_btn: Button = %EncSwitchBtn as Button
@onready var _bind_switch_btn: Button = %BindSwitchBtn as Button
@onready var _fallback_switch_btn: Button = %FallbackSwitchBtn as Button

@onready var _write_save_btn: Button = %WriteSaveBtn as Button
@onready var _write_cfg_btn: Button = %WriteCfgBtn as Button
@onready var _read_verify_btn: Button = %ReadVerifyBtn as Button
@onready var _tamper_btn: Button = %TamperBtn as Button
@onready var _foreign_btn: Button = %ForeignBtn as Button
@onready var _cross_slot_btn: Button = %CrossSlotBtn as Button
@onready var _status_banner_label: Label = %StatusBannerLabel as Label


func _ready() -> void:
	if _enc_switch_btn != null:
		_enc_switch_btn.pressed.connect(func() -> void: toggle_encryption_requested.emit())
	if _bind_switch_btn != null:
		_bind_switch_btn.pressed.connect(func() -> void: toggle_bind_device_requested.emit())
	if _fallback_switch_btn != null:
		_fallback_switch_btn.pressed.connect(func() -> void: toggle_fallback_requested.emit())
	if _write_save_btn != null:
		_write_save_btn.pressed.connect(func() -> void: write_save_requested.emit())
	if _write_cfg_btn != null:
		_write_cfg_btn.pressed.connect(func() -> void: write_config_requested.emit())
	if _read_verify_btn != null:
		_read_verify_btn.pressed.connect(func() -> void: read_verify_requested.emit())
	if _tamper_btn != null:
		_tamper_btn.pressed.connect(func() -> void: tamper_primary_requested.emit())
	if _foreign_btn != null:
		_foreign_btn.pressed.connect(func() -> void: foreign_device_requested.emit())
	if _cross_slot_btn != null:
		_cross_slot_btn.pressed.connect(func() -> void: cross_slot_requested.emit())


func render_panel(state: StorageDemoState) -> void:
	if state == null:
		return
	if _enc_switch_btn != null:
		_enc_switch_btn.text = (
			"全局存档加密开关: ON (AES-256)"
			if state.encryption_enabled
			else "全局存档加密开关: OFF (明文调试)"
		)
		_enc_switch_btn.add_theme_color_override(
			"font_color",
			Color("#34D399") if state.encryption_enabled else Color("#FBBF24")
		)
	if _bind_switch_btn != null:
		_bind_switch_btn.text = (
			"硬件指纹绑定: ON (%s)" % state.device_fingerprint_tag
			if state.bind_device_enabled
			else "硬件指纹绑定: OFF (允许跨机)"
		)
		_bind_switch_btn.add_theme_color_override(
			"font_color",
			Color("#38BDF8") if state.bind_device_enabled else Color("#94A3B8")
		)
	if _fallback_switch_btn != null:
		_fallback_switch_btn.text = (
			"旧明文兼容策略: ON (Dev 自动升级)"
			if state.plaintext_fallback_enabled
			else "旧明文兼容策略: OFF (Prod 防降级)"
		)
		_fallback_switch_btn.add_theme_color_override(
			"font_color",
			Color("#A78BFA") if state.plaintext_fallback_enabled else Color("#F1F5F9")
		)
	if _status_banner_label != null:
		_status_banner_label.text = "最近状态: %s" % state.save_status_text
		_status_banner_label.add_theme_color_override(
			"font_color",
			Color("#34D399") if state.save_status_ok else Color("#F87171")
		)
