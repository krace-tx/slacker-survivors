class_name BattleHudPresenter
extends GamePresenter

## 战斗 HUD · 表现调度层 (Presenter)。[br]
## 调度 BattleHudView、BattleHudModel 与 BattleHudService。

var _hud_view: BattleHudView:
	get:
		return get_view() as BattleHudView

var _hud_model: BattleHudModel:
	get:
		return get_model() as BattleHudModel

var _hud_service: BattleHudService:
	get:
		return get_service() as BattleHudService


func _on_bind() -> void:
	if _hud_view == null or _hud_model == null or _hud_service == null:
		return
	
	if not _hud_view.pause_pressed.is_connected(_on_pause_pressed):
		_hud_view.pause_pressed.connect(_on_pause_pressed)
	
	if not _hud_model.data_changed.is_connected(_on_model_data_changed):
		_hud_model.data_changed.connect(_on_model_data_changed)
	
	_update_view()


func _on_unbind() -> void:
	if _hud_view != null:
		if _hud_view.pause_pressed.is_connected(_on_pause_pressed):
			_hud_view.pause_pressed.disconnect(_on_pause_pressed)
	
	if _hud_model != null:
		if _hud_model.data_changed.is_connected(_on_model_data_changed):
			_hud_model.data_changed.disconnect(_on_model_data_changed)


func _on_pause_pressed() -> void:
	ToastManager.show("游戏已暂停")


func _on_model_data_changed() -> void:
	_update_view()


func _update_view() -> void:
	if _hud_view != null and _hud_model != null:
		_hud_view.render_hud(
			_hud_model.current_hp,
			_hud_model.max_hp,
			_hud_model.current_exp,
			_hud_model.max_exp,
			_hud_model.level,
			_hud_model.kill_count,
			_hud_model.survived_seconds
		)
