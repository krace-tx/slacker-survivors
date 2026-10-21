class_name StorageCache
extends RefCounted

## 内存存储缓存（私有实现，仅供 [MemoryStorageDriver] 使用）。[br]
##
## 负责基于 [BudgetCache] 进行内存槽位管理、体积估算、TTL 解析、水位线控制与 LRU 淘汰。

const DEFAULT_MAX_BYTES: int = 32 * 1024 * 1024   ## 默认 32MB
const DEFAULT_TTL_MSEC: int = 2 * 60 * 1000       ## 默认 2 分钟
const WATERMARK: float = 0.8                      ## 水位线 80%

var _cache: BudgetCache
var _max_bytes: int = DEFAULT_MAX_BYTES


func _init(max_bytes: int = DEFAULT_MAX_BYTES, default_ttl_msec: int = DEFAULT_TTL_MSEC) -> void:
	initialize(max_bytes, default_ttl_msec)


func initialize(max_bytes: int = DEFAULT_MAX_BYTES, default_ttl_msec: int = DEFAULT_TTL_MSEC) -> void:
	_max_bytes = max_bytes if max_bytes > 0 else DEFAULT_MAX_BYTES
	_cache = BudgetCache.new(_max_bytes, default_ttl_msec, WATERMARK)


## 读取指定 key 的缓存，命中时自动续期访问时间戳 (LRU)
func read(key: StringName) -> Variant:
	return _cache.read(key)


## 写入缓存数据，估算体积并解析 memory_ttl
func put(key: StringName, data: Variant, memory_ttl_sec: float = -1.0) -> bool:
	var bytes := MemoryUtils.estimate_bytes(data)
	var ttl_msec: int = -1
	if memory_ttl_sec > 0.0:
		ttl_msec = int(memory_ttl_sec * 1000.0)
	elif memory_ttl_sec == 0.0:
		ttl_msec = 0

	return _cache.put(key, data, bytes, ttl_msec)


## 检查 key 是否存在且未过期
func has(key: StringName) -> bool:
	return _cache.has(key)


## 移除指定 key
func drop(key: StringName) -> bool:
	return _cache.drop(key)


## 清空全部缓存
func clear() -> void:
	_cache.clear()


func get_diagnostics() -> Dictionary:
	return {
		"max_bytes": _max_bytes,
	}
