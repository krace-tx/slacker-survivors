class_name PlayerProfileModel
extends BaseParams

## 玩家全局持久化档案模型 (Shared Domain Model)。[br]
##
## 职责：[br]
## 1. 作为跨模块（大厅、天赋、商店、战斗结算）共享的玩家核心资产与成长档案载体；[br]
## 2. 继承 [BaseParams]，自动具备 [method BaseParams.to_dict] 与 [method BaseParams.from_dict] 反射序列化能力；[br]
## 3. 与 [code]App.storage[/code] 中的 [constant GameConstants.KEY_PLAYER_DATA] 持久层直接映射。

signal data_changed()

## 玩家昵称
var nickname: String = "Survivor"
## 局外持有金币数量
var gold: int = 0
## 玩家账号等级
var level: int = 1
## 已解锁角色 ID 列表
var unlocked_heroes: Array[String] = ["default_slacker"]
## 局外天赋等级字典：{ talent_id: int }
var talent_levels: Dictionary = {}
## 账号首次创建时间戳（Unix 毫秒）
var created_at: int = 0


## 创建新玩家默认初始档案
static func create_default(timestamp_ms: int = 0) -> PlayerProfileModel:
	var model := PlayerProfileModel.new()
	model.nickname = "Survivor"
	model.gold = 0
	model.level = 1
	model.unlocked_heroes = ["default_slacker"]
	model.talent_levels = {}
	model.created_at = timestamp_ms
	return model


## 增减金币（带非负校验）并触发变更通知
func add_gold(delta: int) -> bool:
	if gold + delta < 0:
		return false
	gold += delta
	data_changed.emit()
	return true


## 获取指定天赋当前等级
func get_talent_level(talent_id: String) -> int:
	return int(talent_levels.get(talent_id, 0))


## 设置指定天赋等级并触发变更通知
func set_talent_level(talent_id: String, new_level: int) -> void:
	talent_levels[talent_id] = max(0, new_level)
	data_changed.emit()
