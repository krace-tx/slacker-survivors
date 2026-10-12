class_name UpgradeSelectionPresenter
extends GamePresenter

## 肉鸽选卡 · 表现调度层 (Presenter)。[br]
## 调度 UpgradeSelectionDialog、UpgradeSelectionModel 与 UpgradeSelectionService。

var _dialog_view: UpgradeSelectionDialog:
	get:
		return get_view() as UpgradeSelectionDialog

var _upgrade_model: UpgradeSelectionModel:
	get:
		return get_model() as UpgradeSelectionModel

var _upgrade_service: UpgradeSelectionService:
	get:
		return get_service() as UpgradeSelectionService


func _on_bind() -> void:
	if _dialog_view == null or _upgrade_model == null or _upgrade_service == null:
		return
	
	if not _dialog_view.card_chosen.is_connected(_on_card_chosen):
		_dialog_view.card_chosen.connect(_on_card_chosen)
	if not _dialog_view.reroll_pressed.is_connected(_on_reroll_pressed):
		_dialog_view.reroll_pressed.connect(_on_reroll_pressed)
	
	if not _upgrade_model.data_changed.is_connected(_on_model_data_changed):
		_upgrade_model.data_changed.connect(_on_model_data_changed)
	
	_upgrade_service.roll_cards()
	_update_view()


func _on_unbind() -> void:
	if _dialog_view != null:
		if _dialog_view.card_chosen.is_connected(_on_card_chosen):
			_dialog_view.card_chosen.disconnect(_on_card_chosen)
		if _dialog_view.reroll_pressed.is_connected(_on_reroll_pressed):
			_dialog_view.reroll_pressed.disconnect(_on_reroll_pressed)
	
	if _upgrade_model != null:
		if _upgrade_model.data_changed.is_connected(_on_model_data_changed):
			_upgrade_model.data_changed.disconnect(_on_model_data_changed)


func _on_card_chosen(card_id: String) -> void:
	if _upgrade_service != null:
		_upgrade_service.select_card(card_id)
	
	if _dialog_view != null:
		_dialog_view.close()


func _on_reroll_pressed() -> void:
	if _upgrade_service != null:
		var res := _upgrade_service.reroll()
		if res.is_err():
			ToastManager.show("无法刷新: %s" % res.error_message())


func _on_model_data_changed() -> void:
	_update_view()


func _update_view() -> void:
	if _dialog_view != null and _upgrade_model != null:
		_dialog_view.render_cards(_upgrade_model.candidate_cards, _upgrade_model.rerolls_left)
