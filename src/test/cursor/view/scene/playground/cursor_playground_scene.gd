class_name CursorPlaygroundScene
extends BaseScene

## 自定义鼠标教学演练场主场景（位于 src/test/cursor/view/scene/playground/，遵循 `BaseScene` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 作为 `src/test/cursor/` 的独立可运行入口场景（支持编辑器 `F6` 与命令行 `--headless` 直接启动）；[br]
## 2. 挂载 [CursorPlaygroundView] 并委托 [CursorPlaygroundPresenter] 完成生命周期编排与退出清理。


#region 节点引用

@onready var _playground_view: CursorPlaygroundView = $PlaygroundView as CursorPlaygroundView

#endregion


#region 私有变量

var _presenter: CursorPlaygroundPresenter = null

#endregion


#region 生命周期

func _on_enter(_params: BaseParams = null) -> void:
	if _presenter != null:
		_presenter.unbind()
	_presenter = CursorPlaygroundPresenter.new(self, _playground_view)
	_presenter.bind()


func _on_exit() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null


func _process(_delta: float) -> void:
	if _presenter != null:
		_presenter.poll_live_diagnostics()

#endregion
