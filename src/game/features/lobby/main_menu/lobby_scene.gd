class_name LobbyScene
extends BaseScene

## 大厅主场景（Lobby Scene）。[br]
## 继承 [BaseScene]，作为主选单视图的场景宿主，管理 MSVP 组装与生命周期。

@onready var _ui_view: LobbyMenuView = $UI

var _model: LobbyMenuModel
var _service: LobbyMenuService
var _presenter: LobbyMenuPresenter


func _on_enter(_params: Dictionary = {}) -> void:
	# MSVP 组装
	_model = LobbyMenuModel.new()
	_service = LobbyMenuService.new(_model)
	_presenter = LobbyMenuPresenter.new()
	
	_presenter.bind(_ui_view, _model, _service)


func _on_exit() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null
	_model = null
	_service = null
