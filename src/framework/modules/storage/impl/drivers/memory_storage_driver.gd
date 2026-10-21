class_name MemoryStorageDriver
extends StorageDriver

## 内存存储驱动：负责处理运行时的数据缓存与内存生命周期管理。[br]
##
## 核心职责：[br]
## 1. 实际缓存与容量淘汰策略委托给 [StorageCache]；[br]
## 2. [b]深拷贝引用隔离（Deep-Copy Isolation）[/b]：在写入与读取 [Dictionary]、[Array]、[PackedByteArray] 时强制执行副本克隆，
##    彻底阻断业务层在外部直接修改字典导致的 L1 缓存脏数据污染（Reference Aliasing Bug）；[br]
## 3. 统一返回携带 [StorageError] 标准错误码的 [Result]。

#region State
var _cache: StorageCache
#endregion


#region Lifecycle
func _init(max_bytes: int = StorageCache.DEFAULT_MAX_BYTES, default_ttl_msec: int = StorageCache.DEFAULT_TTL_MSEC) -> void:
	initialize(max_bytes, default_ttl_msec)


## 初始化内存池配置
func initialize(max_bytes: int = StorageCache.DEFAULT_MAX_BYTES, default_ttl_msec: int = StorageCache.DEFAULT_TTL_MSEC) -> void:
	_cache = StorageCache.new(max_bytes, default_ttl_msec)
#endregion


#region Overrides
## 从内存读取数据，命中时自动续期访问时间戳 (LRU)，并返回深拷贝隔离副本。
func read(key: StringName, _kwargs: Dictionary = {}) -> Result:
	var cached: Variant = _cache.read(key)
	if cached == null:
		return Result.err_ex(
			StorageError.NOT_FOUND,
			"Memory cache miss for key '%s'." % String(key),
			{"key": String(key)},
			false,
			ERR_DOES_NOT_EXIST,
			FrameworkError.CATEGORY_NOT_FOUND
		)
	return Result.ok(clone_payload(cached))


## 写入内存（自动保存深拷贝隔离副本，估算体积并触发水位线与 LRU 淘汰）。
func write(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result:
	if key.is_empty():
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Memory write failed: key cannot be empty.",
			{},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)
	if data == null:
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Memory write failed: data is null for key '%s'." % String(key),
			{"key": String(key)},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var item_ttl_sec: float = float(kwargs.get("memory_ttl", -1.0))
	var isolated_copy: Variant = clone_payload(data)
	if _cache.put(key, isolated_copy, item_ttl_sec):
		return Result.ok()

	return Result.err_ex(
		StorageError.MEMORY_LIMIT_EXCEEDED,
		"Memory limit exceeded: entry '%s' is larger than available cache capacity." % String(key),
		{"key": String(key)},
		false,
		ERR_OUT_OF_MEMORY,
		FrameworkError.CATEGORY_GENERAL
	)


## 检查内存中是否存在且未过期
func has(key: StringName) -> Result:
	return Result.ok(_cache.has(key))


## 从内存中物理移除指定 key（幂等操作：不存在时返回 NOT_FOUND 供上层判断，亦可忽略）
func delete(key: StringName) -> Result:
	if _cache.drop(key):
		return Result.ok()
	return Result.err_ex(
		StorageError.NOT_FOUND,
		"Memory delete missed: key '%s' not in cache." % String(key),
		{"key": String(key)},
		false,
		ERR_DOES_NOT_EXIST,
		FrameworkError.CATEGORY_NOT_FOUND
	)
#endregion


#region Public & Static Helpers
## 释放指定 key 的内存缓存槽
func release(key: StringName) -> void:
	_cache.drop(key)


## 清空所有内存缓存（供游戏退出或场景清理时调用）
func clear() -> void:
	_cache.clear()


func get_diagnostics() -> Dictionary:
	return _cache.get_diagnostics() if _cache != null else {}


## 对可变容器类型执行深拷贝，防止调用方持有的引用污染缓存内部状态。
static func clone_payload(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	if value is PackedByteArray:
		return (value as PackedByteArray).duplicate()
	return value
#endregion
