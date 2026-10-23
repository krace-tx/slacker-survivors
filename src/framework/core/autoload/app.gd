extends Node
## 全局服务聚合根 (Autoload / Service Locator)
## 统一持有各子系统的强类型引用，提供全局访问点。
## 接管并分发 OS 层面的生命周期与系统级事件。

#region Core Subsystems
var env:		BaseRuntimeEnvironment	## 基础：运行环境 (Local/Emulator/Dev/Test/Prod)
var logger:		BaseFrameworkLogger		## 基础：日志与诊断
var net:		BaseNetworkClient		## 通讯：HTTP连接池、断线重连、Token鉴权
var auth:		BaseAuthSystem			## 鉴权：跨平台身份认证 (Steam/Apple/Google/Guest) 与网关换票
var storage:	BaseStorageSystem		## 存储：内存/磁盘/远端三级读写 (含 Steam Cloud & HTTP 云存档)
var clock:		BaseClockSystem			## 时钟：防作弊单调时钟与服务器权威时间校准
var locale:		BaseLocalizationSystem	## 表现：多语言与区域格式化
var asset:		BaseAssetSystem			## 资源：资产加载池、内存/磁盘缓存管理
var input:		BaseInputSystem			## 输入：键鼠/手柄双轨映射、组合键求值与交互改键
var scene:		BaseSceneRouter			## 表现：场景流转与转场遮罩
var display:	BaseDisplaySystem		## 表现：显示控制、异形屏安全区与全局画布分层
var audio:		BaseAudioSystem			## 表现：音效分组与交叉淡变
var haptic:		BaseHapticFeedback		## 表现：触觉振动调度与统一裁决
var video:		BaseVideoPlayer			## 表现：视频播放器控制门面 (开源插件桥接 / 原生保底)
#endregion

#region Runtime Lifecycle
var _boot_done := false
var _booting := false
var _boot_result: Result = null
var _runtime: FrameworkRuntime = null
var _is_app_paused := false
var _is_quitting := false


## 获取当前 FrameworkRuntime 状态与启动诊断指标快照。
func get_runtime_diagnostics() -> Dictionary:
	if _runtime == null:
		return {"state": "UNINITIALIZED", "initialized": false}
	return _runtime.get_diagnostics()


## 初始化 Framework 内核。App 只负责生命周期，具体服务装配由 FrameworkRuntime 完成。
## [param on_progress] 内核组件安装进度回调: Callable(step_idx: int, total_steps: int, service_key: String)
func bootstrap(on_progress: Callable = Callable()) -> Result:
	if _boot_done:
		if on_progress.is_valid():
			on_progress.call(14, 14, "ready")
		return _boot_result
	if _booting:
		while _booting:
			await get_tree().process_frame
		return _boot_result if _boot_result != null else Result.err_code("Core.BootFailed", "Framework bootstrap did not produce a result.")
	_booting = true
	_boot_result = null
	_runtime = FrameworkRuntime.new()
	_boot_result = await _runtime.initialize(self, on_progress)
	_boot_done = _boot_result.is_ok()
	_booting = false
	if _boot_result.is_err():
		FrameworkLogger.print_raw(LogLevel.ERROR, "App", "Framework bootstrap failed: %s" % _boot_result.error_message())
		_runtime = null
	return _boot_result
#endregion

#region System Lifecycle
func _ready() -> void:
	# 禁用引擎的“收到退出信号立刻强制关闭”行为，交由 _on_app_quit 统一处理
	get_tree().set_auto_accept_quit(false)
	# 延迟保底：若独立调试非 SplashScene 场景（按 F6 运行），保证底层内核服务按需就绪
	call_deferred("_ensure_standalone_bootstrap")


func _exit_tree() -> void:
	if _runtime != null:
		_runtime.dispose()
		_runtime = null
		_boot_done = false
		_boot_result = null


func _ensure_standalone_bootstrap() -> void:
	if not _boot_done and not _booting:
		var current := get_tree().current_scene
		var res := await bootstrap()
		if res.is_ok() and scene != null and scene.is_empty() and is_instance_valid(current) and current is BaseScene:
			await scene.bind(current.scene_file_path, current as BaseScene)


func _notification(what: int) -> void:
	match what:
		# 1. 移动端：挂起与恢复
		NOTIFICATION_APPLICATION_PAUSED:  _on_app_paused()
		NOTIFICATION_APPLICATION_RESUMED: _on_app_resumed()
		
		# 2. PC端：窗口焦点切换
		NOTIFICATION_WM_WINDOW_FOCUS_OUT: _on_app_focus_out()
		NOTIFICATION_WM_WINDOW_FOCUS_IN:  _on_app_focus_in()
		
		# 3. 硬件交互：物理返回键 / ESC
		NOTIFICATION_WM_GO_BACK_REQUEST:  _on_app_go_back()
		
		# 4. 系统管控：优雅退出与内存警告
		NOTIFICATION_WM_CLOSE_REQUEST:    _on_app_quit()
		NOTIFICATION_OS_MEMORY_WARNING:   _on_app_low_memory()
#endregion

#region Internal Event Handlers
## 切后台：落盘存档并广播 Bus.app_paused。
func _on_app_paused() -> void:
	if _is_app_paused:
		return
	_is_app_paused = true
	if logger != null:
		logger.info("app", "App paused.")
	Bus.app_paused.emit()


## 回前台：异步重同步，并立即广播 Bus.app_resumed。
func _on_app_resumed() -> void:
	if not _is_app_paused:
		return
	_is_app_paused = false
	if logger != null:
		logger.info("app", "App resumed.")
	Bus.app_resumed.emit()


## 窗口失焦（PC/桌面端）：暂停音频并触发 App 挂起逻辑。
func _on_app_focus_out() -> void:
	if logger != null:
		logger.info("app", "App focus out.")
	if audio != null:
		audio.set_paused(true)
	_on_app_paused()


## 窗口获焦（PC/桌面端）：恢复音频并触发 App 恢复逻辑。
func _on_app_focus_in() -> void:
	if logger != null:
		logger.info("app", "App focus in.")
	if audio != null:
		audio.set_paused(false)
	_on_app_resumed()


## 返回键 / ESC / 侧滑返回：广播 Bus.app_back_pressed。
func _on_app_go_back() -> void:
	if logger != null:
		logger.info("app", "App back pressed.")
	Bus.app_back_pressed.emit()


## 关闭请求：等待异步落盘与逆序关闭协议（shutdown_async）完成后允许退出（auto_accept_quit 已关闭）。
func _on_app_quit() -> void:
	if _is_quitting:
		return
	_is_quitting = true
	if logger != null:
		logger.info("app", "App quit requested; running graceful shutdown.")
	if _runtime != null:
		await _runtime.shutdown_async()
		_runtime = null
		_boot_done = false
		_boot_result = null
	get_tree().quit()


## 系统内存警告：释放资源缓存。
func _on_app_low_memory() -> void:
	if logger != null:
		logger.warn("app", "App low memory: flushing asset cache.")
	if asset != null:
		asset.clear()
#endregion
