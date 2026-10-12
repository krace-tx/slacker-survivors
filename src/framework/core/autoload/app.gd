extends Node
## 全局服务聚合根 (Autoload / Service Locator)
## 统一持有各子系统的强类型引用，提供全局访问点。
## 接管并分发 OS 层面的生命周期与系统级事件。

#region Core Subsystems
var env:		BaseRuntimeEnvironment	## 基础：运行环境 (Local/Emulator/Dev/Test/Prod)
@warning_ignore("shadowed_global_identifier")
var log:		BaseFrameworkLogger		## 基础：日志与诊断
var network:	BaseNetworkClient		## 通讯：HTTP连接池、断线重连、Token鉴权
var net:		BaseNetworkClient:		## network 的快速访问别名
	get: return network
var storage:	BaseStorageSystem		## 存储：内存/磁盘/远端三级读写
var time:		BaseTimeSystem			## 校验：服务器权威时间校准
var locale:		BaseLocalizationSystem	## 表现：多语言与区域格式化
var asset:		BaseAssetSystem			## 资源：资产加载池、内存/磁盘缓存管理
var scene:		BaseSceneRouter			## 表现：场景流转与转场遮罩
var ui:			BaseUISystem			## 表现：全局 UI 分层与模态弹窗系统
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


## 初始化 Framework。App 只负责生命周期，具体服务装配由 FrameworkRuntime 完成。
## [method _ready] 会调一次；其它入口可以 [code]await App.bootstrap()[/code] 等待同一个结果。
func bootstrap() -> Result:
	if _boot_done:
		return _boot_result
	if _booting:
		while _booting:
			await get_tree().process_frame
		return _boot_result if _boot_result != null else Result.err_code("Core.BootFailed", "Framework bootstrap did not produce a result.")
	_booting = true
	_boot_result = null
	_runtime = FrameworkRuntime.new()
	_boot_result = await _runtime.initialize(self)
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
	var result := await bootstrap()
	if result.is_err():
		push_error("Framework bootstrap failed: %s" % result.error_message())


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
	if log != null:
		log.info("app", "App paused.")
	Bus.app_paused.emit()


## 回前台：异步重同步，并立即广播 Bus.app_resumed。
func _on_app_resumed() -> void:
	if not _is_app_paused:
		return
	_is_app_paused = false
	if log != null:
		log.info("app", "App resumed.")
	Bus.app_resumed.emit()


## 窗口失焦（PC/桌面端）：暂停音频并触发 App 挂起逻辑。
func _on_app_focus_out() -> void:
	if log != null:
		log.info("app", "App focus out.")
	if audio != null:
		audio.set_paused(true)
	_on_app_paused()


## 窗口获焦（PC/桌面端）：恢复音频并触发 App 恢复逻辑。
func _on_app_focus_in() -> void:
	if log != null:
		log.info("app", "App focus in.")
	if audio != null:
		audio.set_paused(false)
	_on_app_resumed()


## 返回键 / ESC / 侧滑返回：优先关闭顶层弹窗，否则广播 Bus.app_back_pressed。
func _on_app_go_back() -> void:
	if ui != null and ui.has_modal():
		ui.close_top_popup()
		return
	if log != null:
		log.info("app", "App back pressed.")
	Bus.app_back_pressed.emit()


## 关闭请求：flush 后允许退出（auto_accept_quit 已关闭）。
func _on_app_quit() -> void:
	if log != null:
		log.info("app", "App quit.")
	if _runtime != null:
		_runtime.dispose()
		_runtime = null
		_boot_done = false
		_boot_result = null
	get_tree().quit()


## 系统内存警告：释放资源缓存。
func _on_app_low_memory() -> void:
	if log != null:
		log.warn("app", "App low memory: flushing asset cache.")
	if asset != null:
		asset.clear()
#endregion
