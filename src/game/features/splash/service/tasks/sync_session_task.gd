class_name SyncSessionTask
extends BootTask

## 启动任务 2：执行环境策略激活、跨平台自动登录鉴权与权威时钟同步 (`DEGRADABLE`)。[br]
## 自动探测 Steam / Apple / Google / Guest 身份源并签发 [AuthSession]；若网络不可达或处于纯单机环境，
## 自动降级为离线会话继续进游，绝不阻断单机游玩。

const _TASK_ID: StringName = &"sync_session"
const _TASK_TITLE: String = "同步身份与环境"
const _TASK_WEIGHT: float = 15.0
const _ERR_CLOCK_UNTRUSTED: String = "Splash.ClockUntrusted"


func get_task_id() -> StringName:
	return _TASK_ID


func get_task_title() -> String:
	return _TASK_TITLE


func get_weight() -> float:
	return _TASK_WEIGHT


func get_failure_policy() -> FailurePolicy:
	return FailurePolicy.DEGRADABLE


func execute(context: SplashBootContext) -> Result:
	if App.env != null and App.env.has_profile():
		var env_res := App.env.activate_profile()
		if env_res.is_err():
			return env_res

	var is_local_env := App.env != null and App.env.is_local()

	if App.auth != null:
		var auth_opts := AuthOptions.create().with_offline_fallback(true)
		if not is_local_env and App.env != null and not App.env.get_api_base_url().is_empty():
			auth_opts.with_remote_gateway(true)
		var auth_res := await App.auth.login_auto_async(auth_opts)
		if auth_res.is_ok() and auth_res.value is AuthSession:
			var session := auth_res.value as AuthSession
			if context != null:
				context.auth_session = session
				context.is_offline_mode = session.is_offline or is_local_env
		else:
			if context != null:
				context.is_offline_mode = true
			return auth_res

	if is_local_env:
		if context != null:
			context.is_offline_mode = true
		return Result.ok()

	if App.clock != null and not App.clock.is_trusted():
		if context != null:
			context.is_offline_mode = true
		return Result.err_code(
			_ERR_CLOCK_UNTRUSTED,
			"Remote authoritative clock not synced yet; running in offline-capable mode."
		)

	return Result.ok()
