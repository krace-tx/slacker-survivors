class_name BusinessBootPhase
extends BaseBootPhase

## 阶段二：游戏的业务启动加载 (Game Business & Gameplay State)。[br]
## 采用微任务切片 (Steps) 链式编排：
## 1. 静态数值配置与数据定义预载 (LoadConfigStep)
## 2. 玩家本地/远端存档读取与首发账号初始化 (LoadProfileStep)
## 3. 业务音视频与偏好设置应用 (ApplySettingsStep)
## 4. 全局业务状态准备与跨模块就绪广播 (InitStateStep)

const PHASE_ID: int = 2
const PHASE_NAME: String = "Game Business"

var _steps: Array[BaseBootStep] = []


func _init() -> void:
	_steps = [
		LoadConfigStep.new(),
		LoadProfileStep.new(),
		ApplySettingsStep.new(),
		InitStateStep.new(),
	]


func get_phase_id() -> int:
	return PHASE_ID


func get_phase_name() -> String:
	return PHASE_NAME


func execute(context: BootContext) -> Result:
	var phase_start := Time.get_ticks_msec()
	var total_steps := _steps.size()

	for i in range(total_steps):
		var step := _steps[i]
		var step_name := step.get_step_name()
		var progress := float(i) / float(total_steps)

		step_changed.emit("正在%s..." % step_name, progress)

		var step_start := Time.get_ticks_msec()
		var res: Result = await step.execute(context)
		if res.is_err():
			if App.logger != null:
				App.logger.error("Bootstrap", "Phase 2 step failed [%s]: %s" % [step_name, res.error_message()])
			return res

		var step_cost := Time.get_ticks_msec() - step_start
		if context != null:
			context.record_metric("step_%s_ms" % step_name, step_cost)

	step_changed.emit("业务初始化完毕", 1.0)
	var phase_cost := Time.get_ticks_msec() - phase_start
	if context != null:
		context.record_metric("phase_business_ms", phase_cost)

	if App.logger != null:
		App.logger.info("Bootstrap", "Phase 2: Game business loading completed successfully in %d ms." % phase_cost)
	return Result.ok()
