class_name SoulsArenaScene
extends BaseScene

## 3D 魂系闪避/弹反/处决与 FSM+BT 抽象语法树演练场主场景（位于 src/test/souls_arena/view/scene/arena/，遵循 `BaseScene` 规范）。[br]
##
## [b]解构与职责边界（6 大独立子场景组合）：[/b][br]
## 1. 3D 舞台层：组合 [SoulsArenaStage3D]（18.5m 宏大古战场子场景）、[SoulsCameraRig3D]（第三人称平滑跟随与目标锁定相机子场景）及双 [SoulsFighterActor]（玩家与 1800 HP Boss 实体子场景）；[br]
## 2. 2D 视图层：由 [SoulsArenaView] 组合 [SoulsCombatHudBar]（纯净核心 HUD 子场景）、[SoulsKeybindHelpDialog]（独立键位教学弹窗子场景）与 [SoulsBlueprintDialog]（独立 AST 蓝图弹窗子场景）；[br]
## 3. 协调层：将全部 3D 操控、锁定镜头与 AI 决策委托给 [SoulsArenaPresenter]。


#region 节点引用

@onready var _arena_view: SoulsArenaView = $ArenaView as SoulsArenaView
@onready var _arena_stage_3d: SoulsArenaStage3D = %ArenaStage3D as SoulsArenaStage3D
@onready var _camera_rig_3d: SoulsCameraRig3D = %CameraRig3D as SoulsCameraRig3D
@onready var _player_actor: SoulsFighterActor = %PlayerActor as SoulsFighterActor
@onready var _boss_actor: SoulsFighterActor = %BossActor as SoulsFighterActor

#endregion


#region 私有变量

var _presenter: SoulsArenaPresenter = null

#endregion


#region 生命周期

func _on_enter(_params: BaseParams = null) -> void:
	if _arena_stage_3d != null:
		_arena_stage_3d.build_stage()

	_player_actor.setup_actor(
		"灰烬骑士 (玩家)",
		false,
		Color(0.20, 0.72, 0.98),
		SoulsArenaService.PLAYER_SPAWN_POS
	)
	_boss_actor.setup_actor(
		"深渊铁卫 · 玛尔斯",
		true,
		Color(0.86, 0.22, 0.26),
		SoulsArenaService.BOSS_SPAWN_POS
	)
	_player_actor.target_opponent = _boss_actor
	_boss_actor.target_opponent = _player_actor

	if _presenter != null:
		_presenter.unbind()
	_presenter = SoulsArenaPresenter.new(_arena_view, _camera_rig_3d, _player_actor, _boss_actor)
	_presenter.bind()


func _on_exit() -> void:
	_cleanup_presenter()


func _exit_tree() -> void:
	_cleanup_presenter()


func _cleanup_presenter() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null
	if _player_actor != null:
		_player_actor.target_opponent = null
	if _boss_actor != null:
		_boss_actor.target_opponent = null


func _process(delta: float) -> void:
	if _presenter != null:
		_presenter.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _presenter != null:
		_presenter.handle_unhandled_input(event)

#endregion
