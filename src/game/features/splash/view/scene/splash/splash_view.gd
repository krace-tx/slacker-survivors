class_name SplashView
extends BaseView

## 闪屏场景全屏 UI 视图容器（位于 src/game/features/splash/view/scene/splash/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 挂载于 [SplashScene] 的 `UI` 根节点，继承 [BaseView] 自动获享异形屏安全区逆矩阵适配与 `task_scope` 守卫；[br]
## 2. 驱动主视觉背景微幅呼吸感与 UI 柔和渐显入场；[br]
## 3. 组合并驱动局部预制体 [BootProgressPanel]，向上层转发 [signal retry_requested] 交互信号。

## 用户点击重试按钮时发射
signal retry_requested()

#region Constants & State
const _FADE_IN_DURATION: float = 0.45
const _PROP_MODULATE_ALPHA: NodePath = ^"modulate:a"

var _fade_tween: Tween = null

@onready var _progress_panel: BootProgressPanel = (
	get_node_or_null("PanelMargin/BootProgressPanel") as BootProgressPanel
)
#endregion


#region Engine Lifecycle
func _ready() -> void:
	super._ready()
	if _progress_panel != null and not _progress_panel.retry_requested.is_connected(_on_panel_retry_requested):
		_progress_panel.retry_requested.connect(_on_panel_retry_requested)

	_play_fade_in()
#endregion


#region Public View Rendering API
## 重置视图到初始状态
func reset_view() -> void:
	if _progress_panel != null:
		_progress_panel.reset_state()
	_play_fade_in()


## 渲染正常加载进度与状态描述
func render_progress(target_ratio: float, status_text: String) -> void:
	if _progress_panel != null:
		_progress_panel.render_progress(target_ratio, status_text)


## 渲染启动致命异常状态并显示重试按钮
func render_error(error_text: String) -> void:
	if _progress_panel != null:
		_progress_panel.render_error(error_text)


## 渲染加载 100% 完成状态
func render_completed(status_text: String) -> void:
	if _progress_panel != null:
		_progress_panel.render_completed(status_text)
#endregion


#region Internal Callbacks
func _play_fade_in() -> void:
	if _progress_panel == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_progress_panel.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_progress_panel, _PROP_MODULATE_ALPHA, 1.0, _FADE_IN_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_panel_retry_requested() -> void:
	retry_requested.emit()
#endregion
