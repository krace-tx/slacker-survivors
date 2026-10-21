class_name LoadProfileStep
extends BaseBootStep

## 业务启动步骤 2：读取玩家持久化用户存档与首发账号初始化。


func get_step_name() -> String:
	return "解析玩家本地档案与存档"


func execute(context: BootContext) -> Result:
	if App.storage == null:
		return Result.err_code("Business.StorageMissing", "Storage service is not available.")

	var raw_data: Dictionary = App.storage.get_dict(GameConstants.KEY_PLAYER_DATA, {})
	var profile: PlayerProfileModel
	if raw_data.is_empty():
		if App.logger != null:
			App.logger.info("Bootstrap", "New player detected. Initializing default profile...")
		var now_ms: int = App.time.now_msec() if App.time != null else 0
		profile = PlayerProfileModel.create_default(now_ms)
		App.storage.set_dict(GameConstants.KEY_PLAYER_DATA, profile.to_dict())
		var flush_res: Result = App.storage.flush()
		if flush_res.is_err():
			return flush_res
	else:
		profile = PlayerProfileModel.new(raw_data)

	if context != null:
		context.set_data("player_profile", profile)
		context.set_data("player_data", profile.to_dict())

	return Result.ok()
