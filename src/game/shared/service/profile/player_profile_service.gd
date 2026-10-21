class_name PlayerProfileService
extends RefCounted

## 玩家全局档案业务服务（位于 src/game/shared/service/profile/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一持有并管理跨模块共享的 [PlayerProfileModel] 实例；[br]
## 2. 封装档案读取、新账号初始化、原子落盘及跨模块资产变更广播（[constant GameEvents.GOLD_CHANGED]、[constant GameEvents.TALENT_UPGRADED]）。

static var _current: PlayerProfileModel = null


## 获取当前运行时玩家档案模型（若未加载则惰性创建默认实例）。
static func get_current() -> PlayerProfileModel:
	if _current == null:
		var now_ms: int = App.clock.now_msec() if (App != null and App.clock != null) else 0
		_current = PlayerProfileModel.create_default(now_ms)
	return _current


## 从本地存储加载玩家档案；若为新玩家则初始化默认档案并落盘（由启动管线 LoadProfileStep 调用）。
static func load_or_create_async() -> Result:
	if App == null or App.storage == null:
		return Result.err_code("Business.StorageMissing", "Storage service is not available.")

	var item := PlayerProfileModel.storage_item()
	App.storage.bind(item)

	var read_res: Result = await App.storage.read_async(item, StorageReadMode.LOCAL_ONLY)
	if read_res.is_ok() and read_res.value is Dictionary and not (read_res.value as Dictionary).is_empty():
		_current = PlayerProfileModel.new(read_res.value as Dictionary)
		return Result.ok(_current)

	# 若存档存在但因版本过高（Storage.VersionTooNew）或迁移失败报错，阻断启动以保护原存档不被覆盖
	if read_res.is_err() and read_res.error_code() != StorageError.NOT_FOUND:
		return read_res

	if App.logger != null:
		App.logger.info("ProfileService", "New player detected. Initializing default profile...")
	var now_ms: int = App.clock.now_msec() if App.clock != null else 0
	_current = PlayerProfileModel.create_default(now_ms)
	var write_res: Result = await App.storage.write_async(item, _current.to_dict(), StorageWriteMode.LOCAL_ONLY)
	if write_res.is_err():
		return write_res

	return Result.ok(_current)


## 将当前玩家档案持久化落盘。
static func save_async() -> Result:
	if App == null or App.storage == null:
		return Result.err_code("Business.StorageMissing", "Storage service is not available.")
	var item := PlayerProfileModel.storage_item()
	App.storage.bind(item)
	return await App.storage.write_async(item, get_current().to_dict(), StorageWriteMode.LOCAL_ONLY)


## 增减玩家金币，成功后自动广播 [constant GameEvents.GOLD_CHANGED] 并按需落盘。
static func add_gold(delta: int, auto_save: bool = true) -> bool:
	var profile := get_current()
	if not profile.add_gold(delta):
		return false
	if Bus != null:
		Bus.emit(GameEvents.GOLD_CHANGED, {"gold": profile.gold, "delta": delta})
	if auto_save:
		save_async()
	return true


## 升级指定天赋等级，自动广播 [constant GameEvents.TALENT_UPGRADED] 并按需落盘。
static func set_talent_level(talent_id: String, new_level: int, auto_save: bool = true) -> void:
	var profile := get_current()
	profile.set_talent_level(talent_id, new_level)
	if Bus != null:
		Bus.emit(GameEvents.TALENT_UPGRADED, {
			"talent_id": talent_id,
			"level": profile.get_talent_level(talent_id),
		})
	if auto_save:
		save_async()
