extends Node

## 全局服务聚合根（Autoload / Service Locator）。[br]
##
## [b]核心职责：[/b][br]
## 1. [b]强类型门面聚合[/b]：统一持有 15 大核心子系统的抽象门面（[code]Base*[/code]）引用，供业务层通过 [code]App.<service>[/code] 访问；[br]
## 2. [b]单飞幂等启动[/b]：通过 [method bootstrap] 委托唯一组合根 [FrameworkRuntime] 完成依赖拓扑校验与显式注入装配，支持多协程信号合并等待与进度广播；[br]
## 3. [b]OS 生命周期中枢[/b]：统一接管桌面/移动端的焦点切换、前后台挂起（自动刷盘保护）、物理返回键、低内存泄压与优雅退出协议。

## 当内核启动流程结束（成功或失败）时触发
signal bootstrap_completed(result: Result)

const _LOG_TAG: String = "App"
const _ERR_BOOT_FAILED: String = "Core.BootFailed"

#region Core Subsystems
var env:		BaseRuntimeEnvironment	## 基础：运行环境 (Local/Emulator/Dev/Test/Staging/Prod)
var logger:		BaseFrameworkLogger		## 基础：分级日志、染色输出与环形诊断缓冲
var clock:		BaseClockSystem			## 基础：防作弊单调时钟与服务器权威时间校准
var asset:		BaseAssetSystem			## 资源：同步缓存直通、并发加载合并与 LRU 预算池
var input:		BaseInputSystem			## 输入：键鼠/手柄双轨映射、组合键求值与交互改键
var haptic:		BaseHapticFeedback		## 表现：三端触觉反馈、高优防打断与怪潮节流
var net:		BaseNetworkClient		## 通讯：有界并发 HTTP 队列、退避重试与流式下载
var auth:		BaseAuthSystem			## 鉴权：跨平台身份取证 (Steam/Apple/Google/Guest) 与网关换票
var storage:	BaseStorageSystem		## 存储：L1 内存 + L2 磁盘 (.tmp/.bak 自愈) + L3 云端三级存储
var locale:		BaseLocalizationSystem	## 表现：多语言区域切换与缺省回退
var scene:		BaseSceneRouter			## 表现：顶层场景栈路由与流式视觉转场
var display:	BaseDisplaySystem		## 表现：窗口状态机、异形屏安全区逆矩阵与全局画布分层
var cursor:		BaseCursorSystem		## 表现：自定义鼠标光标、五层交互优先级与粒子伴生
var audio:		BaseAudioSystem			## 表现：零协程缓存音效池、BGM 交叉淡变与正交音画避让
var video:		BaseVideoPlayer			## 表现：跨平台视频播放门面 (FFmpeg / 移动原生 / Theora 保底)
#endregion

#region Runtime State
var _runtime: FrameworkRuntime = null
var _boot_result: Result = null
var _progress_callbacks: Array[Callable] = []
var _boot_done: bool = false
var _booting: bool = false
var _is_app_paused: bool = false
var _is_quitting: bool = false
#endregion


#region Public Queries & Bootstrap API
## 当前 Framework 内核是否已完成初始化并处于就绪状态。
func is_bootstrapped() -> bool:
	return _boot_done


## 当前应用是否处于后台挂起或窗口失焦状态。
func is_paused() -> bool:
	return _is_app_paused


## 当前应用是否正在执行退出关闭流程。
func is_quitting() -> bool:
	return _is_quitting


## 获取当前 [FrameworkRuntime] 状态与各模块启动耗时诊断快照。
func get_runtime_diagnostics() -> Dictionary:
	if _runtime == null:
		return {"state": "UNINITIALIZED", "initialized": false}
	return _runtime.get_diagnostics()


## 初始化 Framework 内核（单飞幂等：支持多调用方并发 `await`，共享同一次装配进度与结果）。[br]
## [param on_progress] 内核组件安装进度回调：[code]Callable(step_idx: int, total_steps: int, service_key: String)[/code]。
func bootstrap(on_progress: Callable = Callable()) -> Result:
	if _boot_done and _boot_result != null:
		if on_progress.is_valid():
			var total := RuntimeManifest.total_steps()
			on_progress.call(total, total, "ready")
		return _boot_result

	if on_progress.is_valid() and not _progress_callbacks.has(on_progress):
		_progress_callbacks.append(on_progress)

	if _booting:
		var wait_res: Result = await bootstrap_completed
		return wait_res if wait_res != null else Result.err_code(_ERR_BOOT_FAILED, "Framework bootstrap did not produce a result.")

	_booting = true
	_boot_result = null
	_runtime = FrameworkRuntime.new()
	_boot_result = await _runtime.initialize(self, _dispatch_boot_progress)
	_boot_done = _boot_result.is_ok()
	_booting = false
	_progress_callbacks.clear()

	if _boot_result.is_err():
		_log_error("Framework bootstrap failed: %s" % _boot_result.error_message())
		_runtime = null

	bootstrap_completed.emit(_boot_result)
	return _boot_result
