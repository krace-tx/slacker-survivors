class_name PlayerProfileModel
extends BaseParams

## 玩家全局持久化基础档案模型（位于 src/game/shared/model/save/）。[br]
##
## [b]核心职责（遵循 `*Model` 领域后缀规范）：[/b][br]
## 1. 作为跨模块共享的玩家通用账号元数据载体（与具体玩法数值解耦）；[br]
## 2. 继承 [BaseParams]，自动具备 [method BaseParams.to_dict] 与 [method BaseParams.from_dict] 反射序列化能力；[br]
## 3. 与 [code]App.storage[/code] 中的 [constant STORAGE_KEY] 持久层直接映射，默认启用 Steam Cloud (`with_steam_cloud`) 跨设备云存档同步。

signal data_changed()

#region Constants
const STORAGE_DOMAIN: StringName = &"shared"
const STORAGE_SUBJECT: String = "player_profile"
const STORAGE_KEY: StringName = &"shared:player_profile"
const _STORAGE_SCHEMA_VERSION: int = 1
const _DEFAULT_NICKNAME: String = "Player"
#endregion

#region Profile Fields
## 玩家档案唯一标识（关联 AuthSession.account_id，如 "steam:76561198..." 或 "guest:..."）
var profile_id: String = ""
## 认证身份提供商标识（如 "steam"、"apple"、"google"、"guest"）
var auth_provider: String = ""
## 平台原生用户唯一标识（如 SteamID64、Apple sub、GPGS playerId）
var platform_user_id: String = ""
## 玩家展示昵称
var nickname: String = _DEFAULT_NICKNAME
## 档案首次创建时间戳（Unix 毫秒）
var created_at_ms: int = 0
## 最近一次登录/启动时间戳（Unix 毫秒）
var last_login_at_ms: int = 0
## 累计登录/启动次数
var login_count: int = 1
## 通用扩展元数据键值表（供业务模块按需挂载轻量跨周期标记）
var custom_data: Dictionary = {}
#endregion


#region Public API
## 创建玩家档案标准存储配置项（落盘至玩家核心存档区 user://saves/shared/player_profile.json，并启用 Steam Cloud 同步）
static func storage_item() -> StorageItem:
	return StorageItem.for_save(
		STORAGE_DOMAIN,
		STORAGE_SUBJECT,
		_STORAGE_SCHEMA_VERSION,
		"json",
		-1.0
	).with_steam_cloud()


## 创建新玩家默认初始档案
static func create_default(timestamp_ms: int = 0) -> PlayerProfileModel:
	var model := PlayerProfileModel.new()
	model.profile_id = "local_%d" % maxi(0, timestamp_ms)
	model.auth_provider = String(AuthProviderType.GUEST)
	model.platform_user_id = ""
	model.nickname = _DEFAULT_NICKNAME
	model.created_at_ms = maxi(0, timestamp_ms)
	model.last_login_at_ms = maxi(0, timestamp_ms)
	model.login_count = 1
	model.custom_data = {}
	return model


## 将当前已认证的 [AuthSession] 身份信息绑定合并至玩家档案
func apply_auth_session(session: AuthSession) -> bool:
	if session == null or not session.is_valid():
		return false
	var changed := false
	if not session.account_id.is_empty() and (profile_id.is_empty() or profile_id.begins_with("local_") or profile_id.begins_with("guest_")):
		if profile_id != session.account_id:
			profile_id = session.account_id
			changed = true
	var provider_str := String(session.provider)
	if not provider_str.is_empty() and auth_provider != provider_str:
		auth_provider = provider_str
		changed = true
	if not session.platform_user_id.is_empty() and platform_user_id != session.platform_user_id:
		platform_user_id = session.platform_user_id
		changed = true
	if not session.display_name.is_empty() and (nickname.is_empty() or nickname == _DEFAULT_NICKNAME or nickname.begins_with("Player_")):
		if nickname != session.display_name:
			nickname = session.display_name
			changed = true
	if changed:
		data_changed.emit()
	return changed


## 对档案字段执行合法范围自愈校验，返回自身以支持链式调用。
func sanitize() -> PlayerProfileModel:
	if nickname.strip_edges().is_empty():
		nickname = _DEFAULT_NICKNAME
	created_at_ms = maxi(0, created_at_ms)
	last_login_at_ms = maxi(created_at_ms, last_login_at_ms)
	login_count = maxi(1, login_count)
	return self


## 记录一次新的会话登录时间戳与计数
func record_login_session(timestamp_ms: int) -> void:
	last_login_at_ms = maxi(last_login_at_ms, timestamp_ms)
	login_count = maxi(1, login_count + 1)
	data_changed.emit()


## 更新玩家昵称并触发变更信号
func set_nickname(new_nickname: String) -> bool:
	var cleaned := new_nickname.strip_edges()
	if cleaned.is_empty() or cleaned == nickname:
		return false
	nickname = cleaned
	data_changed.emit()
	return true


## 写入自定义扩展字段并触发变更信号
func set_custom_value(key: String, value: Variant) -> void:
	if key.is_empty():
		return
	custom_data[key] = value
	data_changed.emit()


## 读取自定义扩展字段
func get_custom_value(key: String, default_value: Variant = null) -> Variant:
	return custom_data.get(key, default_value)


## 触发档案数据变更通知
func notify_changed() -> void:
	data_changed.emit()
#endregion
