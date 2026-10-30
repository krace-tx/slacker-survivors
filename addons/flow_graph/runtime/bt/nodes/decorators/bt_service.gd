@tool
class_name BTService
extends BTNode

## 周期性黑板刷新服务装饰节点（Periodic Blackboard Service Decorator Node）。[br]
##
## 每次被评估时检查 `ctx.blackboard` 记忆槽中的下次触发时间戳；到期则调用 `service_cb` 刷新黑板并按 `interval_sec ± jitter_sec` 重设下次时间，随后透传评估唯一子节点。

#region Constants & Config
const _MEM_NEXT_RUN_AT: StringName = &"next_run_at"

var service_cb: Callable = Callable()
var service_key: StringName = &""
var interval_sec: float = 0.25
var jitter_sec: float = 0.05
var params: Dictionary = {}

var _service_argc: int = 0
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_service_cb: Callable = Callable(),
	p_interval_sec: float = 0.25,
	p_jitter_sec: float = 0.05,
	p_title: String = "",
	p_service_key: StringName = &"",
	p_params: Dictionary = {}
) -> void:
	var resolved_title: String = p_title if not p_title.is_empty() else "Service"
	super._init(p_node_id, &"Service", resolved_title, false)
	service_cb = p_service_cb
	_service_argc = service_cb.get_argument_count() if service_cb.is_valid() else 0
	service_key = p_service_key
	interval_sec = maxf(0.0, p_interval_sec)
	jitter_sec = maxf(0.0, p_jitter_sec)
	params = p_params.duplicate(true)


func _on_tick(ctx: BTContext) -> int:
	var next_run_at: float = float(ctx.blackboard.get_node_mem(node_id, _MEM_NEXT_RUN_AT, -1.0))
	if next_run_at < 0.0 or ctx.elapsed_time + 0.0001 >= next_run_at:
		_invoke_service(ctx)
		var step_dt: float = interval_sec
		if jitter_sec > 0.0:
			step_dt = randf_range(maxf(0.0, interval_sec - jitter_sec), interval_sec + jitter_sec)
		ctx.blackboard.set_node_mem(node_id, _MEM_NEXT_RUN_AT, ctx.elapsed_time + step_dt)

	if children.is_empty():
		return BTStatus.Status.SUCCESS
	return children[0].tick(ctx)


func _invoke_service(ctx: BTContext) -> void:
	if not service_cb.is_valid():
		return
	if _service_argc >= 2:
		service_cb.call(ctx, params)
	elif _service_argc == 1:
		service_cb.call(ctx)
	else:
		service_cb.call()


func clear() -> void:
	service_cb = Callable()
	_service_argc = 0
	params.clear()
	super.clear()
#endregion
