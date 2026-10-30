class_name StorageReportPanel
extends PanelContainer

## 右栏 9 项自动化安全契约自检报告与实时操作时间线面板（`src/test/storage/view/component/report/`）。

@onready var _suite_list_label: Label = %SuiteListLabel as Label
@onready var _event_log_label: Label = %EventLogLabel as Label


func render_panel(state: StorageDemoState) -> void:
	if state == null:
		return
	if _suite_list_label != null:
		if state.case_lines.is_empty():
			_suite_list_label.text = "正在执行 9 项存档加密契约自检..."
		else:
			_suite_list_label.text = "\n".join(state.case_lines)
	if _event_log_label != null:
		if state.event_logs.is_empty():
			_event_log_label.text = "暂无操作记录"
		else:
			_event_log_label.text = "\n".join(state.event_logs)
