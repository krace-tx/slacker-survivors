class_name LoadConfigTask
extends BootTask

## 启动任务 1：绑定核心存储契约并装载静态策划数值配置表 (CRITICAL)。


func get_task_id() -> StringName:
	return &"load_config"


func get_task_title() -> String:
	return "装载静态数值与存储契约"


func get_weight() -> float:
	return 20.0


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.CRITICAL


func execute(context: SplashBootContext) -> Result:
	if App.storage == null:
		return Result.err_code("Splash.StorageMissing", "Storage subsystem is not initialized.")

	# 1. 确保所有全局持久化契约项已在 StorageSystem 中注册绑定
	var settings_item := GameSettingsModel.storage_item()
	if not App.storage.is_bound(settings_item.key_id):
		App.storage.bind(settings_item)

	var profile_item := PlayerProfileModel.storage_item()
	if not App.storage.is_bound(profile_item.key_id):
		App.storage.bind(profile_item)

	# 2. 若 BootstrapScene 已抢先通过 GameSettingsService 加载过偏好设置则直接挂载引用；否则在此兜底加载
	if context != null and context.game_settings == null:
		var settings_res := await GameSettingsService.load_and_apply()
		if settings_res.is_err():
			return settings_res
		context.game_settings = GameSettingsService.get_current()

	return Result.ok()
