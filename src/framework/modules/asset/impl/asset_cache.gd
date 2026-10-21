class_name AssetCache
extends RefCounted

## 已加载资源的预算缓存（私有实现，仅供 [AssetSystem] 使用）。[br]
##
## 负责基于 [MemoryUtils] 的 O(1) 体积估算，并将 TTL / 水位 / LRU 惰性淘汰委托给 [BudgetCache]。[br]
## 纯 RefCounted 实现，不挂载任何后台轮询定时器，完全零耦合 [SceneTree]。

#region Constants
## 未传参时的缓存估算上限。贴图按 RGBA8 上界；默认 32MB，给低端机留余量。
const DEFAULT_MAX_BYTES: int = 32 * 1024 * 1024
## 未再次读取命中超过此时长则过期；默认 2 分钟，闲置尽快放槽。
const DEFAULT_TTL_MSEC: int = 2 * 60 * 1000
## 估算占用达到上限的这个比例就开始挤；默认 80%，避免顶格才动。
const WATERMARK: float = 0.8
## PackedScene 等估不出体积时计入水位的占位，避免上限被架空。
const UNKNOWN_BYTES: int = 256 * 1024
#endregion

#region State
var _cache: BudgetCache
var _disposed: bool = false
#endregion

#region Lifecycle
func _init(max_bytes: int = DEFAULT_MAX_BYTES, ttl_msec: int = DEFAULT_TTL_MSEC) -> void:
	_cache = BudgetCache.new(max_bytes, ttl_msec, WATERMARK)


## 销毁并清空缓存。
func dispose() -> void:
	_disposed = true
	clear()
#endregion

#region Public API
## 命中返回 [Resource] 并续 TTL；未命中或已过期返回 [code]null[/code]。
func read(path: String) -> Variant:
	if _disposed or path.is_empty():
		return null
	return _cache.read(StringName(path))


## 查询 [param path] 是否仍在缓存中且未过期（不续期访问时间）。
func has(path: String) -> bool:
	if _disposed or path.is_empty():
		return false
	return _cache.has(StringName(path))


## 估算体积并入库（使用默认 TTL）。放不下返回 [code]false[/code]，不占槽。
func store(path: String, resource: Resource) -> bool:
	if _disposed or path.is_empty() or resource == null:
		return false
	var bytes := MemoryUtils.estimate_resource_bytes(resource, UNKNOWN_BYTES)
	return _cache.put(StringName(path), resource, bytes, 0)


## 钉住 [param path]，期间不会被挤出。
func pin(path: String) -> void:
	if not _disposed and not path.is_empty():
		_cache.pin(StringName(path))


## 解除钉住。
func unpin(path: String) -> void:
	if not _disposed and not path.is_empty():
		_cache.unpin(StringName(path))


## 丢掉 [param path] 的槽位。不在缓存里是空操作。
func drop(path: String) -> void:
	if not path.is_empty() and _cache != null:
		_cache.drop(StringName(path))


## 丢掉全部槽位。
func clear() -> void:
	if _cache != null:
		_cache.clear()
#endregion
