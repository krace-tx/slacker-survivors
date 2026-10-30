class_name OtomeTerraceScene
extends BaseScene

## 乙女向 2.5D 户外庭院「晴风湖畔 · 花树咖啡露台」测试主场景。[br]
##
## [b]架构职责：[/b][br]
## 1. 继承 [BaseScene]，统一支持通过 [code]App.scene.replace()[/code] 路由切换或编辑器 [code]F6[/code] 直接独立运行；[br]
## 2. 托管场景级 [SpinePool] 对象池，为男主 [code]%HeroActor[/code]（[OtomeActor3D]）零分配挂载 [code]Rev2D -> Spine 4.2[/code] 骨骼实例；[br]
## 3. 组装 [OtomeTerraceService] 与 [OtomeTerracePresenter]，退栈时确定性释放池化实例与信号订阅。

#region Exports & Node Refs
@export var hero_skeleton_data: Resource = null
@export var bust_skeleton_data: Resource = null

@onready var _terrace_stage: OtomeTerraceStage3D = %TerraceStage3D as OtomeTerraceStage3D
@onready var _camera_rig: OtomeCameraRig3D = %CameraRig3D as OtomeCameraRig3D
@onready var _hero_actor: OtomeActor3D = %HeroActor as OtomeActor3D
@onready var _terrace_view: OtomeTerraceView = %UI as OtomeTerraceView

var _spine_pool: SpinePool = null
var _service: OtomeTerraceService = null
var _presenter: OtomeTerracePresenter = null
#endregion


#region Lifecycle
func _ready() -> void:
	_setup_terrace_if_needed()


func _on_enter(_params: BaseParams = null) -> void:
	_setup_terrace_if_needed()
	if App.logger != null:
		App.logger.info(
			"OtomeTerrace",
			"Entered Lakeside Blossom Terrace (Blender MCP 3D Stage + Rev2D Spine 4.2 Hero)."
		)


func _on_exit() -> void:
	_teardown_terrace()


func _exit_tree() -> void:
	super._exit_tree()
	_teardown_terrace()


func _physics_process(delta: float) -> void:
	if _presenter != null:
		_presenter.physics_tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _presenter != null:
		_presenter.handle_unhandled_input(event)
#endregion


#region Public Test Accessors
## 获取当前协调器实例（供自动化截图与冒烟测试调用）。
func get_presenter() -> OtomeTerracePresenter:
	return _presenter


## 获取当前领域服务实例（供自动化冒烟测试读取状态）。
func get_service() -> OtomeTerraceService:
	return _service
#endregion


#region Internal Assembly & Teardown
func _setup_terrace_if_needed() -> void:
	if _presenter != null:
		return

	_spine_pool = SpinePool.new(self)
	var skel_res: Resource = _resolve_skeleton_resource(
		hero_skeleton_data,
		OtomeTerraceConfig.HERO_SPINE_DATA_PATH
	)
	var bust_skel_res: Resource = _resolve_skeleton_resource(
		bust_skeleton_data,
		OtomeTerraceConfig.BUST_SPINE_DATA_PATH
	)

	if _hero_actor != null:
		_hero_actor.position = OtomeTerraceConfig.HERO_SPAWN_POS
		_hero_actor.mount_from_pool(_spine_pool, skel_res)
		_hero_actor.set_facing_right(true, true)

	if _terrace_view != null:
		_terrace_view.mount_bust_from_pool(_spine_pool, bust_skel_res)

	_service = OtomeTerraceService.new()
	_presenter = OtomeTerracePresenter.new(
		_service,
		_terrace_view,
		_terrace_stage,
		_camera_rig,
		_hero_actor
	)
	_presenter.bind()
	if _terrace_view != null and not _terrace_view.is_opened():
		_terrace_view.open()
	_apply_cmdline_showcase_preset()


func _apply_cmdline_showcase_preset() -> void:
	if _presenter == null or _service == null:
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--otome-preset=roam":
			_service.select_outfit(0, false)
			_service.select_expr(0)
		elif arg == "--otome-preset=coffee":
			_presenter.enter_hotspot_immediately(OtomeTerraceConfig.HotspotId.COFFEE_CART)
		elif arg == "--otome-preset=blossom-blush":
			_presenter.enter_hotspot_immediately(OtomeTerraceConfig.HotspotId.BLOSSOM_BENCH)
			_service.choose_dialogue_option(1)
		elif arg == "--otome-preset=sunset":
			_service.toggle_weather_mode()
			_service.select_outfit(2, true)
			_service.trigger_greeting()
			if _hero_actor != null:
				_hero_actor.play_greeting_once()


func _resolve_skeleton_resource(exported_res: Resource, fallback_path: String) -> Resource:
	if exported_res != null:
		return exported_res
	if App.asset != null:
		var cached: Resource = App.asset.get_cached(fallback_path)
		if cached != null:
			return cached
	return load(fallback_path) as Resource


func _teardown_terrace() -> void:
	if _presenter != null:
		_presenter.dispose()
		_presenter = null
	_service = null
	if _terrace_view != null:
		_terrace_view.release_bust_spine()
	if _hero_actor != null:
		_hero_actor.release_spine()
	if _spine_pool != null:
		_spine_pool.dispose()
		_spine_pool = null
#endregion
