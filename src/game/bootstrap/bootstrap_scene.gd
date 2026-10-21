class_name BootstrapScene
extends BaseScene

@warning_ignore_start("redundant_await")

## 引擎级极简纯空启动器场景 (Pure Kernel Bootstrapper & Handover Entry)。[br]
##
## [b]工业级架构职责（第一性原理）：[/b][br]
## 1. [b]零视觉开销纯空节点[/b]：作为 `project.godot` 的 `run/main_scene`，本场景不包含任何 UI 控件或业务重资产引用，确保引擎进程以 0 渲染负担毫秒级拉起；[br]
## 2. [b]消灭首屏跳变与爆音（Early Preferences Alignment）[/b]：在实例化任何业务 UI 视图（如 `features/splash`）之前，先行完成 [method App.bootstrap] 内核装配与 [method GameSettingsService.load_and_apply] 硬件参数对齐（窗口模式、分辨率、VSync、MSAA、多语言 Locale、音频总线静音/音量）；[br]
## 3. [b]无感移交至业务层[/b]：内核与硬件就绪后，将自身注册为 [code]App.scene[/code] 初始根节点，随即通过无动画瞬切（[constant SceneTransitionType.NONE]）将控制权移交至 `src/game/features/splash/` 垂直模块。

## 启动交接流转完成信号（供自动化集成测试监听）
signal handover_completed(next_scene_path: String)

## 允许在检查器或测试中覆盖内核就绪后的首个业务加载场景（默认移交至 GameConstants.SCENE_SPLASH）
@export var handover_scene_path: String = GameConstants.SCENE_SPLASH
## 允许在开发期指定完成 Splash 加载后强制直达的目标业务场景（透传给 SplashEnterParams.override_target_scene）
@export var override_target_scene: String = ""

var _handover_started: bool = false


func _ready() -> void:
	# 立即在首帧同步发起内核装配，抢在 App._ensure_standalone_bootstrap 之前接管启动控制权
	_boot_kernel_and_handover()


func _boot_kernel_and_handover() -> void:
	if _handover_started:
		return
	_handover_started = true

	# 1. 装配 Framework 13 大核心技术子系统
	var kernel_res := await App.bootstrap()
	if kernel_res.is_err():
		push_error("[BootstrapScene] Kernel bootstrap failed: %s" % kernel_res.error_message())
		return

	# 2. 将当前空启动场景注册为 SceneRouter 的初始受管根节点
	var self_path := scene_file_path if not scene_file_path.is_empty() else GameConstants.SCENE_BOOTSTRAP
	if App.scene != null and App.scene.is_empty():
		await App.scene.bind(self_path, self)

	# 3. 抢在首帧任何 UI 渲染前，加载并应用设备窗口、分辨率、画质抗锯齿、多语言与音频总线偏好
	await GameSettingsService.load_and_apply()

	# 4. 构造强类型入参并无感移交至 features/splash 闪屏加载模块
	var next_scene := handover_scene_path if not handover_scene_path.is_empty() else GameConstants.SCENE_SPLASH
	if App.logger != null:
		App.logger.info(
			"Bootstrap",
			"Kernel & early device preferences ready; handing over to '%s'." % next_scene
		)

	handover_completed.emit(next_scene)

	if App.scene != null and ResourceLoader.exists(next_scene):
		var enter_params := SplashEnterParams.new(override_target_scene)
		await App.scene.replace(next_scene, enter_params, SceneTransitionType.NONE)
