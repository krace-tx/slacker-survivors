class_name TaskScope
extends RefCounted

## 异步任务生命周期作用域与并发编排器（Async Task Scope & Orchestrator）。[br]
##
## 统一收敛全框架的异步任务生命周期所有权、并发收集（[method gather]）、竞态等待（[method race]）、
## 安全休眠（[method sleep]）与完成守卫（Completion Guard），彻底解决「场景退出或 UI 关闭后，
## 异步回调继续执行并访问已释放节点」的 Use-After-Free 与资源泄漏风险：[br]
## 1. [b]作用域所有权[/b]：绑定到 [FrameworkRuntime]、[BaseScene] 或 [BaseView]（弱引用 ID 追踪，零循环引用）；[br]
## 2. [b]批量取消与代际隔离[/b]：[method cancel_all] 立即作废当前代际令牌并轮换新令牌，旧任务完成后的过期结果被自动拦截丢弃；[br]
## 3. [b]全链路 Result 与级联取消[/b]：[method run]、[method gather]、[method race]、[method sleep] 统一返回强类型 [Result]，
##    并在取消、超时或子任务失败时通过级联 [CancellationToken] 自动中止同行任务；[br]
## 4. [b]静态节点等待[/b]：提供 [method wait] 供普通 [Node] 一行执行防 UAF 安全延时。

#region State
var _scope_name: String
var _owner_id: int = 0
var _has_owner: bool = false
var _require_inside_tree: bool = false
var _token: CancellationToken
var _generation: int = 0
var _disposed: bool = false

var _active_count: int = 0
var _completed_count: int = 0
var _cancelled_count: int = 0
var _timed_out_count: int = 0
var _failed_count: int = 0
#endregion


#region Lifecycle
## 构造任务作用域。[br]
## [param owner] 可选宿主对象（如 BaseScene / BaseView 节点）；使用 instance_id 弱引用追踪，绝不造成循环引用。[br]
## [param scope_name] 诊断标识名称。[br]
## [param require_inside_tree] 若宿主为 Node，是否要求其必须处于 SceneTree 内才视为有效。
func _init(owner: Object = null, scope_name: String = "TaskScope", require_inside_tree: bool = true) -> void:
	_scope_name = scope_name
	_require_inside_tree = require_inside_tree
	if owner != null and is_instance_valid(owner):
		_has_owner = true
		_owner_id = owner.get_instance_id()
	_token = CancellationToken.new()


## 获取当前代际的取消令牌。
func get_token() -> CancellationToken:
	return _token


## 当前作用域及其宿主是否仍然存活且未销毁。
func is_valid() -> bool:
	if _disposed:
		return false
	if not _has_owner:
		return true
	var owner_obj := instance_from_id(_owner_id)
	if owner_obj == null or not is_instance_valid(owner_obj):
		return false
	if _require_inside_tree and owner_obj is Node:
		return (owner_obj as Node).is_inside_tree()
	return true


## 是否已永久销毁。
func is_disposed() -> bool:
	return _disposed


## 取消当前作用域内所有进行中的任务，并轮换新令牌（作用域本身保持可用，适用于 UI 视图关闭后重开）。
func cancel_all(reason: String = "TaskScope cancelled.") -> void:
	if _disposed:
		return
	_generation += 1
	var old_token := _token
	_token = CancellationToken.new()
	if old_token != null and not old_token.is_cancelled():
		old_token.cancel(reason)


## 永久关闭并销毁作用域（适用于场景退出、节点释放）。销毁后不可再提交新任务。
func dispose(reason: String = "TaskScope disposed.") -> void:
	if _disposed:
		return
	_disposed = true
	_generation += 1
	if _token != null and not _token.is_cancelled():
		_token.cancel(reason)
#endregion


