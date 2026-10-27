@tool
class_name BTBlackboard
extends RefCounted

## 行为树单实体黑板与享元节点记忆槽（Behavior Tree Blackboard & Per-Node Memory）。[br]
##
## [b]双区隔离设计：[/b][br]
## 1. [b]业务共享键值区 (`_data`)[/b]：供传感器、状态机与行为树条件/动作节点读写业务数据（如 `hp_ratio`, `target_dist`, `posture_broken`）；[br]
## 2. [b]节点私有记忆区 (`_node_memory`)[/b]：按 `node_id` 隔离存储各享元 [BTNode] 的跨帧运行状态（如 `BTWait` 剩余时间、`BTCooldown` 冷却到期时间戳），使同一棵 [BTTree] 可被 500 个实体同时安全共享。

#region Private Storage
var _data: Dictionary = {}
var _node_memory: Dictionary = {} ## {int (node_id): Dictionary}
#endregion


#regionTyped Data Accessors
func set_var(key: StringName, value: Variant) -> void:
	_data[key] = value


func set_value(key: StringName, value: Variant) -> void:
	_data[key] = value


func get_var(key: StringName, default_val: Variant = null) -> Variant:
	return _data.get(key, default_val)


func get_value(key: StringName, default_val: Variant = null) -> Variant:
	return _data.get(key, default_val)


func get_float(key: StringName, default_val: float = 0.0) -> float:
	var v: Variant = _data.get(key, null)
	return float(v) if v != null else default_val


func get_int(key: StringName, default_val: int = 0) -> int:
	var v: Variant = _data.get(key, null)
	return int(v) if v != null else default_val


func get_bool(key: StringName, default_val: bool = false) -> bool:
	var v: Variant = _data.get(key, null)
	return bool(v) if v != null else default_val


func get_vec3(key: StringName, default_val: Vector3 = Vector3.ZERO) -> Vector3:
	var v: Variant = _data.get(key, null)
	return v as Vector3 if v is Vector3 else default_val


func get_string_name(key: StringName, default_val: StringName = &"") -> StringName:
	var v: Variant = _data.get(key, null)
	return StringName(str(v)) if v != null else default_val


func has_key(key: StringName) -> bool:
	return _data.has(key)


func erase_key(key: StringName) -> void:
	_data.erase(key)


func clear_data() -> void:
	_data.clear()


func get_data_snapshot() -> Dictionary:
	return _data.duplicate()


func get_all() -> Dictionary:
	return _data.duplicate()
#endregion


#region Flyweight Per-Node Memory Slots
func set_node_mem(node_id: int, field: StringName, value: Variant) -> void:
	if not _node_memory.has(node_id):
		_node_memory[node_id] = {}
	var bucket: Dictionary = _node_memory[node_id]
	bucket[field] = value


func get_node_mem(node_id: int, field: StringName, default_val: Variant = null) -> Variant:
	if not _node_memory.has(node_id):
		return default_val
	var bucket: Dictionary = _node_memory[node_id]
	return bucket.get(field, default_val)


func clear_node_mem(node_id: int) -> void:
	_node_memory.erase(node_id)


func clear_all() -> void:
	_data.clear()
	_node_memory.clear()
#endregion
