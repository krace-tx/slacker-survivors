class_name PlayerProfileModel
extends BaseParams

## 玩家全局持久化基础档案模型（位于 src/game/shared/model/save/）。[br]
##
## [b]核心职责（遵循 `*Model` 领域后缀规范）：[/b][br]
## 1. 作为跨模块共享的玩家通用账号元数据载体（与具体玩法数值解耦）；[br]
## 2. 继承 [BaseParams]，自动具备 [method BaseParams.to_dict] 与 [method BaseParams.from_dict] 反射序列化能力；[br]
## 3. 与 [code]App.storage[/code] 中的 [constant GameConstants.KEY_PLAYER_PROFILE] 持久层直接映射。

signal data_changed()

#region Constants
const _STORAGE_DISK_PATH: String = "user://saves/player_profile.json"
const _STORAGE_SCHEMA_VERSION: int = 1
const _DEFAULT_NICKNAME: String = "Player"
#endregion

#region Profile Fields
## 玩家本地档案唯一标识
var profile_id: String = ""
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
## 创建玩家档案标准存储配置项
static func storage_item() -> StorageItem:
	return StorageItem.new(
		GameConstants.KEY_PLAYER_PROFILE,
		_STORAGE_DISK_PATH,
		_STORAGE_SCHEMA_VERSION,
		-1.0
	)


## 创建新玩家默认初始档案
static func create_default(timestamp_ms: int = 0) -> PlayerProfileModel:
	var model := PlayerProfileModel.new()
	model.profile_id = "local_%d" % maxi(0, timestamp_ms)
	model.nickname = _DEFAULT_NICKNAME
	model.created_at_ms = maxi(0, timestamp_ms)
	model.last_login_at_ms = maxi(0, timestamp_ms)
	model.login_count = 1
	model.custom_data = {}
	return model


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