#region Public Task Execution APIs
## 在当前作用域保护下执行单个异步任务。[br]
## [param task] 待执行的 [Callable]，支持无参 [code]func()[/code] 或单参 [code]func(token: CancellationToken)[/code]。[br]
## [param timeout_seconds] 超时秒数，[code]<= 0.0[/code] 表示不限时。[br]
## 返回 [Result]：若作用域失效/被取消则返回 [code]Async.Cancelled[/code]；若超时则返回 [code]Async.Timeout[/code]；
## 若任务本身返回 [Result] 则原样透传，否则包装为 [code]Result.ok(ret)[/code]。
func run(task: Callable, timeout_seconds: float = 0.0) -> Result:
	var pre_err := _precheck_scope()
	if pre_err != null:
		return pre_err
	if not task.is_valid() or task.is_null():
		_failed_count += 1
		return Result.err_code("Async.InvalidTask", "[%s] Callable is invalid or null." % _scope_name)

	var launch_gen := _generation
	var launch_token := _token
	var child_token := _create_linked_token(launch_token)
	_active_count += 1

	var done := [false]
	var task_output: Array = [null]

	_invoke_callable_async(task, child_token, func(out: Variant) -> void:
		task_output[0] = out
		done[0] = true
	)

	var timed_out := await _poll_until(func() -> bool: return done[0], launch_gen, launch_token, timeout_seconds)
	_active_count = maxi(0, _active_count - 1)

	var guard_err := _check_completion_guard(launch_gen, launch_token, timed_out, timeout_seconds, child_token)
	if guard_err != null:
		return guard_err

	return _unwrap_single_output(task_output[0])


## 并发执行一组异步任务，等待全部完成（等价于受生命周期与令牌保护的 [code]asyncio.gather[/code]）。[br]
## - 每个子任务支持无参 [code]func()[/code] 或单参 [code]func(token: CancellationToken)[/code]；[br]
## - 若任意子任务返回失败 [Result]，立即级联取消其余子任务并返回该错误；[br]
## - 全部成功时返回 [code]Result.ok(results_array)[/code]（若子任务返回 [code]Result.ok(val)[/code] 会自动解包出 [code]val[/code]）。
func gather(tasks: Array[Callable], timeout_seconds: float = 0.0) -> Result:
	var pre_err := _precheck_scope()
	if pre_err != null:
		return pre_err
	if tasks.is_empty():
		return Result.ok([])

	var launch_gen := _generation
	var launch_token := _token
	var batch_token := _create_linked_token(launch_token)

	var count := tasks.size()
	var results: Array = []
	results.resize(count)
	var pending := [count]
	var first_error: Array = [null] # Array[Result]

	_active_count += 1

	for i in count:
		var task := tasks[i]
		if not task.is_valid() or task.is_null():
			results[i] = null
			pending[0] -= 1
			continue

		var idx := i
		_invoke_callable_async(task, batch_token, func(out: Variant) -> void:
			if out is Result:
				var r := out as Result
				if r.is_err():
					if first_error[0] == null:
						first_error[0] = r
						batch_token.cancel("Subtask %d failed in gather." % idx)
				else:
					results[idx] = r.value
			else:
				results[idx] = out
			pending[0] -= 1
		)

	var timed_out := await _poll_until(
		func() -> bool: return pending[0] <= 0 or first_error[0] != null,
		launch_gen,
		launch_token,
		timeout_seconds
	)
	_active_count = maxi(0, _active_count - 1)

	var guard_err := _check_completion_guard(launch_gen, launch_token, timed_out, timeout_seconds, batch_token)
	if guard_err != null:
		return guard_err

	if first_error[0] != null:
		_failed_count += 1
		return first_error[0] as Result

	_completed_count += 1
	return Result.ok(results)


