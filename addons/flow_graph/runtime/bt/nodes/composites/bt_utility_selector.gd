@tool
class_name BTUtilitySelector
extends BTNode

## 效用评分选择组合节点（Utility AI Selector Composite Node）。[br]
##
## [b]享元执行契约：[/b][br]
## 1. 每帧通过预编译规格字典与 [FlowUtilityScorer] 对全部子分支零字符串分配打分，并将本帧得分写入单实体记忆槽 `last_scores`；[br]
## 2. [b]防抖动滞回 (`momentum`)[/b]：上一帧处于 `RUNNING` 且本帧基础分达标（`> 0.0` 且 `>= min_score`）的子分支自动获得 `+ momentum` 惯性加分；[br]
## 3. [b]低分淘汰 (`min_score`)[/b]：低于 `min_score` 的分支直接跳过；全部分支不达标时立即返回 `FAILURE`；[br]
## 4. [b]前 K 加权抽样 (`top_k`)[/b]：默认 `top_k == 1` 执行零闭包分配的确定性最高分抢占；`top_k > 1` 在前 K 候选池内按效用分加权抽样。

#region Constants & Readonly Config
const MEM_RUNNING_IDX: StringName = &"running_idx"
const MEM_LAST_SCORES: StringName = &"last_scores"

var child_specs: Array[Dictionary] = []
var momentum: float = 0.10
var min_score: float = 0.01
var top_k: int = 1
var memory: bool = false
var utility_lookup: Callable = Callable()

var _compiled_specs: Array[Dictionary] = []
#endregion


#region Lifecycle & Assembly
func _init(
	p_node_id: int = 0,
	p_title: String = "UtilitySelector",
	p_child_specs: Array[Dictionary] = [],
	p_momentum: float = 0.10,
	p_min_score: float = 0.01,
	p_top_k: int = 1,
	p_memory: bool = false,
	p_utility_lookup: Callable = Callable()
) -> void:
	super._init(p_node_id, &"UtilitySelector", p_title, false)
	for sp: Dictionary in p_child_specs:
		var cloned: Dictionary = sp.duplicate(true)
		child_specs.append(cloned)
		_compiled_specs.append(FlowUtilityScorer.compile_spec(cloned))
	momentum = maxf(0.0, p_momentum)
	min_score = maxf(0.0, p_min_score)
	top_k = maxi(1, p_top_k)
	memory = p_memory
	utility_lookup = p_utility_lookup


## 添加子节点并同步指定其效用评分配置字典（链式组装辅助）。
func add_utility_child(child: BTNode, spec: Dictionary = {}) -> BTUtilitySelector:
	if child != null:
		while child_specs.size() < children.size():
			child_specs.append({})
			_compiled_specs.append(FlowUtilityScorer.compile_spec({}))
		children.append(child)
		var cloned: Dictionary = spec.duplicate(true)
		child_specs.append(cloned)
		_compiled_specs.append(FlowUtilityScorer.compile_spec(cloned))
	return self


## 更新指定子分支索引的效用配置字典，并同步刷新预编译规格缓存。
func set_child_spec(idx: int, spec: Dictionary) -> void:
	if idx < 0:
		return
	while child_specs.size() <= idx:
		child_specs.append({})
		_compiled_specs.append(FlowUtilityScorer.compile_spec({}))
	var cloned: Dictionary = spec.duplicate(true)
	child_specs[idx] = cloned
	_compiled_specs[idx] = FlowUtilityScorer.compile_spec(cloned)


func clear() -> void:
	utility_lookup = Callable()
	child_specs.clear()
	_compiled_specs.clear()
	super.clear()
#endregion


