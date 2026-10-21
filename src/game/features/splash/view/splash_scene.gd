class_name SplashScene
extends BaseScene

## 闪屏与业务加载视图场景（位于 src/game/features/splash/view/）。[br]
##
## [b]核心职责（遵循 MSVP 的 `View` 规范）：[/b][br]
## 1. 纯视觉表现层：负责品牌标题、进度条视觉阻尼平滑插值（`_process`）、状态文本与错误重试按钮展示；[br]
## 2. 零业务逻辑：不包含任何存储读写或配表解析逻辑，进场时创建并委托 [SplashPresenter] 调度；[br]
## 3. 信号向上汇报：当用户点击错误重试按钮时发射 [signal retry_requested] 信号。

## 用户点击重试按钮或外部触发重试时发射
signal retry_requested()

@onready var _progress_bar: ProgressBar = $UI/CenterContainer/VBoxContainer/ProgressBar
@onready var _status_label: Label = $UI/CenterContainer/VBoxContainer/StatusLabel
@onready var _title_label: Label = $UI/CenterContainer/VBoxContainer/TitleLabel
@onready var _retry_button: Button = get_node_or_null("UI/CenterContainer/VBoxContainer/RetryButton") as Button

var _presenter: SplashPresenter = null
var _target_progress: float = 0.0
var _visual_progress: float = 0.0


func _ready() -> void:
	if _retry_button != null:
		_retry_button.visible = false
		_retry_button.pressed.connect(func() -> void: retry_requested.emit())


func _process(delta: float) -> void:
	if _progress_bar == null:
		return
	if not is_equal_approx(_visual_progress, _target_progress):
		var speed := maxf(2.0, absf(_target_progress - _visual_progress) * 8.0)
		_visual_progress = move_toward(_visual_progress, _target_progress, speed * delta)
		_progress_bar.value = _visual_progress * 100.0


func _on_enter(params: BaseParams = null) -> void:
	_target_progress = 0.0
	_visual_progress = 0.0
	if _progress_bar != null:
		_progress_bar.value = 0.0
	if _retry_button != null:
		_retry_button.visible = false

	_presenter = SplashPresenter.new(self, params)
	_presenter.start()


func _on_exit() -> void:
	if _presenter != null:
		_presenter.dispose()
		_presenter = null


#region Pure View Rendering APIs (Called by SplashPresenter)
## 渲染正常加载进度与状态描述
func render_progress(target_ratio: float, status_text: String) -> void:
	_target_progress = clampf(target_ratio, 0.0, 1.0)
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
	_target_progress = 1.0
	_visual_progress = 1.0
	if _progress_bar != null:
		_progress_bar.value = 100.0
	if _status_label != null:
		_status_label.text = status_text
	if _retry_button != null:
		_retry_button.visible = false
#endregion


## 获取当前绑定的 Presenter（供自动化测试读取上下文或触发重试）
func get_presenter() -> SplashPresenter:
	return _presenter
