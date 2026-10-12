class_name MemoryStorageDriver
extends StorageDriver

## 内存存储驱动：负责处理运行时的数据缓存与内存生命周期管理。[br]
##
## 实际缓存与容量淘汰策略委托给 [StorageCache]（[code]internal/storage_cache.gd[/code]）。[br]
## 本驱动作为统一 [StorageDriver] 契约的实现，返回标准化 [Result]。

#region State
var _cache: StorageCache
#endregion

#region Lifecycle
func _init(max_bytes: int = StorageCache.DEFAULT_MAX_BYTES, default_ttl_msec: int = StorageCache.DEFAULT_TTL_MSEC) -> void:
	initialize(max_bytes, default_ttl_msec)


## 初始化内存池配置（供 StorageService 初始化时注入）
func initialize(max_bytes: int = StorageCache.DEFAULT_MAX_BYTES, default_ttl_msec: int = StorageCache.DEFAULT_TTL_MSEC) -> void:
	_cache = StorageCache.new(max_bytes, default_ttl_msec)
#endregion

#region Overrides
## 从内存读取数据，命中时自动续期访问时间戳 (LRU)。
func read(key: StringName, _kwargs: Dictionary = {}) -> Result:
	var cached: Variant = _cache.read(key)
	if cached == null:
		return Result.err(ERR_DOES_NOT_EXIST)
	return Result.ok(cached)


## 写入内存，自动估算体积并触发水位线与 LRU 淘汰。
func write(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	if data == null:
		return Result.err("Write failed: data is null")

	var item_ttl_sec: float = float(kwargs.get("memory_ttl", -1.0))
	if _cache.put(key, data, item_ttl_sec):
		return Result.ok()
	return Result.err("Memory limit exceeded: entry is larger than available capacity")


## 检查内存中是否存在且未过期
func has(key: StringName) -> Result:
	return Result.ok(_cache.has(key))


## 从内存中物理移除指定 key
func delete(key: StringName) -> Result:
	if _cache.drop(key):
		return Result.ok()
	return Result.err(ERR_DOES_NOT_EXIST)
#endregion

#region Public API
## 释放指定 key 的内存缓存槽
func release(key: StringName) -> void:
	_cache.drop(key)


## 清空所有内存缓存（供游戏退出或场景清理时调用）
func clear() -> void:
	_cache.clear()
#endregion
