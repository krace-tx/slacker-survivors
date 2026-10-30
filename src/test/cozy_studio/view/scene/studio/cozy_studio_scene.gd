class_name CozyStudioScene
extends BaseScene

## 2.5D 温馨二次元工作室测试舞台根场景（继承 `BaseScene`，组合 3D 房间、三段式跟随相机、序列帧立牌角色与轻量操控 HUD）。

const _SLACKER_SHEET_PATH: String = "res://src/test/cozy_studio/assets/textures/spr_cozy_studio_slacker_sheet.png"
const _PARTNER_TEX_PATH: String = "res://src/test/cozy_studio/assets/textures/spr_cozy_studio_partner_idle.png"

@onready var _studio_stage: CozyStudioStage3D = %StudioStage3D as CozyStudioStage3D
@onready var _camera_rig: CozyCameraRig3D = %CameraRig as CozyCameraRig3D
@onready var _player_actor: CozyStandeeActor3D = %SlackerActor as CozyStandeeActor3D
@onready var _partner_actor: CozyStandeeActor3D = %PartnerActor as CozyStandeeActor3D
@onready var _ui_view: CozyStudioView = %UI as CozyStudioView

var _presenter: CozyStudioPresenter = null


func _ready() -> void:
	_setup_scene_if_needed()


func _on_enter(_params: BaseParams = null) -> void:
	_setup_scene_if_needed()
	if App.logger != null:
		App.logger.info("CozyStudio", "Entered 2.5D Cozy Studio test scene (CameraRig + Walk Sheet).")


func _on_exit() -> void:
	_cleanup_presenter()


func _exit_tree() -> void:
	super._exit_tree()
	_cleanup_presenter()


func _process(delta: float) -> void:
	if _presenter != null:
		_presenter.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _presenter != null:
		_presenter.handle_unhandled_input(event)


func _setup_scene_if_needed() -> void:
	if _presenter != null:
		return
	var slacker_sheet: Texture2D = load(_SLACKER_SHEET_PATH) as Texture2D
	var partner_tex: Texture2D = load(_PARTNER_TEX_PATH) as Texture2D
	if _player_actor != null:
		_player_actor.idle_phase_offset = 0.0
		_player_actor.setup_character_sheet(slacker_sheet, 4, 6, 1.62)
	if _partner_actor != null:
		_partner_actor.idle_phase_offset = 1.65
		_partner_actor.setup_character(partner_tex, 1.54)

	_presenter = CozyStudioPresenter.new(
		_ui_view,
		_studio_stage,
		_camera_rig,
		_player_actor,
		_partner_actor
	)
	_presenter.bind()


func _cleanup_presenter() -> void:
	if _presenter != null:
		_presenter.unbind()
		_presenter = null
