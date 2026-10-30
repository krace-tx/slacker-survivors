class_name StoragePlaygroundView
extends BaseView

## 存档加密与硬件指纹演练场顶层视图协调器（`src/test/storage/view/scene/playground/`）。[br]
##
## 零运行时代码拼装节点，纯粹通过 `%UniqueName` 组合声明式 `.tscn` 子预制体：
## [StorageHeaderBar]、[StorageControlPanel]、[StorageInspectorPanel] 与 [StorageReportPanel]。

signal rerun_suite_requested
signal toggle_encryption_requested
signal toggle_bind_device_requested
signal toggle_fallback_requested
signal write_save_requested
signal write_config_requested
signal read_verify_requested
signal tamper_primary_requested
signal foreign_device_requested
signal cross_slot_requested

@onready var _header_bar: StorageHeaderBar = %HeaderBar as StorageHeaderBar
@onready var _control_panel: StorageControlPanel = %ControlPanel as StorageControlPanel
@onready var _inspector_panel: StorageInspectorPanel = %InspectorPanel as StorageInspectorPanel
@onready var _report_panel: StorageReportPanel = %ReportPanel as StorageReportPanel


func _ready() -> void:
	super._ready()
	if _header_bar != null:
		_header_bar.rerun_suite_requested.connect(func() -> void: rerun_suite_requested.emit())
	if _control_panel != null:
		_control_panel.toggle_encryption_requested.connect(func() -> void: toggle_encryption_requested.emit())
		_control_panel.toggle_bind_device_requested.connect(func() -> void: toggle_bind_device_requested.emit())
		_control_panel.toggle_fallback_requested.connect(func() -> void: toggle_fallback_requested.emit())
		_control_panel.write_save_requested.connect(func() -> void: write_save_requested.emit())
		_control_panel.write_config_requested.connect(func() -> void: write_config_requested.emit())
		_control_panel.read_verify_requested.connect(func() -> void: read_verify_requested.emit())
		_control_panel.tamper_primary_requested.connect(func() -> void: tamper_primary_requested.emit())
		_control_panel.foreign_device_requested.connect(func() -> void: foreign_device_requested.emit())
		_control_panel.cross_slot_requested.connect(func() -> void: cross_slot_requested.emit())


func render_all(state: StorageDemoState) -> void:
	if state == null:
		return
	if _header_bar != null:
		_header_bar.render_header(state)
	if _control_panel != null:
		_control_panel.render_panel(state)
	if _inspector_panel != null:
		_inspector_panel.render_panel(state)
	if _report_panel != null:
		_report_panel.render_panel(state)
