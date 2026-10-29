class_name StorageHeaderBar
extends PanelContainer

## 存档加密演练场顶部状态与重跑控制栏（`src/test/storage/view/component/header/`）。

signal rerun_suite_requested

@onready var _env_pill: StorageStatPill = %EnvPill as StorageStatPill
@onready var _device_pill: StorageStatPill = %DevicePill as StorageStatPill
@onready var _suite_pill: StorageStatPill = %SuitePill as StorageStatPill
@onready var _rerun_button: Button = %RerunButton as Button


func _ready() -> void:
	if _rerun_button != null:
		_rerun_button.pressed.connect(func() -> void: rerun_suite_requested.emit())


func render_header(state: StorageDemoState) -> void:
	if state == null:
		return
	if _env_pill != null:
		var mode_tag: String = "ENCRYPTED" if state.encryption_enabled else "PLAINTEXT"
		var mode_col: Color = Color("#34D399") if state.encryption_enabled else Color("#FBBF24")
		_env_pill.render_pill("ENV", "%s · %s" % [state.env_name, mode_tag], mode_col)
	if _device_pill != null:
		var bind_tag: String = state.device_fingerprint_tag if state.bind_device_enabled else "UNBOUND"
		var bind_col: Color = Color("#38BDF8") if state.bind_device_enabled else Color("#94A3B8")
		_device_pill.render_pill("HW BIND", bind_tag, bind_col)
	if _suite_pill != null:
		var all_ok: bool = (state.passed_cases == state.total_cases and state.total_cases > 0)
		var suite_col: Color = Color("#34D399") if all_ok else Color("#F87171")
		_suite_pill.render_pill("SUITE", "%d / %d PASS" % [state.passed_cases, state.total_cases], suite_col)
