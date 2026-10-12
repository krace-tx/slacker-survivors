class_name BattleScene
extends BaseScene

## 战斗主场景（Battle Scene）。[br]
## 继承 [BaseScene]，负责管理战斗 HUD、局内升级弹窗、敌人生成循环与游戏主状态。

@onready var _hud_view: BattleHudView = $UI

var _hud_model: BattleHudModel
var _hud_service: BattleHudService
var _hud_presenter: BattleHudPresenter

var _upgrade_presenter: UpgradeSelectionPresenter
var _is_battle_active: bool = false


func _on_enter(_params: Dictionary = {}) -> void:
	# 1. 组装战斗 HUD (MSVP 架构)
	_hud_model = BattleHudModel.new()
	_hud_service = BattleHudService.new(_hud_model)
	_hud_presenter = BattleHudPresenter.new()
	_hud_presenter.bind(_hud_view, _hud_model, _hud_service)
	
	# 2. 监听业务总线上的肉鸽升级事件
	if Bus != null:
		Bus.on(GameEvents.BATTLE_LEVEL_UP, _on_level_up)
		Bus.on(GameEvents.BATTLE_FINISHED, _on_battle_finished)
	
	_is_battle_active = true
	App.logger.info("Battle", "Battle scene started.")


func _on_exit() -> void:
	_is_battle_active = false
	if Bus != null:
		Bus.off(GameEvents.BATTLE_LEVEL_UP, _on_level_up)
		Bus.off(GameEvents.BATTLE_FINISHED, _on_battle_finished)
	
	if _hud_presenter != null:
		_hud_presenter.unbind()
		_hud_presenter = null
	_hud_model = null
	_hud_service = null


func _process(delta: float) -> void:
	if not _is_battle_active or _hud_service == null:
		return
	
	# 驱动战斗计时
	_hud_service.tick_timer(delta)


func _on_level_up(_payload: Dictionary) -> void:
	App.logger.info("Battle", "Opening UpgradeSelectionDialog for level up.")
	
	# 唤起升级选卡弹窗 (通过 DialogManager.open)
	var dialog_path := "res://src/game/features/battle/upgrade_selection/upgrade_selection_dialog.tscn"
	var dialog := (await DialogManager.open(dialog_path)) as UpgradeSelectionDialog
	
	if dialog != null:
		var up_model := UpgradeSelectionModel.new()
		var up_service := UpgradeSelectionService.new(up_model)
		_upgrade_presenter = UpgradeSelectionPresenter.new()
		_upgrade_presenter.bind(dialog, up_model, up_service)


func _on_battle_finished(payload: Dictionary) -> void:
	var is_victory: bool = payload.get("is_victory", false)
	App.logger.info("Battle", "Battle finished: Victory=%s" % is_victory)
	
	ToastManager.show("战斗结束！正在返回大厅...")
	
	# 延迟 1 秒平滑返回大厅
	await get_tree().create_timer(1.0).timeout
	if App.scene != null:
		App.scene.replace(GameConstants.SCENE_LOBBY)
