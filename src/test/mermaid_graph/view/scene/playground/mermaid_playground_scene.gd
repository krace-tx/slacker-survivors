class_name MermaidPlaygroundScene
extends BaseScene

## Mermaid 图蓝图演练场顶层场景舞台（位于 `src/test/mermaid_graph/view/scene/playground/`，继承 [BaseScene]）。[br]
##
## [b]核心职责：[/b][br]
## 1. 作为 `src/test/mermaid_graph/` 的可运行主场景入口（支持编辑器 `F6` 与无头命令行直接启动）；[br]
## 2. 仅负责路由生命周期钩子与 [MermaidPlaygroundPresenter] 的装配、帧推进及退场解绑。


#region Node References & Private State

@onready var _ui: MermaidPlaygroundView = %UI as MermaidPlaygroundView

var _presenter: MermaidPlaygroundPresenter = null

#endregion


#region BaseScene Lifecycle

func _on_enter(_params: BaseParams = null) -> void:
	_cleanup_presenter()
	_presenter = MermaidPlaygroundPresenter.new(self, _ui)
	var suite_ok: bool = _presenter.bind()

	if _is_auto_quit_requested():
		if (await task_scope.sleep(0.05)).is_err():
			return
		_cleanup_presenter()
		get_tree().quit(0 if suite_ok else 1)


func _on_exit() -> void:
	_cleanup_presenter()


func _exit_tree() -> void:
	_cleanup_presenter()
	super._exit_tree()


func _process(delta: float) -> void:
	if _presenter != null:
		_presenter.tick(delta)


func _cleanup_presenter() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null


static func _is_auto_quit_requested() -> bool:
	return (
		OS.get_cmdline_user_args().has("--mermaid-test-auto-quit")
		or OS.get_cmdline_args().has("--mermaid-test-auto-quit")
	)

#endregion
