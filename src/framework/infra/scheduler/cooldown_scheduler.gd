class_name CooldownScheduler
extends RefCounted

## 通用异步冷却节流调度器 (Infra)。
## 基于显式有限状态机 (FSM) 驱动速率限制 (Rate Limiting) 与尾部延迟合并 (Trailing Debounce)。
##
## [b]状态机流转拓扑：[/b]
## [code]
##   IDLE (就绪) ──[trigger]──> EXECUTING (执行中) ────> COOLDOWN (冷却中)
##     ▲                                                   │
##     │                      [期满且无排队]                │ [期满且有排队]
##     └───────────────────────────────────────────────────┴──> EXECUTING
## [/code]

#region Enums & Signals
## 调度器运行时离散状态
enum State {
	IDLE,       ## 空闲就绪：无任务在跑，且冷却已度过，随时可响应即刻触发
	EXECUTING,  ## 正在执行：目标 action（含异步协程）正在运行中
	COOLDOWN,   ## 冷却等待：单定时器正在倒计时等待冷却期满
}

signal executed                           ## 目标任务实质性执行完成时发射
signal throttled                          ## 请求因处于执行中或冷却期被节流排队时发射
signal state_changed(old_state: State, new_state: State) ## 状态机状态发生转移时发射
#endregion

#region Configuration & State
var cooldown_sec: float = 5.0             ## 最小执行间隔冷却时长（秒，保底 0.05s）
var action: Callable = Callable()         ## 调度触发的目标执行体
var tag: String = "CooldownScheduler"     ## 调度器业务标识（用于日志追踪）

var _state: State = State.IDLE            ## 当前状态机核心状态
var _has_pending: bool = false            ## 冷却期或执行期内是否有积压待发请求
var _last_execute_msec: int = 0           ## 上次实质性执行完成的时间戳（毫秒）
#endregion

#region Metrics & Properties
var state: State:               ## 当前状态机离散状态
	get: return _state
var is_executing: bool:         ## 是否正在执行任务
	get: return _state == State.EXECUTING
var has_pending: bool:          ## 是否有待发的合并请求
	get: return _has_pending
var remaining_cooldown: float:  ## 剩余冷却秒数（<=0 表示就绪）
	get: return _get_remaining_sec()
var is_busy: bool:              ## 调度器是否忙碌
	get: return _state != State.IDLE or _has_pending
#endregion


#region Lifecycle
func _init(p_cooldown_sec: float = 5.0, p_action: Callable = Callable(), p_tag: String = "CooldownScheduler") -> void:
	cooldown_sec = maxf(0.05, p_cooldown_sec)
	action = p_action
	tag = p_tag
	_log("Initialized (cooldown=%.2fs, initial_state=IDLE)" % cooldown_sec)
#endregion


#region Public API
## 请求触发一次调度（节流模式）。
## - IDLE 状态：立即转入 EXECUTING 执行；
## - EXECUTING 或 COOLDOWN 状态：标记 pending 排队，期满后由状态机自动闭环补发。
func trigger(p_override_action: Callable = Callable()) -> void:
	if p_override_action.is_valid():
		action = p_override_action

	# 1. 空闲且冷却就绪 -> 立即触发执行
	if _state == State.IDLE and _get_remaining_sec() <= 0.0:
		_log("Trigger: idle & ready, executing immediately.")
		_run_pipeline()
		return

	# 2. 状态机忙碌（正在执行或冷却中）-> 记录排队待发
	_has_pending = true
	throttled.emit()
	_log("Trigger: throttled in %s state, queued for trailing execution." % State.keys()[_state])

	# 若处于 IDLE 但尚有残留时间戳（异常兜底），拉起冷却计时
	if _state == State.IDLE:
		_transition_to(State.COOLDOWN)
		_start_cooldown_timer()


## 立即强制执行（忽略冷却限制）。
func flush() -> void:
	_log("Flush requested in %s state." % State.keys()[_state])
	if _state == State.EXECUTING:
		_has_pending = true
		return
	_run_pipeline()


## 取消排队中的尾部待发任务。
func cancel() -> void:
	if _has_pending:
		_log("Pending trailing task cancelled.")
		_has_pending = false


## 重置调度器至初始空闲状态。
func reset() -> void:
	_log("Resetting scheduler to IDLE.")
	_transition_to(State.IDLE)
	_has_pending = false
	_last_execute_msec = 0
#endregion


#region FSM Transitions & Pipeline
## 状态转移核心入口
func _transition_to(new_state: State) -> void:
	if _state == new_state:
		return
	var old_state := _state
	_state = new_state
	_log("FSM: %s -> %s" % [State.keys()[old_state], State.keys()[new_state]])
	state_changed.emit(old_state, new_state)


## 执行管线：从当前切入 EXECUTING，跑完切入 COOLDOWN
func _run_pipeline() -> void:
	if not action.is_valid():
		_log("Action execution aborted: callable is invalid.")
		_transition_to(State.IDLE)
		return

	# 1. 转移至执行中状态
	_transition_to(State.EXECUTING)
	_has_pending = false
	_last_execute_msec = Time.get_ticks_msec()

	# 2. 执行业务体（支持同步函数与异步协程）
	var res = action.call()
	if res is Signal:
		await res

	executed.emit()

	# 3. 执行完毕，进入冷却阶段
	_transition_to(State.COOLDOWN)
	_start_cooldown_timer()


## 启动单定时器冷却等待
func _start_cooldown_timer() -> void:
	var wait_sec := maxf(0.05, _get_remaining_sec())
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_log("SceneTree is null, transition back to IDLE.")
		_transition_to(State.IDLE)
		return

	_log("COOLDOWN timer started: %.2fs" % wait_sec)
	await tree.create_timer(wait_sec, false).timeout

	# 保护：若等待期间被外部 reset() 切回 IDLE，则不再流转
	if _state != State.COOLDOWN:
		return

	# 4. 冷却倒计时结束：根据是否有排队决定下一跳状态
	if _has_pending:
		_log("COOLDOWN expired with pending request -> looping to EXECUTING.")
		_run_pipeline()
	else:
		_log("COOLDOWN expired with no pending request -> transition to IDLE.")
		_transition_to(State.IDLE)


## 计算距离冷却结束剩余秒数
func _get_remaining_sec() -> float:
	if _last_execute_msec <= 0:
		return 0.0
	var passed_sec := float(Time.get_ticks_msec() - _last_execute_msec) / 1000.0
	return maxf(0.0, cooldown_sec - passed_sec)
#endregion


#region Logging Helpers
func _log(message: String) -> void:
	LogService.print_raw(LogLevel.DEBUG, tag, message)
#endregion
