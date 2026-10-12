class_name InitStateStep
extends BaseBootStep

## 业务启动步骤 4：全局业务状态准备就绪与广播。


func get_step_name() -> String:
	return "初始化全局游戏状态"


func execute(_context: BootContext) -> Result:
	if Bus != null:
		Bus.emit(GameEvents.BOOTSTRAP_COMPLETED)
	return Result.ok()
