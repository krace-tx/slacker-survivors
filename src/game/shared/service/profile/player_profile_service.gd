class_name PlayerProfileService
extends RefCounted

## 玩家全局档案业务服务（位于 src/game/shared/service/profile/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一持有并管理跨模块共享的 [PlayerProfileModel] 实例；[br]
## 2. 封装档案读取（含本地 `.bak` 自愈与 Steam Cloud / HTTP 云存档回填）、新账号初始化、`App.auth` 会话绑定、原子落盘及跨模块事件广播（[constant EVENT_PROFILE_UPDATED]）。

#region Constants & Static State
const _LOG_TAG: String = "ProfileService"
const _ERR_STORAGE_MISSING: String = "Profile.StorageMissing"

## 玩家全局档案数据已更新事件: {"profile": PlayerProfileModel}
const EVENT_PROFILE_UPDATED: StringName = &"game:profile_updated"

static var _current: PlayerProfileModel = null
#endregion


#region Public API
## 获取当前运行时玩家档案模型（若未加载则惰性创建默认实例）。
static func get_current() -> PlayerProfileModel:
	if _current == null:
		var now_ms: int = App.clock.now_msec() if (App != null and App.clock != null) else 0
		_current = PlayerProfileModel.create_default(now_ms)
		_sync_auth_session(_current)
	return _current


## 从多级存储（L1 内存 -> L2 本地磁盘 -> L3 Steam Cloud / 远端云存档）加载玩家档案；
## 若为新玩家则初始化默认档案并落盘（由启动管线 [LoadProfileTask] 调用）。
static func load_or_create_async() -> Result:
	if App == null or App.storage == null:
		return Result.err_code(_ERR_STORAGE_MISSING, "Storage service is not available.")

	var item := PlayerProfileModel.storage_item()
	App.storage.bind(item)

	var now_ms: int = App.clock.now_msec() if App.clock != null else 0
	var read_res: Result = await App.storage.read_async(item, StorageReadMode.CACHE_FIRST)
	if read_res.is_ok() and read_res.value is Dictionary and not (read_res.value as Dictionary).is_empty():
		_current = PlayerProfileModel.new(read_res.value as Dictionary).sanitize()
		_sync_auth_session(_current)
		_current.record_login_session(now_ms)
		await App.storage.write_async(item, _current.to_dict(), StorageWriteMode.LOCAL_FIRST)
		_notify_profile_updated()
		return Result.ok(_current)

	# 若存档存在但因版本过高（Storage.VersionTooNew）或迁移失败报错，阻断启动以保护原存档不被覆盖
	if read_res.is_err() and read_res.error_code() != StorageError.NOT_FOUND and read_res.error_code() != StorageError.REMOTE_UNAVAILABLE:
		return read_res

	if App.logger != null:
		App.logger.info(_LOG_TAG, "New player detected. Initializing default profile...")
	_current = PlayerProfileModel.create_default(now_ms)
	_sync_auth_session(_current)
	var write_res: Result = await App.storage.write_async(item, _current.to_dict(), StorageWriteMode.LOCAL_FIRST)
	if write_res.is_err():
		return write_res

	_notify_profile_updated()
	return Result.ok(_current)


## 将当前玩家档案持久化落盘并后台同步至云端（Steam Cloud / HTTP 远端）。
static func save_async() -> Result:
	if App == null or App.storage == null:
		return Result.err_code(_ERR_STORAGE_MISSING, "Storage service is not available.")
	var item := PlayerProfileModel.storage_item()
	App.storage.bind(item)
	var profile := get_current().sanitize()
	_sync_auth_session(profile)
	return await App.storage.write_async(item, profile.to_dict(), StorageWriteMode.LOCAL_FIRST)


## 修改玩家昵称，成功后自动广播 [constant EVENT_PROFILE_UPDATED] 并按需落盘。
static func update_nickname(new_nickname: String, auto_save: bool = true) -> bool:
	var profile := get_current()
	if not profile.set_nickname(new_nickname):
		return false
	_notify_profile_updated()
	if auto_save:
		save_async()
	return true


## 写入玩家档案自定义扩展数据，自动广播 [constant EVENT_PROFILE_UPDATED] 并按需落盘。
static func set_custom_data(key: String, value: Variant, auto_save: bool = true) -> void:
	if key.is_empty():
		return
	var profile := get_current()
	profile.set_custom_value(key, value)
	_notify_profile_updated()
	if auto_save:
		save_async()
#endregion


#region Internal Helpers
static func _sync_auth_session(profile: PlayerProfileModel) -> void:
	if profile == null or App == null or App.auth == null:
		return
	var session := App.auth.get_session()
	if session != null and session.is_valid():
		profile.apply_auth_session(session)


static func _notify_profile_updated() -> void:
	var profile := get_current()
	if Bus != null:
		Bus.emit(EVENT_PROFILE_UPDATED, {"profile": profile})
#endregion