## 竞态执行一组异步任务，任意首个有效任务完成时立即返回其结果，并自动触发取消令牌中止其余陪跑任务。[br]
## [param tasks] 待竞态执行的 [Callable] 数组。[br]
## [param timeout_seconds] 超时秒数，[code]<= 0.0[/code] 表示不限时。
func race(tasks: Array[Callable], timeout_seconds: float = 0.0) -> Result:
	var pre_err := _precheck_scope()
	if pre_err != null:
		return pre_err
	if tasks.is_empty():
		return Result.err_code("Async.InvalidTask", "[%s] race() tasks array is empty." % _scope_name)

	var launch_gen := _generation
	var launch_token := _token
	var race_token := _create_linked_token(launch_token)

	var valid_count := 0
	var done := [false]
	var winner_output: Array = [null]

	for task in tasks:
		if not task.is_valid() or task.is_null():
			continue
		valid_count += 1
		_invoke_callable_async(task, race_token, func(out: Variant) -> void:
			if not done[0]:
				done[0] = true
				winner_output[0] = out
				race_token.cancel("Lost race.")
		)

	if valid_count == 0:
		_failed_count += 1
		return Result.err_code("Async.InvalidTask", "[%s] No valid Callable in race()." % _scope_name)

	_active_count += 1
	var timed_out := await _poll_until(func() -> bool: return done[0], launch_gen, launch_token, timeout_seconds)
	_active_count = maxi(0, _active_count - 1)

	var guard_err := _check_completion_guard(launch_gen, launch_token, timed_out, timeout_seconds, race_token)
	if guard_err != null:
		return guard_err

	return _unwrap_single_output(winner_output[0])


## 在当前作用域内安全休眠指定秒数；若休眠期间作用域取消或宿主退树，立即返回 [code]Async.Cancelled[/code]。
func sleep(seconds: float) -> Result:
	var pre_err := _precheck_scope()
	if pre_err != null:
		return pre_err

	var launch_gen := _generation
	var launch_token := _token
	var tree := _get_safe_tree()
	if tree == null:
		return Result.err_code("Async.NoTree", "[%s] SceneTree unavailable." % _scope_name)

	if seconds <= 0.0:
		await tree.process_frame
	else:
		var start_msec := Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - start_msec) / 1000.0 < seconds:
			if _is_interrupted(launch_gen, launch_token):
				break
			await tree.process_frame

	if _is_interrupted(launch_gen, launch_token):
		_cancelled_count += 1
		return Result.err_code("Async.Cancelled", "[%s] Sleep interrupted by cancellation or owner exit." % _scope_name)
	return Result.ok()


## 静态快捷安全等待：供未挂载独立 [TaskScope] 的普通 [Node] 执行绑定在树生命周期的延时等待（防 Use-After-Free）。[br]
## [codeblock]
## var res := await TaskScope.wait(self, 1.5)
## if res.is_err():
##     return
## [/codeblock]
static func wait(node: Node, seconds: float) -> Result:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return Result.err_code("Async.Cancelled", "TaskScope.wait failed: node is invalid or outside tree.")
	var tree := node.get_tree()
	if tree == null:
		return Result.err_code("Async.NoTree", "TaskScope.wait failed: SceneTree unavailable.")

	if seconds <= 0.0:
		await tree.process_frame
	else:
		await tree.create_timer(seconds, false).timeout

	if not is_instance_valid(node) or not node.is_inside_tree():
		return Result.err_code("Async.Cancelled", "TaskScope.wait aborted: node was freed or left tree.")
	return Result.ok()
#endregion


#region Diagnostics
## 获取当前作用域的活跃任务数与历史统计快照。
func get_diagnostics() -> Dictionary:
	return {
		"scope": _scope_name,
		"valid": is_valid(),
		"disposed": _disposed,
		"generation": _generation,
		"active": _active_count,
		"completed": _completed_count,
		"cancelled": _cancelled_count,
		"timed_out": _timed_out_count,
		"failed": _failed_count,
	}
#endregion


