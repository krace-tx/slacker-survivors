class_name BTWeightedSelector
extends BTNode

## 加权随机选择组合节点（Weighted Random Selector Composite Node）。[br]
##
## [b]享元执行契约：[/b][br]
## 1. 若 `ctx.blackboard` 节点记忆槽记录了上一帧处于 `RUNNING` 的子索引，则锁定继续评估该子分支直至其结束；[br]
## 2. 否则按 [member weights] 加权不放回随机抽取子分支顺序依次尝试，直到某个子分支返回 `SUCCESS` 或 `RUNNING`。

#region Constants & Config
const _MEM_RUNNING_IDX: StringName = &"running_idx"

var weights: Array[float] = []
#endregion


#region Execution
func _init(
	p_node_id: int = 0,
	p_title: String = "WeightedSelector",
	p_weights: Array[float] = []
) -> void:
	super._init(p_node_id, &"WeightedSelector", p_title, false)
	weights = p_weights.duplicate()


## 添加子节点并同步指定其随机权重（链式组装辅助）。
func add_weighted_child(child: BTNode, weight: float = 1.0) -> BTWeightedSelector:
	if child != null:
		while weights.size() < children.size():
			weights.append(1.0)
		children.append(child)
		weights.append(maxf(0.0, weight))
	return self


func _on_tick(ctx: BTContext) -> int:
	var count: int = children.size()
	if count == 0:
		return BTStatus.Status.FAILURE

	var running_idx: int = int(ctx.blackboard.get_node_mem(node_id, _MEM_RUNNING_IDX, -1))
	if running_idx >= 0 and running_idx < count:
		var locked_status: int = children[running_idx].tick(ctx)
		if locked_status == BTStatus.Status.RUNNING:
			return BTStatus.Status.RUNNING
		ctx.blackboard.clear_node_mem(node_id)
		return locked_status

	var order: Array[int] = _build_weighted_order(count)
	for idx: int in order:
		var status: int = children[idx].tick(ctx)
		if status == BTStatus.Status.RUNNING:
			ctx.blackboard.set_node_mem(node_id, _MEM_RUNNING_IDX, idx)
			return BTStatus.Status.RUNNING
		if status == BTStatus.Status.SUCCESS:
			ctx.blackboard.clear_node_mem(node_id)
			return BTStatus.Status.SUCCESS

	ctx.blackboard.clear_node_mem(node_id)
	return BTStatus.Status.FAILURE


func _build_weighted_order(count: int) -> Array[int]:
	var remaining_idx: Array[int] = []
	var remaining_w: Array[float] = []
	for i: int in range(count):
		remaining_idx.append(i)
		var w: float = weights[i] if i < weights.size() else 1.0
		remaining_w.append(maxf(0.0, w))

	var order: Array[int] = []
	while not remaining_idx.is_empty():
		var total_w: float = 0.0
		for w_val: float in remaining_w:
			total_w += w_val

		var picked_pos: int = 0
		if total_w > 0.0:
			var roll: float = randf() * total_w
			var acc: float = 0.0
			picked_pos = remaining_idx.size() - 1
			for j: int in range(remaining_w.size()):
				acc += remaining_w[j]
				if roll <= acc:
					picked_pos = j
					break
		else:
			picked_pos = randi() % remaining_idx.size()

		order.append(remaining_idx[picked_pos])
		remaining_idx.remove_at(picked_pos)
		remaining_w.remove_at(picked_pos)
	return order
#endregion
