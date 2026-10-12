class_name LoadProfileStep
extends BaseBootStep

## 业务启动步骤 2：读取玩家持久化用户存档与首发账号初始化。


func get_step_name() -> String:
	return "解析玩家本地档案与存档"


func execute(context: BootContext) -> Result:
	if App.storage == null:
		return Result.err_code("Business.StorageMissing", "Storage service is not available.")

	var user_data: Dictionary = App.storage.get_dict(GameConstants.KEY_PLAYER_DATA, {})
	if user_data.is_empty():
		if App.logger != null:
			App.logger.info("Bootstrap", "New player detected. Initializing default profile...")
		user_data = {
			"nickname": "Survivor",
			"gold": 0,
			"level": 1,
			"created_at": App.time.now_msec() if App.time != null else 0,
		}
		App.storage.set_dict(GameConstants.KEY_PLAYER_DATA, user_data)
		var flush_res: Result = App.storage.flush()
		if flush_res.is_err():
			return flush_res

	if context != null:
		context.set_data("player_data", user_data)

	return Result.ok()
