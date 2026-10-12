class_name GameBootstrapper
extends RefCounted

## 游戏业务层启动器与装配调度器。[br]
##
## 串联 Framework 初始化、基础静态数据加载、用户存档读取与进入主场景流程。

signal progress_updated(progress: float, step_name: String)


## 执行完整的游戏启动流水线
func start_boot_sequence() -> Result:
	# 步骤 1：启动底层 Framework 核心运行时
	progress_updated.emit(0.2, "Initializing Framework Core...")
	var boot_res := await App.bootstrap()
	if boot_res.is_err():
		App.log.error("Bootstrap", "Framework bootstrap failed: %s" % boot_res.error_message())
		return boot_res
	
	# 步骤 2：读取本地持久化用户存档 (通过 App.storage)
	progress_updated.emit(0.5, "Loading User Save Data...")
	_load_user_profile()
	
	# 步骤 3：预热音频总线与关键系统
	progress_updated.emit(0.8, "Preheating Systems...")
	_warmup_systems()
	
	# 步骤 4：就绪完成
	progress_updated.emit(1.0, "Ready")
	App.log.info("Bootstrap", "Game bootstrap sequence completed successfully.")
	return Result.ok()


func _load_user_profile() -> void:
	if App.storage == null:
		return
	
	var user_data: Dictionary = App.storage.get_dict(GameConstants.KEY_PLAYER_DATA, {})
	if user_data.is_empty():
		App.log.info("Bootstrap", "New player detected. Initializing default profile...")
		App.storage.set_dict(GameConstants.KEY_PLAYER_DATA, {
			"nickname": "Survivor",
			"gold": 0,
			"level": 1,
			"created_at": App.time.get_unix_time_ms() if App.time else 0
		})
		App.storage.flush()


func _warmup_systems() -> void:
	if App.audio != null:
		# 设置默认主音量
		App.audio.set_bus_volume(GameConstants.BUS_MASTER, 1.0)
