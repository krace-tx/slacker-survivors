class_name LoadProfileTask
extends BootTask

## 启动任务 3：通过 [PlayerProfileService] 加载玩家持久化档案并探测未完结战局快照 (CRITICAL)。[br]
## 若存档版本过高或迁移失败则中止启动以保护玩家原存档不被覆盖；若为新玩家则自动建档落盘。


func get_task_id() -> StringName:
	return &"load_profile"


func get_task_title() -> String:
	return "读取玩家档案与战局快照"


func get_weight() -> float:
	return 25.0


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.CRITICAL


func execute(context: SplashBootContext) -> Result:
	if App.storage == null:
		return Result.err_code("Splash.StorageMissing", "Storage subsystem is not initialized.")

	var profile_item := PlayerProfileModel.storage_item()
	var existed_before := FileAccess.file_exists(profile_item.disk_path)

	# 1. 委托 PlayerProfileService 执行档案加载、校验与新号默认建档
	var profile_res := await PlayerProfileService.load_or_create_async()
	if profile_res.is_err():
		return profile_res

	if context != null:
		context.player_profile = PlayerProfileService.get_current()
		context.is_first_launch = not existed_before

	# 2. 探测是否存在未结算的局内战斗快照（用于崩溃恢复 / 断线续战）
	var run_save_item := StorageItem.new(
		StringName(GameConstants.KEY_RUN_SAVE),
		"user://saves/current_run_save.json",
		1,
		-1.0
	)
	if not App.storage.is_bound(run_save_item.key_id):
		App.storage.bind(run_save_item)

	var run_res := await App.storage.read_async(run_save_item, StorageReadMode.LOCAL_ONLY)
	if run_res.is_ok() and run_res.value is Dictionary and not (run_res.value as Dictionary).is_empty():
		if context != null:
			context.has_unfinished_run = true

	return Result.ok()
