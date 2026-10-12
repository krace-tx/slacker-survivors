class_name UpgradeSelectionService
extends GameService

## 肉鸽选卡 · 业务服务 (Service)。[br]
## 负责技能池抽取、洗牌、权重算法与技能生效逻辑。

const SKILL_POOL: Array[Dictionary] = [
	{
		"id": "whirlwind_blades",
		"title": "回旋飞刃",
		"description": "发射环绕自身的利刃，范围 +25%",
		"icon": "🗡️"
	},
	{
		"id": "slacker_aura",
		"title": "摸鱼立场",
		"description": "对身边敌人持续造成震慑，伤害 +20%",
		"icon": "🛡️"
	},
	{
		"id": "iced_americano",
		"title": "冰美式咖啡",
		"description": "瞬间精神饱满，移动速度 +15%",
		"icon": "☕"
	},
	{
		"id": "overtime_pay",
		"title": "加班补助",
		"description": "消灭敌人金币掉落率 +30%",
		"icon": "💰"
	}
]

var _model: UpgradeSelectionModel


func _init(model: UpgradeSelectionModel) -> void:
	_model = model


## 抽取候选卡片并推入 Model
func roll_cards() -> void:
	var pool := SKILL_POOL.duplicate()
	pool.shuffle()
	
	var chosen: Array[Dictionary] = []
	for i in range(mini(3, pool.size())):
		chosen.append(pool[i])
	
	_model.set_candidates(chosen, _model.rerolls_left)


## 应用玩家选择的卡片效果
func select_card(card_id: String) -> Result:
	log_info("Upgrade", "Selected upgrade card: %s" % card_id)
	
	if App != null and App.haptic != null:
		App.haptic.vibrate_medium()
	
	# 这里执行玩家被动/主动技能的注入
	return Result.ok()


## 消耗次数重新刷新
func reroll() -> Result:
	if _model.rerolls_left <= 0:
		return Result.err_code("Upgrade.NoRerolls", "No rerolls remaining.")
	
	_model.rerolls_left -= 1
	roll_cards()
	return Result.ok()