#endregion


#region Engine Lifecycle & OS Notifications
func _ready() -> void:
	# 禁用引擎收到关闭信号立即强退的默认行为，交由 _on_app_quit 执行异步落盘与逆序停机
	get_tree().set_auto_accept_quit(false)
	# 延迟保底：若在编辑器中直接按 F6 独立运行非 BootstrapScene 场景，自动拉起内核并绑定当前场景
	call_deferred("_ensure_standalone_bootstrap")


func _exit_tree() -> void:
	if _runtime != null:
		_runtime.dispose()
		_runtime = null
		_boot_done = false
		_boot_result = null


func _ensure_standalone_bootstrap() -> void:
	if _boot_done or _booting:
		return
	var current := get_tree().current_scene
	var res := await bootstrap()
	if res.is_ok() and scene != null and scene.is_empty() and is_instance_valid(current) and current is BaseScene:
		await scene.bind(current.scene_file_path, current as BaseScene)


func _notification(what: int) -> void:
	match what:
		# 1. 移动端：应用切后台挂起与回前台恢复
		NOTIFICATION_APPLICATION_PAUSED:
			_on_app_paused()
		NOTIFICATION_APPLICATION_RESUMED:
			_on_app_resumed()

		# 2. 桌面端：窗口焦点切出与切入
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_on_app_focus_out()
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_on_app_focus_in()

		# 3. 硬件交互：Android 物理返回键 / 侧滑返回
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_on_app_go_back()

		# 4. 系统管控：窗口关闭请求与 OS 低内存警告
		NOTIFICATION_WM_CLOSE_REQUEST:
			_on_app_quit()
		NOTIFICATION_OS_MEMORY_WARNING:
			_on_app_low_memory()
#endregion


#region Internal Event Handlers
func _dispatch_boot_progress(step_idx: int, total_steps: int, service_key: String) -> void:
	for cb in _progress_callbacks.duplicate():
		if cb.is_valid():
			cb.call(step_idx, total_steps, service_key)


## 切入后台或窗口失焦：主动刷盘进行中的存储写入并广播 [signal EventBus.app_paused]。
func _on_app_paused() -> void:
	if _is_app_paused:
		return
	_is_app_paused = true
	_log_info("App paused.")
	if storage != null:
		storage.flush_async()
	Bus.app_paused.emit()


## 回到前台或窗口获焦：广播 [signal EventBus.app_resumed]。
func _on_app_resumed() -> void:
	if not _is_app_paused:
		return
	_is_app_paused = false
	_log_info("App resumed.")
	Bus.app_resumed.emit()


## 桌面窗口失焦：汇总进入挂起流（具体后台静音与后台降帧由 GameSettingsService 监听 Bus.app_paused 统一裁决）。
func _on_app_focus_out() -> void:
	_log_info("Window focus out.")
	_on_app_paused()


## 桌面窗口获焦：汇总进入恢复流。
func _on_app_focus_in() -> void:
	_log_info("Window focus in.")
	_on_app_resumed()


## 硬件返回请求：广播 [signal EventBus.app_back_pressed]。
func _on_app_go_back() -> void:
	_log_info("System back requested.")
	Bus.app_back_pressed.emit()


## 优雅退出：等待异步落盘与逆序停机协议（`shutdown_async`）完成后退出进程。
func _on_app_quit() -> void:
	if _is_quitting:
		return
	_is_quitting = true
	_log_info("Quit requested; running graceful shutdown...")
	if _runtime != null:
		await _runtime.shutdown_async()
		_runtime = null
		_boot_done = false
		_boot_result = null
	get_tree().quit()


## 系统低内存警告：清理非钉住资源池与视频预热流缓存。
func _on_app_low_memory() -> void:
	_log_warn("OS low memory warning received; flushing non-pinned caches.")
	if asset != null:
		asset.clear()
	if video != null:
		video.clear_cache()


func _log_info(msg: String) -> void:
	if logger != null:
		logger.info(_LOG_TAG, msg)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, _LOG_TAG, msg)


func _log_warn(msg: String) -> void:
	if logger != null:
		logger.warn(_LOG_TAG, msg)
	else:
		FrameworkLogger.print_raw(LogLevel.WARN, _LOG_TAG, msg)


func _log_error(msg: String) -> void:
	if logger != null:
		logger.error(_LOG_TAG, msg)
	else:
		FrameworkLogger.print_raw(LogLevel.ERROR, _LOG_TAG, msg)
#endregion
