class_name ApplySettingsStep
extends BaseBootStep

## 业务启动步骤 3：应用用户偏好设置与系统预热。


func get_step_name() -> String:
	return "应用系统偏好与音频预热"


func execute(_context: BootContext) -> Result:
	if App.audio != null:
		# 设置默认主音量与 BGM / SFX 比例
		App.audio.set_bus_volume(GameConstants.BUS_MASTER, 1.0)
		App.audio.set_bus_volume(GameConstants.BUS_BGM, 0.8)
		App.audio.set_bus_volume(GameConstants.BUS_SFX, 1.0)
	return Result.ok()