#region Internal Helpers
func _precheck_scope() -> Result:
	if _disposed:
		_cancelled_count += 1
		return Result.err_code("Async.Cancelled", "[%s] Scope is already disposed." % _scope_name)
	if not is_valid():
		_cancelled_count += 1
		return Result.err_code("Async.Cancelled", "[%s] Owner is invalid or outside scene tree." % _scope_name)
	return null


func _is_interrupted(launch_gen: int, launch_token: CancellationToken) -> bool:
	return _disposed or launch_gen != _generation or launch_token.is_cancelled() or not is_valid()


static func _create_linked_token(parent_token: CancellationToken) -> CancellationToken:
	var child := CancellationToken.new()
	if parent_token != null:
		if parent_token.is_cancelled():
			child.cancel(parent_token.get_reason())
		else:
			parent_token.cancelled.connect(func(reason: String) -> void:
				child.cancel(reason)
			, CONNECT_ONE_SHOT)
	return child


static func _invoke_callable_async(callable: Callable, token: CancellationToken, on_done: Callable) -> void:
	(func(cb: Callable, tok: CancellationToken, done_cb: Callable) -> void:
		var out: Variant = null
		if cb.is_valid():
			if cb.get_argument_count() > 0:
				out = await cb.call(tok)
			else:
				out = await cb.call()
		done_cb.call(out)
	).call(callable, token, on_done)


func _poll_until(
	predicate: Callable,
	launch_gen: int,
	launch_token: CancellationToken,
	timeout_seconds: float
) -> bool:
	var tree := _get_safe_tree()
	var timed_out := false
	var start_msec := Time.get_ticks_msec()

	while not predicate.call():
		if _is_interrupted(launch_gen, launch_token):
			break
		if timeout_seconds > 0.0:
			var elapsed_sec := float(Time.get_ticks_msec() - start_msec) / 1000.0
			if elapsed_sec >= timeout_seconds:
				timed_out = true
				break
		if tree == null:
			break
		await tree.process_frame

	return timed_out


func _check_completion_guard(
	launch_gen: int,
	launch_token: CancellationToken,
	timed_out: bool,
	timeout_seconds: float,
	child_token: CancellationToken
) -> Result:
	# 1. 完成守卫 (Completion Guard)：优先拦截取消与宿主失效，丢弃过期结果
	if _is_interrupted(launch_gen, launch_token):
		_cancelled_count += 1
		var cancel_reason := launch_token.get_reason() if launch_token.is_cancelled() else "Scope or owner invalidated before completion."
		if child_token != null and not child_token.is_cancelled():
			child_token.cancel(cancel_reason)
		return Result.err_ex(
			"Async.Cancelled",
			"[%s] %s" % [_scope_name, cancel_reason],
			{"scope": _scope_name, "generation": launch_gen},
			false,
			null,
			FrameworkError.CATEGORY_CANCELLED
		)

	# 2. 超时拦截
	if timed_out:
		_timed_out_count += 1
		var timeout_msg := "[%s] Task timed out after %.2fs." % [_scope_name, timeout_seconds]
		if child_token != null and not child_token.is_cancelled():
			child_token.cancel(timeout_msg)
		return Result.err_ex(
			"Async.Timeout",
			timeout_msg,
			{"scope": _scope_name, "timeout_seconds": timeout_seconds},
			true,
			null,
			FrameworkError.CATEGORY_TIMEOUT
		)

	return null


func _unwrap_single_output(raw_res: Variant) -> Result:
	if raw_res is Result:
		var r := raw_res as Result
		if r.is_err():
			_failed_count += 1
		else:
			_completed_count += 1
		return r

	_completed_count += 1
	return Result.ok(raw_res)


func _get_safe_tree() -> SceneTree:
	if _has_owner:
		var owner_obj := instance_from_id(_owner_id)
		if owner_obj != null and is_instance_valid(owner_obj) and owner_obj is Node:
			var node := owner_obj as Node
			if node.is_inside_tree():
				return node.get_tree()
	return Engine.get_main_loop() as SceneTree
#endregion
