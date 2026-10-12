class_name BattleHudService
extends GameService

## 战斗 HUD · 业务服务 (Service)。[br]
## 负责生命值结算、经验累加与升级公式校验。

var _model: BattleHudModel


func _init(model: BattleHudModel) -> void:
	_model = model


## 受到伤害结算
func apply_damage(amount: float) -> void:
	if amount <= 0.0 or _model.current_hp <= 0.0:
		return
	
	var new_hp := maxf(0.0, _model.current_hp - amount)
	_model.set_hp(new_hp, _model.max_hp)
	
	if App != null and App.haptic != null:
		App.haptic.vibrate_light()
	
	if new_hp <= 0.0:
		log_info("Battle", "Player died in battle.")
		if Bus != null:
			Bus.emit(GameEvents.BATTLE_FINISHED, {
				"is_victory": false,
				"survived_time": _model.survived_seconds,
				"kills": _model.kill_count
			})


## 治疗恢复
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	var new_hp := minf(_model.max_hp, _model.current_hp + amount)
	_model.set_hp(new_hp, _model.max_hp)


## 增加经验值并检查肉鸽升级
func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	
	var cur_exp := _model.current_exp + amount
	var max_exp := _model.max_exp
	var cur_lvl := _model.level
	
	# 支持单次获取海量经验连续升级
	while cur_exp >= max_exp:
		cur_exp -= max_exp
		cur_lvl += 1
		max_exp = int(float(max_exp) * 1.3) # 每级经验上调 30%
		
		log_info("Battle", "Player leveled up to Lv.%d!" % cur_lvl)
		if Bus != null:
			Bus.emit(GameEvents.BATTLE_LEVEL_UP, {
				"current_level": cur_lvl
			})
	
	_model.set_exp(cur_exp, max_exp, cur_lvl)


## 击杀敌人数累加
func record_kill() -> void:
	_model.update_stats(_model.kill_count + 1, _model.survived_seconds)


## 计时器步进
func tick_timer(delta: float) -> void:
	_model.update_stats(_model.kill_count, _model.survived_seconds + delta)
