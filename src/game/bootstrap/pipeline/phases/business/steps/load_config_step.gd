class_name LoadConfigStep
extends BaseBootStep

## 业务启动步骤 1：静态数值配置与数据定义预载。


func get_step_name() -> String:
	return "载入静态策划与数值配置"


func execute(_context: BootContext) -> Result:
	# 预留策划静态表 (Resources/Configs) 验证与预载逻辑
	# 未来接入具体数值表 (如 ItemConfig, SkillConfig) 时在此进行加载
	return Result.ok()
