class_name LobbyMenuPresenter
extends GamePresenter

## 大厅主选单 · 表现层中介 (Presenter)。[br]
## 串联 LobbyMenuView、LobbyMenuModel 与 LobbyMenuService。

var _menu_view: LobbyMenuView:
	get:
		return get_view() as LobbyMenuView

var _menu_model: LobbyMenuModel:
	get:
		return get_model() as LobbyMenuModel

var _menu_service: LobbyMenuService:
	get:
		return get_service() as LobbyMenuService


func _on_bind() -> void:
	if _menu_view == null or _menu_model == null or _menu_service == null:
		return
	
	# 1. 监听 View 派发的用户交互，委托 Service 处理
	if not _menu_view.start_battle_pressed.is_connected(_on_start_battle_pressed):
		_menu_view.start_battle_pressed.connect(_on_start_battle_pressed)
	if not _menu_view.add_gold_pressed.is_connected(_on_add_gold_pressed):
		_menu_view.add_gold_pressed.connect(_on_add_gold_pressed)
	
	# 2. 监听 Model 数据变更信号，驱动 View 刷新
	if not _menu_model.data_changed.is_connected(_on_model_data_changed):
		_menu_model.data_changed.connect(_on_model_data_changed)
	
	# 3. 初始化拉取数据并初次渲染
	_menu_service.refresh_player_data()
	_update_view()


func _on_unbind() -> void:
	if _menu_view != null:
		if _menu_view.start_battle_pressed.is_connected(_on_start_battle_pressed):
			_menu_view.start_battle_pressed.disconnect(_on_start_battle_pressed)
		if _menu_view.add_gold_pressed.is_connected(_on_add_gold_pressed):
			_menu_view.add_gold_pressed.disconnect(_on_add_gold_pressed)
	
	if _menu_model != null:
		if _menu_model.data_changed.is_connected(_on_model_data_changed):
			_menu_model.data_changed.disconnect(_on_model_data_changed)


func _on_start_battle_pressed() -> void:
	if _menu_service != null:
		var res := _menu_service.request_start_battle()
		if res.is_err():
			ToastManager.show("无法进入战斗: %s" % res.error_message())


func _on_add_gold_pressed() -> void:
	if _menu_service != null:
		_menu_service.add_gold(100)


func _on_model_data_changed() -> void:
	_update_view()


func _update_view() -> void:
	if _menu_view != null and _menu_model != null:
		_menu_view.render_profile(
			_menu_model.nickname,
			_menu_model.gold,
			_menu_model.level,
			_menu_model.best_survived_seconds
		)
