class_name InventoryPlaygroundScene
extends BaseScene

## 背包与通用容器基建交互测试入口场景（`src/test/inventory/view/scene/playground/`）。[br]
##
## [b]运行模式：[/b][br]
## 1. 编辑器打开 [code]src/test/inventory/inventory_test.tscn[/code] 按 [code]F6[/code] 进入交互演练场；[br]
## 2. 命令行附带 [code]--inventory-test-auto-quit[/code] 运行无头 10 项契约验证门禁。


#region Node References & State

@onready var _ui: InventoryPlaygroundView = $UI as InventoryPlaygroundView

var _presenter: InventoryDemoPresenter = null

#endregion


#region Scene Lifecycle

func _on_enter(_params: BaseParams = null) -> void:
	if _presenter != null:
		_presenter.unbind()
	_presenter = InventoryDemoPresenter.new(_ui)
	var passed: int = _presenter.bind()
	var total: int = _presenter.get_service().state.total_cases
	var all_ok: bool = passed == total

	if (
		OS.get_cmdline_user_args().has("--inventory-test-auto-quit")
		or OS.get_cmdline_args().has("--inventory-test-auto-quit")
	):
		get_tree().quit(0 if all_ok else 1)


func _on_exit() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null

#endregion
