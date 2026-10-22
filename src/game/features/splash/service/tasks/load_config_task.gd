class_name LoadConfigTask
extends BootTask

## 启动任务 1：绑定核心存储契约并装载静态配置表 (`CRITICAL`)。

const _TASK_ID: StringName = &"load_config"
const _TASK_TITLE: String = "加载配置"
const _TASK_WEIGHT: float = 20.0
const _ERR_STORAGE_MISSING: String = "Splash.StorageMissing"


func get_task_id() -> StringName:
	return _TASK_ID


func get_task_title() -> String:
	return _TASK_TITLE


func get_weight() -> float:
	return _TASK_WEIGHT


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.CRITICAL


func execute(context: SplashBootContext) -> Result:
	if App.storage == null:
		return Result.err_code(_ERR_STORAGE_MISSING, "Storage subsystem is not initialized.")

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
