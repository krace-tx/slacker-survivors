class_name LobbyMenuService
extends GameService

## 大厅主选单 · 业务服务 (Service)。[br]
## 负责玩家数据读取、开始战斗准备校验、金币与体力逻辑。

var _model: LobbyMenuModel


func _init(model: LobbyMenuModel) -> void:
	_model = model


## 从本地存档拉取玩家最新档案
func refresh_player_data() -> void:
	if App.storage == null:
		return
	
	var data: Dictionary = App.storage.get_dict(GameConstants.KEY_PLAYER_DATA, {})
	var nick: String = data.get("nickname", "Survivor")
	var gold: int = int(data.get("gold", 0))
	var lvl: int = int(data.get("level", 1))
	var best_time: float = float(data.get("best_survived_seconds", 0.0))
	
	_model.update_profile(nick, gold, lvl, best_time)


## 请求开始新一局战斗
func request_start_battle() -> Result:
	log_info("Lobby", "Player requested to start battle.")
	
	# 此处可加入体力检查、装备检验等规则逻辑
	if App.scene != null:
		App.scene.replace(GameConstants.SCENE_BATTLE)
		return Result.ok()
	
	return Result.err_code("Lobby.SceneRouterNull", "Scene router is unavailable.")


## 增加金币并同步持久化
func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	
	_model.set_gold(_model.gold + amount)
	
	if App.storage != null:
		var data: Dictionary = App.storage.get_dict(GameConstants.KEY_PLAYER_DATA, {})
		data["gold"] = _model.gold
		App.storage.set_dict(GameConstants.KEY_PLAYER_DATA, data)
		App.storage.flush()
	
	if Bus != null:
		Bus.emit(GameEvents.GOLD_CHANGED, {"gold": _model.gold, "delta": amount})
