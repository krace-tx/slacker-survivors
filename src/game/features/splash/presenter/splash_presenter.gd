class_name SplashPresenter
extends RefCounted

## 闪屏加载模块视图调度器（位于 src/game/features/splash/presenter/）。[br]
##
## [b]核心职责（遵循 MSVP 的 `Presenter` 规范）：[/b][br]
## 1. 作为薄胶水层连接 [SplashScene] (View)、[SplashBootService] (Service) 与 [SplashBootState] (Model)；[br]
## 2. 监听 [signal SplashBootState.state_changed] 状态变更，将数据映射为纯净视图指令驱动 [SplashScene] 渲染；[br]
## 3. 监听 [signal SplashScene.retry_requested] 用户交互信号，委托 [SplashBootService] 执行断点重试；[br]
## 4. 在业务启动管线全部完成后，按 [member SplashBootContext.target_scene_path] 调度首屏场景路由跳转。

#region Constants & State
const _ERR_BUSY: String = "Splash.Busy"
const _ERR_CANNOT_RETRY: String = "Splash.CannotRetry"

var _view: SplashScene = null
var _state: SplashBootState = null
var _context: SplashBootContext = null
var _service: SplashBootService = null
var _is_running: bool = false
var _disposed: bool = false
#endregion


#region Public API
func _init(view: SplashScene, params: BaseParams = null) -> void:
	_view = view
	_state = SplashBootState.new()
	_context = SplashBootContext.new()
	_context.game_settings = GameSettingsService.get_current()

	if params is SplashEnterParams:
		var enter := params as SplashEnterParams
		_context.override_target_scene = enter.override_target_scene
		_context.override_target_params = enter.override_target_params
	elif params is SplashBootContext:
		_context = params as SplashBootContext

	_service = SplashBootService.new(_state, _context)
	_bind_signals()


## 启动闪屏业务加载流程
func start() -> Result:
	if _disposed or _is_running:
		return Result.err_code(_ERR_BUSY, "SplashPresenter is already running or disposed.")
	_is_running = true
	var res := await _service.start_boot_sequence()
	_is_running = false
	await _on_sequence_finished(res)
	return res


## 响应重试请求，从失败断点处原地续跑
func retry() -> Result:
	if _disposed or _is_running:
		return Result.err_code(_ERR_CANNOT_RETRY, "SplashPresenter cannot retry right now.")
	_is_running = true
	var res := await _service.retry_failed()
	_is_running = false
	await _on_sequence_finished(res)
	return res


## 销毁并解绑所有信号监听（由 [method SplashScene._on_exit] 调用）
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if _state != null and _state.state_changed.is_connected(_on_state_changed):
		_state.state_changed.disconnect(_on_state_changed)
	if _view != null and is_instance_valid(_view) and _view.retry_requested.is_connected(_on_view_retry_requested):
		_view.retry_requested.disconnect(_on_view_retry_requested)
	_view = null


## 获取底层领域服务实例（供自动化测试注入或断言）
func get_service() -> SplashBootService:
	return _service


## 获取当前启动共享上下文
func get_context() -> SplashBootContext:
	return _context


## 获取当前运行时状态模型
func get_state() -> SplashBootState:
	return _state
#endregion


#region Internal Signal Handlers & Navigation
func _bind_signals() -> void:
	if _state != null and not _state.state_changed.is_connected(_on_state_changed):
		_state.state_changed.connect(_on_state_changed)
	if _view != null and not _view.retry_requested.is_connected(_on_view_retry_requested):
		_view.retry_requested.connect(_on_view_retry_requested)


func _on_state_changed() -> void:
	if _disposed or _view == null or not is_instance_valid(_view):
		return
	match _state.phase:
		SplashBootState.Phase.RUNNING, SplashBootState.Phase.IDLE:
			_view.render_progress(_state.progress_ratio, _state.status_text)
		SplashBootState.Phase.FAILED:
			_view.render_error(_state.status_text)
		SplashBootState.Phase.COMPLETED:
			_view.render_completed(_state.status_text)


func _on_view_retry_requested() -> void:
	retry()


func _on_sequence_finished(res: Result) -> void:
	if _disposed or res.is_err():
		return

	var target_path := _context.target_scene_path
	if not target_path.is_empty() and ResourceLoader.exists(target_path) and App.scene != null:
		await App.scene.replace(target_path, _context.target_scene_params, SceneTransitionType.AUTO)
#endregion
