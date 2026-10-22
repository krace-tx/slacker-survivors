class_name BootProgressPanel
extends VBoxContainer

## 闪屏启动进度与异常重试交互面板预制体（位于 src/game/features/splash/view/component/progress/）。[br]
##
## [b]核心职责（遵循 `view/component/<domain>/` 语义角色命名规范）：[/b][br]
## 1. 聚合标题、平滑进度条（[BootProgressBar]）、状态描述文本与错误重试按钮（[BaseTextureButton]）；[br]
## 2. 对父视图（[SplashView]）暴露声明式渲染方法，并向上转发 [signal retry_requested] 交互信号。

## 用户点击重试按钮时发射
signal retry_requested()

#region Constants & Node References
const _PERCENT_SCALE: float = 100.0

@onready var _progress_bar: BootProgressBar = $ProgressGroup/ProgressBar as BootProgressBar
@onready var _status_label: Label = $ProgressGroup/MetaRow/StatusLabel as Label
@onready var _percent_label: Label = $ProgressGroup/MetaRow/PercentLabel as Label
@onready var _retry_button: BaseButton = $RetryButton as BaseButton
#endregion


#region Engine Lifecycle
func _ready() -> void:
	if _retry_button != null:
		_retry_button.visible = false
		if not _retry_button.pressed.is_connected(_on_retry_button_pressed):
			_retry_button.pressed.connect(_on_retry_button_pressed)

	if _progress_bar != null and not _progress_bar.visual_ratio_changed.is_connected(_on_bar_visual_ratio_changed):
		_progress_bar.visual_ratio_changed.connect(_on_bar_visual_ratio_changed)

	_update_percent_text(0.0)
#endregion


#region Public Rendering API
## 重置面板到初始零进度状态
func reset_state() -> void:
	if _progress_bar != null:
		_progress_bar.snap_to_ratio(0.0)
	_update_percent_text(0.0)
	if _retry_button != null:
		_retry_button.visible = false


## 渲染正常加载进度与状态描述
func render_progress(target_ratio: float, status_text: String) -> void:
	if _progress_bar != null:
		_progress_bar.set_target_ratio(target_ratio)
	if _status_label != null:
		_status_label.text = status_text
	if _retry_button != null:
		_retry_button.visible = false


## 渲染启动致命异常状态并显示重试按钮
func render_error(error_text: String) -> void:
	if _status_label != null:
		_status_label.text = error_text
	if _retry_button != null:
		_retry_button.visible = true


## 渲染加载 100% 完成状态
func render_completed(status_text: String) -> void:
	if _progress_bar != null:
		_progress_bar.snap_to_ratio(1.0)
	_update_percent_text(1.0)
	if _status_label != null:
		_status_label.text = status_text
	if _retry_button != null:
		_retry_button.visible = false
#endregion


#region Internal Callbacks
func _on_bar_visual_ratio_changed(visual_ratio: float) -> void:
	_update_percent_text(visual_ratio)


func _update_percent_text(ratio: float) -> void:
	if _percent_label == null:
		return
	var pct: int = clampi(int(round(ratio * _PERCENT_SCALE)), 0, 100)
	_percent_label.text = "%d%%" % pct


func _on_retry_button_pressed() -> void:
	retry_requested.emit()
#endregion