#region Flyweight Execution
func _on_tick(ctx: BTContext) -> int:
	var count: int = children.size()
	if count == 0:
		return BTStatus.Status.FAILURE

	var prev_running_idx: int = int(ctx.blackboard.get_node_mem(node_id, MEM_RUNNING_IDX, -1))
	var scores: Array[float] = _evaluate_all_scores(ctx, count, prev_running_idx)
	ctx.blackboard.set_node_mem(node_id, MEM_LAST_SCORES, scores)

	if memory and prev_running_idx >= 0 and prev_running_idx < count:
		var locked_status: int = children[prev_running_idx].tick(ctx)
		if locked_status == BTStatus.Status.RUNNING:
			return BTStatus.Status.RUNNING
		ctx.blackboard.set_node_mem(node_id, MEM_RUNNING_IDX, -1)
		return locked_status

	var order: Array[int] = _build_candidate_order(scores, prev_running_idx)
	for idx: int in order:
		var status: int = children[idx].tick(ctx)
		if status != BTStatus.Status.FAILURE:
			if prev_running_idx >= 0 and prev_running_idx != idx and prev_running_idx < count:
				children[prev_running_idx].abort(ctx)
			ctx.blackboard.set_node_mem(
				node_id,
				MEM_RUNNING_IDX,
				idx if status == BTStatus.Status.RUNNING else -1
			)
			return status

	if prev_running_idx >= 0 and prev_running_idx < count:
		children[prev_running_idx].abort(ctx)
	ctx.blackboard.set_node_mem(node_id, MEM_RUNNING_IDX, -1)
	return BTStatus.Status.FAILURE


func _evaluate_all_scores(ctx: BTContext, count: int, prev_running_idx: int) -> Array[float]:
	var out: Array[float] = []
	for i: int in range(count):
		var c_spec: Dictionary = _compiled_specs[i] if i < _compiled_specs.size() else (child_specs[i] if i < child_specs.size() else {})
		var base_sc: float = FlowUtilityScorer.evaluate(c_spec, ctx.blackboard, ctx, utility_lookup)
		var is_viable: bool = base_sc > 0.0 and base_sc >= min_score
		if i == prev_running_idx and is_viable and momentum > 0.0:
			base_sc += momentum
		out.append(base_sc)
	return out


func _build_candidate_order(scores: Array[float], prev_running_idx: int) -> Array[int]:
	var eligible: Array[int] = []
	for i: int in range(scores.size()):
		var sc: float = scores[i]
		if sc >= min_score and (min_score == 0.0 or sc > 0.0):
			eligible.append(i)

	var n_elig: int = eligible.size()
	if n_elig <= 1:
		return eligible

	# 零闭包分配原位插入排序（按分数降序，同分保持左优索引稳定）
	for i: int in range(1, n_elig):
		var key_idx: int = eligible[i]
		var key_sc: float = scores[key_idx]
		var j: int = i - 1
		while j >= 0:
			var cmp_idx: int = eligible[j]
			var cmp_sc: float = scores[cmp_idx]
			var cmp_wins: bool = (cmp_sc > key_sc) if not is_equal_approx(cmp_sc, key_sc) else (cmp_idx < key_idx)
			if cmp_wins:
				break
			eligible[j + 1] = cmp_idx
			j -= 1
		eligible[j + 1] = key_idx

	if top_k <= 1:
		return eligible

	var pool_size: int = mini(top_k, n_elig)
	var pool_idx: Array[int] = eligible.slice(0, pool_size)
	var rest_idx: Array[int] = eligible.slice(pool_size)

	var sampled: Array[int] = []
	if prev_running_idx >= 0 and pool_idx.has(prev_running_idx):
		sampled.append(prev_running_idx)
		pool_idx.erase(prev_running_idx)

	var pool_weights: Array[float] = []
	var total_w: float = 0.0
	for idx_p: int in pool_idx:
		var w: float = maxf(0.0, scores[idx_p])
		pool_weights.append(w)
		total_w += w

	while not pool_idx.is_empty():
		var pick: int = 0
		if total_w > 0.0:
			var roll: float = randf() * total_w
			var acc: float = 0.0
			pick = pool_idx.size() - 1
			for j: int in range(pool_weights.size()):
				acc += pool_weights[j]
				if roll <= acc:
					pick = j
					break
		else:
			pick = randi() % pool_idx.size()
		total_w = maxf(0.0, total_w - pool_weights[pick])
		sampled.append(pool_idx[pick])
		pool_idx.remove_at(pick)
		pool_weights.remove_at(pick)

	for tail_i: int in rest_idx:
		sampled.append(tail_i)
	return sampled
#endregion
