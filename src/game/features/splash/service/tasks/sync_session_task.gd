class_name SyncSessionTask
extends BootTask

## 启动任务 2：执行环境策略激活、会话探测与权威时钟同步 (DEGRADABLE)。[br]
## 若网络不可达或处于纯单机环境，自动降级为离线模式继续进游，绝不阻断单机游玩。


func get_task_id() -> StringName:
	return &"sync_session"


func get_task_title() -> String:
	return "同步运行环境与时间基准"


func get_weight() -> float:
	return 15.0


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.DEGRADABLE


func execute(context: SplashBootContext) -> Result:
	if App.env != null and App.env.has_profile():
		var env_res := App.env.activate_profile()
		if env_res.is_err():
			return env_res

	if App.env != null and App.env.is_local():
		if context != null:
			context.is_offline_mode = true
		return Result.ok()

	if App.clock != null and not App.clock.is_trusted():
		if context != null:
			context.is_offline_mode = true
		return Result.err_code(
			"Splash.ClockUntrusted",
			"Remote authoritative clock not synced yet; running in offline-capable mode."
		)

	return Result.ok()
