class_name SplashScene
extends BaseScene

## 闪屏与业务加载主场景根节点（位于 src/game/features/splash/view/scene/splash/）。[br]
##
## [b]核心职责（遵循 `view/scene/<domain>/` 主场景单元规范）：[/b][br]
## 1. 作为 `App.scene` 路由管理的顶层舞台（继承 [BaseScene]），专注处理场景进退场生命周期（[method _on_enter] / [method _on_exit]）；[br]
## 2. 持有 `UI` 视图根节点（[SplashView]）并装配 [SplashPresenter]，自身不直接操作深层 UI 子控件。

## 用户点击重试按钮或外部触发重试时发射
signal retry_requested()

#region State & Node References
var _presenter: SplashPresenter = null

@onready var _ui_view: SplashView = get_node_or_null("UI") as SplashView
#endregion


#region Engine & Scene Lifecycle
func _ready() -> void:
	if _ui_view != null and not _ui_view.retry_requested.is_connected(_on_ui_retry_requested):
		_ui_view.retry_requested.connect(_on_ui_retry_requested)


func _on_enter(params: BaseParams = null) -> void:
	if _ui_view != null:
		_ui_view.reset_view()

	_presenter = SplashPresenter.new(self, params)
	_presenter.start()


func _on_exit() -> void:
	if _presenter != null:
		_presenter.dispose()
		_presenter = null
#endregion


#region Pure View Rendering APIs (Called by SplashPresenter)
## 渲染正常加载进度与状态描述
func render_progress(target_ratio: float, status_text: String) -> void:
	if _ui_view != null:
		_ui_view.render_progress(target_ratio, status_text)


## 渲染启动致命异常状态并显示重试按钮
func render_error(error_text: String) -> void:
	if _ui_view != null:
		_ui_view.render_error(error_text)


## 渲染加载 100% 完成状态
func render_completed(status_text: String) -> void:
	if _ui_view != null:
		_ui_view.render_completed(status_text)


## 获取当前绑定的 Presenter（供自动化测试读取上下文或触发重试）
func get_presenter() -> SplashPresenter:
	return _presenter
#endregion


#region Internal Signal Callbacks
func _on_ui_retry_requested() -> void:
	retry_requested.emit()
#endregion
