@tool
class_name BTContext
extends RefCounted

## 行为树单实体运行上下文与实时可视化遥测器（Behavior Tree Execution Context & Telemetry）。[br]
##
## 每个 AI 实体（如 Boss 或小怪）各自持有一个轻量 [BTContext]，而共享同一个 [BTTree] 实例。

#region Public Properties
## 实体独享黑板。
var blackboard: BTBlackboard = BTBlackboard.new()

## 当前 Tick 的帧间隔秒数。
var delta: float = 0.0

## 上下文累计运行总秒数（单调递增，供 `BTCooldown` 计算冷却到期时间）。
var elapsed_time: float = 0.0

## 累计已执行的 Tick 次数。
var tick_count: int = 0

## 可选：分频决策间隔秒数（`<= 0.0` 表示每帧 Tick；设为 `0.1` 表示每 0.1 秒评估一次 AI 树）。
var tick_interval: float = 0.0
#endregion

#region Private Fields
var _actor_id: int = 0
var _accumulated_dt: float = 0.0
var _last_root_status: int = BTStatus.Status.FAILURE
var _node_status_map: Dictionary = {} ## {int (node_id): int (BTStatus.Status)}
var _node_tick_stamp: Dictionary = {} ## {int (node_id): int (tick_count)}
var _active_leaf_title: String = ""
var _debug_forced_node_id: int = 0
var _debug_forced_prev_id: int = 0
var _debug_forced_until: float = 0.0
var _synced_tree_epoch: int = -1
#endregion


#region Lifecycle
func _init(actor: Object = null, initial_data: Dictionary = {}, p_tick_interval: float = 0.0) -> void:
	_actor_id = actor.get_instance_id() if is_instance_valid(actor) else 0
	tick_interval = p_tick_interval
	for k: Variant in initial_data.keys():
		blackboard.set_var(StringName(str(k)), initial_data[k])


## 获取绑定的业务实体宿主（如 Boss `Node3D`、角色控制器）。
func get_actor() -> Object:
	if _actor_id == 0 or not is_instance_id_valid(_actor_id):
		return null
	return instance_from_id(_actor_id)
#endregion


#region Internal Tick, Epoch Sync & Telemetry Recording
## 获取已同步的行为树热重载纪元号（`O(1)` 整型比较，避免每帧查询黑板字典）。
func get_tree_epoch() -> int:
	return _synced_tree_epoch


## 当树首次运行或发生 `hot_reload_from_ir` 纪元递增时同步清理已废弃节点的遥测残留。
func sync_tree_epoch(epoch: int) -> void:
	if _synced_tree_epoch >= 0 and _synced_tree_epoch != epoch:
		_node_status_map.clear()
		_node_tick_stamp.clear()
	_synced_tree_epoch = epoch


## 由 [BTTree] 在每次 Tick 开始前调用。返回 `false` 表示当前处于分频节流跳过帧。
func begin_tick(dt: float) -> bool:
	var safe_dt: float = maxf(0.0, dt)
	elapsed_time += safe_dt
	if tick_interval > 0.0:
		_accumulated_dt += safe_dt
		if _accumulated_dt < tick_interval and tick_count > 0:
			return false
		delta = _accumulated_dt
		_accumulated_dt = 0.0
	else:
		delta = safe_dt

	tick_count += 1
	_active_leaf_title = ""
	if _debug_forced_node_id > 0 and elapsed_time >= _debug_forced_until:
		_debug_forced_node_id = 0
	return true


## 请求在可视化调试期间临时强制驱动指定 `node_id` 子树（支持画布双击强制触发验证）。
func request_debug_force_node(target_node_id: int, hold_sec: float = 1.5) -> void:
	if target_node_id <= 0:
		_debug_forced_node_id = 0
		return
	_debug_forced_node_id = target_node_id
	_debug_forced_until = elapsed_time + maxf(0.1, hold_sec)


## 查询当前是否处于调试强制节点驱动状态（`0` 表示正常求值）。
func get_debug_forced_node_id() -> int:
	return _debug_forced_node_id


## 消费一次调试强制切换标记（若刚切换强制目标则返回 `true`，供 `BTTree` 先 `abort` 旧分支）。
func consume_debug_force_switched() -> bool:
	if _debug_forced_node_id == _debug_forced_prev_id:
		return false
	_debug_forced_prev_id = _debug_forced_node_id
	return _debug_forced_node_id > 0


## 主动结束调试强制节点驱动。
func clear_debug_force_node() -> void:
	_debug_forced_node_id = 0
	_debug_forced_prev_id = 0
	_debug_forced_until = 0.0


## 由 [BTNode] 在每次 `_on_tick` 完成时自动记录节点执行状态。
func record_node_status(node_id: int, status: int, is_leaf: bool = false, title: String = "") -> void:
	_node_status_map[node_id] = status
	_node_tick_stamp[node_id] = tick_count
	if is_leaf and (status == BTStatus.Status.RUNNING or status == BTStatus.Status.SUCCESS):
		_active_leaf_title = title


func set_last_root_status(status: int) -> void:
	_last_root_status = status


func get_last_root_status() -> int:
	return _last_root_status
#endregion


#region Live Visual Blueprint Telemetry Queries
## 查询指定 `node_id` 在当前最新 Tick 中是否被评估过，并返回其状态（未被当前帧评估过的分支返回 `-1`）。
func get_live_node_status(node_id: int) -> int:
	if int(_node_tick_stamp.get(node_id, -1)) != tick_count:
		return -1
	return int(_node_status_map.get(node_id, -1))


## 获取当前激活的叶节点可读名称（如 `"Flame Nova AoE"`）。
func get_active_leaf_title() -> String:
	return _active_leaf_title


## 导出完整遥测快照（供可视化 AST 蓝图面板实时高亮）。
func get_telemetry_snapshot() -> Dictionary:
	var active_nodes: Dictionary = {}
	for nid: Variant in _node_status_map.keys():
		var id_int: int = int(nid)
		if int(_node_tick_stamp.get(id_int, -1)) == tick_count:
			active_nodes[id_int] = String(BTStatus.to_string_name(int(_node_status_map[id_int])))
	return {
		"tick_count": tick_count,
		"elapsed_time": snappedf(elapsed_time, 0.01),
		"root_status": String(BTStatus.to_string_name(_last_root_status)),
		"active_leaf": _active_leaf_title,
		"active_nodes": active_nodes,
		"blackboard": blackboard.get_data_snapshot(),
	}
#endregion
