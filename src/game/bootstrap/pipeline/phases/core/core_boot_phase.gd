class_name CoreBootPhase
extends BaseBootPhase

## 阶段一：游戏内核的启动组件加载 (Framework Core / Engine Services)。[br]
## 负责底层通用技术能力装配：环境、日志、时间、资产、触觉、网络、存储、本地化、场景路由、UI分层、音频、视频解码。

const PHASE_ID: int = 1
const PHASE_NAME: String = "Framework Core"


func get_phase_id() -> int:
	return PHASE_ID


func get_phase_name() -> String:
	return PHASE_NAME


func execute(context: BootContext) -> Result:
	var start := Time.get_ticks_msec()
	step_changed.emit("正在准备内核基础设施...", 0.0)

	var on_step := func(index: int, total: int, service_key: String) -> void:
		var ratio := float(index) / float(max(1, total))
		step_changed.emit("加载内核服务: %s (%d/%d)" % [service_key.capitalize(), index, total], ratio)

	var result: Result = await App.bootstrap(on_step)
	if result.is_err():
		if App.logger != null:
			App.logger.error("Bootstrap", "Phase 1 (Core) failed: %s" % result.error_message())
		return result

	var cost := Time.get_ticks_msec() - start
	if context != null:
		context.record_metric("phase_core_ms", cost)

	step_changed.emit("内核服务装配完成", 1.0)
	if App.logger != null:
		App.logger.info("Bootstrap", "Phase 1: Game kernel components loaded successfully in %d ms." % cost)
	return Result.ok()
