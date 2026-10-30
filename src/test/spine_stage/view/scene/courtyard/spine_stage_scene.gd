class_name SpineStageScene
extends BaseScene

## 2.5D「3D 场景实时光影投射阴影 + Spine 2D 骨骼角色跑跳攻击 + 实时换装（方案 B）」原型根场景。[br]
##
## [b]架构职责：[/b][br]
## 1. 继承 [BaseScene]，统一支持通过 [code]App.scene.replace()[/code] 路由进入或编辑器 [code]F6[/code] 直接独立运行；[br]
## 2. 托管场景级 [SpinePool] 对象池，为 [code]%PlayerActor[/code] 与两尊 [code]%Dummy*Actor[/code] 零分配挂载 [code]SpineSprite[/code]，并将木偶注册至 `30 FPS` 错峰分频更新；[br]
## 3. 组装 [SpineStageService] 与 [SpineStagePresenter]，在退栈时确定性释放池化实例与信号订阅。

#region Exports & Node Refs
@export var hero_skeleton_data: Resource = null
@export var dummy_skeleton_data: Resource = null

@onready var _courtyard_stage: SpineCourtyardStage3D = %CourtyardStage3D as SpineCourtyardStage3D
@onready var _camera_rig: SpineCameraRig3D = %CameraRig3D as SpineCameraRig3D
@onready var _player_actor: SpineActor3D = %PlayerActor as SpineActor3D
@onready var _dummy_left_actor: SpineActor3D = %DummyLeftActor as SpineActor3D
@onready var _dummy_right_actor: SpineActor3D = %DummyRightActor as SpineActor3D
@onready var _stage_view: SpineStageView = %UI as SpineStageView

var _spine_pool: SpinePool = null
var _service: SpineStageService = null
var _presenter: SpineStagePresenter = null
#endregion


#region Lifecycle
func _ready() -> void:
	_setup_stage_if_needed()


func _on_enter(_params: BaseParams = null) -> void:
	_setup_stage_if_needed()
	if App.logger != null:
		App.logger.info(
			"SpineStage",
			"Entered 2.5D Scheme-B stage (Rev2D -> SpineSprite + SubViewport -> Shaded Sprite3D)."
		)


func _on_exit() -> void:
	_teardown_stage()


func _exit_tree() -> void:
	super._exit_tree()
	_teardown_stage()


func _physics_process(delta: float) -> void:
	if _presenter != null:
		_presenter.physics_tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _presenter != null:
		_presenter.handle_unhandled_input(event)
#endregion


#region Public Test Accessors
## 获取当前舞台协调器实例（供自动化冒烟验证调用）。
func get_presenter() -> SpineStagePresenter:
	return _presenter


## 获取当前领域服务实例（供自动化冒烟验证读取状态）。
func get_service() -> SpineStageService:
	return _service
#endregion


#region Internal Assembly & Teardown
func _setup_stage_if_needed() -> void:
	if _presenter != null:
		return

	_spine_pool = SpinePool.new(self)
	var hero_res: Resource = _resolve_skeleton_resource(hero_skeleton_data, SpineStageConfig.HERO_SPINE_DATA_PATH)
	var dummy_res: Resource = _resolve_skeleton_resource(dummy_skeleton_data, SpineStageConfig.DUMMY_SPINE_DATA_PATH)

	if _player_actor != null:
		_player_actor.position = SpineStageConfig.PLAYER_SPAWN_POS
		_player_actor.mount_from_pool(_spine_pool, hero_res)
		_player_actor.set_facing_right(true, true)

	if _dummy_left_actor != null:
		_dummy_left_actor.position = SpineStageConfig.DUMMY_LEFT_POS
		_dummy_left_actor.mount_from_pool(_spine_pool, dummy_res)
		_dummy_left_actor.set_facing_right(true, true)

	if _dummy_right_actor != null:
		_dummy_right_actor.position = SpineStageConfig.DUMMY_RIGHT_POS
		_dummy_right_actor.mount_from_pool(_spine_pool, dummy_res)
		_dummy_right_actor.set_facing_right(false, true)

	_service = SpineStageService.new()
	var dummies: Array[SpineActor3D] = [_dummy_left_actor, _dummy_right_actor]
	var homes: Array[Vector3] = [SpineStageConfig.DUMMY_LEFT_POS, SpineStageConfig.DUMMY_RIGHT_POS]

	_presenter = SpineStagePresenter.new(
		_service,
		_stage_view,
		_courtyard_stage,
		_camera_rig,
		_player_actor,
		dummies,
		homes
	)
	_presenter.bind()
	if _stage_view != null and not _stage_view.is_opened():
		_stage_view.open()


func _resolve_skeleton_resource(exported_res: Resource, fallback_path: String) -> Resource:
	if exported_res != null:
		return exported_res
	if App.asset != null:
		var cached: Resource = App.asset.get_cached(fallback_path)
		if cached != null:
			return cached
	return load(fallback_path) as Resource


func _teardown_stage() -> void:
	if _presenter != null:
		_presenter.dispose()
		_presenter = null
	_service = null
	if _player_actor != null:
		_player_actor.release_spine()
	if _dummy_left_actor != null:
		_dummy_left_actor.release_spine()
	if _dummy_right_actor != null:
		_dummy_right_actor.release_spine()
	if _spine_pool != null:
		_spine_pool.dispose()
		_spine_pool = null
#endregion
