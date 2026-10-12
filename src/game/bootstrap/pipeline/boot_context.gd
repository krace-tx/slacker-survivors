class_name BootContext
extends RefCounted

## 游戏启动共享上下文 (Boot Context)。[br]
## 用于在启动管线的阶段（Phases）与微任务（Steps）之间安全传递数据、记录启动耗时与收集诊断信息。

var start_time_ms: int = 0
var end_time_ms: int = 0
var _data: Dictionary = {}
var _metrics: Dictionary = {}


func _init() -> void:
	start_time_ms = Time.get_ticks_msec()


## 写入上下文键值数据
func set_data(key: String, value: Variant) -> void:
	_data[key] = value


## 读取上下文键值数据
func get_data(key: String, default_value: Variant = null) -> Variant:
	return _data.get(key, default_value)


## 检查是否存在指定键值
func has_data(key: String) -> bool:
	return _data.has(key)


## 记录步骤或阶段耗时指标 (毫秒)
func record_metric(task_name: String, duration_ms: int) -> void:
	_metrics[task_name] = duration_ms


## 获取全部耗时指标
func get_metrics() -> Dictionary:
	return _metrics.duplicate()


## 标记全部启动结束并返回总耗时 (毫秒)
func finish() -> int:
	end_time_ms = Time.get_ticks_msec()
	var total := end_time_ms - start_time_ms
	_metrics["total_boot_time_ms"] = total
	return total
