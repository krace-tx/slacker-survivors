class_name StoragePlaygroundScene
extends BaseScene

## 全局存档加密与硬件指纹绑定交互演练场入口场景（`src/test/storage/view/scene/playground/`）。[br]
##
## [b]运行模式：[/b][br]
## 1. 编辑器打开 [code]res://src/test/storage/storage_test.tscn[/code] 按 [code]F6[/code] 进入实时交互透视演练场；[br]
## 2. 命令行附带 [code]--storage-test-auto-quit[/code] 运行无头 9 项安全契约验证门禁。

@onready var _ui: StoragePlaygroundView = $UI as StoragePlaygroundView

var _presenter: StorageDemoPresenter = null


func _on_enter(_params: BaseParams = null) -> void:
	if _presenter != null:
		_presenter.unbind()
	_presenter = StorageDemoPresenter.new(_ui)
	var passed: int = await _presenter.bind_and_run_async()
	var total: int = _presenter.get_service().state.total_cases
	var all_ok: bool = (passed == total)

	if (
		OS.get_cmdline_user_args().has("--storage-test-auto-quit")
		or OS.get_cmdline_args().has("--storage-test-auto-quit")
	):
		get_tree().quit(0 if all_ok else 1)


func _on_exit() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null
