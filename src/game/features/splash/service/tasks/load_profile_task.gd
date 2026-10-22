class_name LoadProfileTask
extends BootTask

## 启动任务 3：通过 [PlayerProfileService] 加载玩家持久化基础档案 (`CRITICAL`)。[br]
## 若存档版本过高或迁移失败则中止启动以保护玩家原存档不被覆盖；若为新玩家则自动建档落盘。

const _TASK_ID: StringName = &"load_profile"
const _TASK_TITLE: String = "读取存档"
const _TASK_WEIGHT: float = 25.0
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

	var profile_item := PlayerProfileModel.storage_item()
	var existed_before := FileUtils.file_exists(profile_item.disk_path)

	var profile_res := await PlayerProfileService.load_or_create_async()
	if profile_res.is_err():
		return profile_res

	if context != null:
		context.player_profile = PlayerProfileService.get_current()
		context.is_first_launch = not existed_before

	return Result.ok()
