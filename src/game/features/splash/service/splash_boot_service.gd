class_name SplashBootService
extends RefCounted

## 闪屏业务启动管线领域服务（位于 src/game/features/splash/service/）。[br]
##
## [b]核心职责（遵循 MSVP 的 `Service` 规范）：[/b][br]
## 1. [b]加权业务启动管线编排[/b]：顺序调度 5 大标准 [BootTask]（配置装载 ➔ 会话同步 ➔ 玩家档案恢复 ➔ 资源预热 ➔ 终局路由裁决）；[br]
## 2. [b]状态驱动与零 UI 耦合[/b]：实时更新 [SplashBootState] 并由其发射信号通知 [SplashPresenter]，自身绝不引用任何 UI 节点；[br]
## 3. [b]三级容灾与原地断点重试[/b]：区分 `CRITICAL` / `DEGRADABLE` / `OPTIONAL`，当关键任务失败时保留失败断点索引，支持 [method retry_failed] 原地续跑；[br]
## 4. [b]全局就绪事件广播[/b]：全部任务完成后广播 [constant GameEvents.BOOTSTRAP_COMPLETED]。

#region Constants & State
const _LOG_TAG: String = "Splash"
const _ERR_ALREADY_RUNNING: String = "Splash.AlreadyRunning"
const _ERR_NOT_IN_FAILED_STATE: String = "Splash.NotInFailedState"
const _TASK_ID_KERNEL_BOOT: StringName = &"kernel_boot"

var _state: SplashBootState = null
var _context: SplashBootContext = null
var _tasks: Array[BootTask] = []
var _current_task_index: int = 0
#endregion


#region Public API
func _init(
	state: SplashBootState = null,
	context: SplashBootContext = null,
	custom_tasks: Array[BootTask] = []
) -> void:
	_state = state if state != null else SplashBootState.new()
	_context = context if context != null else SplashBootContext.new()
	if not custom_tasks.is_empty():
		_tasks = custom_tasks.duplicate()
	else:
		_tasks = _build_default_pipeline()


## 追加自定义启动任务（需在 [method start_boot_sequence] 调用前注册）
func add_task(task: BootTask) -> SplashBootService:
	if task != null and _state.phase == SplashBootState.Phase.IDLE:
		_tasks.append(task)
	return self


## 启动并执行业务加载流水线（从头开始）
func start_boot_sequence() -> Result:
	if _state.phase == SplashBootState.Phase.RUNNING:
		return Result.err_code(_ERR_ALREADY_RUNNING, "Boot sequence is already running.")
	_current_task_index = 0
	return await _run_from_index(_current_task_index)


## 当某个 CRITICAL 任务失败挂起后，从失败断点处原地重试剩余流水线
func retry_failed() -> Result:
	if _state.phase != SplashBootState.Phase.FAILED:
		return Result.err_code(_ERR_NOT_IN_FAILED_STATE, "Boot sequence is not in FAILED state.")
	return await _run_from_index(_current_task_index)


## 获取运行时响应式状态模型
func get_state() -> SplashBootState:
	return _state


## 获取启动共享上下文与诊断数据
func get_context() -> SplashBootContext:
	return _context
#endregion


#region Internal Pipeline Execution
func _build_default_pipeline() -> Array[BootTask]:
	return [
		LoadConfigTask.new(),
		SyncSessionTask.new(),
		LoadProfileTask.new(),
		WarmupAssetsTask.new(),
		ResolveRouteTask.new(),
	]


func _run_from_index(start_index: int) -> Result:
	# 防御性兜底：若在单元测试或编辑器 F6 独立调试 SplashScene 时直接调用，确保 Framework 内核已就绪
	var kernel_res := await App.bootstrap()
	if kernel_res.is_err():
		_state.mark_failed(_TASK_ID_KERNEL_BOOT, kernel_res.error_code(), kernel_res.error_message())
		return kernel_res

	var total_weight := _compute_total_weight()
	var completed_weight := _compute_weight_before(start_index)

	for idx in range(start_index, _tasks.size()):
		_current_task_index = idx
		var task: BootTask = _tasks[idx]
		var task_id := task.get_task_id()
		var task_title := task.get_task_title()

		var start_ratio := clampf(completed_weight / total_weight, 0.0, 0.99)
		_state.mark_running(task_id, task_title, start_ratio)

		var t0 := Time.get_ticks_msec()
		var res: Result = await task.execute(_context)
		var duration_ms := maxi(0, Time.get_ticks_msec() - t0)
		_context.record_task_metric(task_id, duration_ms)

		if res.is_err():
			var policy := task.get_failure_policy()
			match policy:
				BootTask.FailurePolicy.CRITICAL:
					if App.logger != null:
						App.logger.error(
							_LOG_TAG,
							"Critical boot task '%s' failed: [%s] %s" % [
								String(task_id), res.error_code(), res.error_message()
							]
						)
					_state.mark_failed(task_id, res.error_code(), res.error_message())
					return res

				BootTask.FailurePolicy.DEGRADABLE:
					_context.add_warning(
						task_id,
						"%s (code=%s)" % [res.error_message(), res.error_code()]
					)
					if App.logger != null:
						App.logger.warn(
							_LOG_TAG,
							"Degradable boot task '%s' degraded: [%s] %s" % [
								String(task_id), res.error_code(), res.error_message()
							]
						)

				BootTask.FailurePolicy.OPTIONAL:
					if App.logger != null:
						App.logger.info(
							_LOG_TAG,
							"Optional boot task '%s' skipped: %s" % [String(task_id), res.error_message()]
						)

		completed_weight += maxf(0.0, task.get_weight())
		var end_ratio := clampf(completed_weight / total_weight, 0.0, 1.0)
		_state.update_progress(end_ratio, task_title)

	_current_task_index = _tasks.size()
	var total_ms := _context.mark_finished()
	_state.mark_completed(total_ms, _context.target_scene_path)

	if App.logger != null:
		App.logger.info(
			_LOG_TAG,
			"Business boot pipeline completed in %d ms -> target='%s' (warnings=%d)." % [
				total_ms, _context.target_scene_path, _context.warnings.size()
			]
		)

	if Bus != null:
		Bus.emit(GameEvents.BOOTSTRAP_COMPLETED, _context.get_diagnostics_summary())

	return Result.ok(_context)


func _compute_total_weight() -> float:
	var sum := 0.0
	for task in _tasks:
		sum += maxf(0.0, task.get_weight())
	return maxf(sum, 1.0)


func _compute_weight_before(index: int) -> float:
	var sum := 0.0
	var bound := clampi(index, 0, _tasks.size())
	for i in range(bound):
		sum += maxf(0.0, _tasks[i].get_weight())
	return sum
#endregion
