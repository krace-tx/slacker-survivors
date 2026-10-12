class_name AssetCache
extends RefCounted

## 已加载资源的预算缓存（私有实现，仅供 [AssetService] 使用）。[br]
##
## 负责体积估算、TTL / 水位 / LRU（委托 [BudgetCache]）以及周期性闲置扫描。[br]
## 不读盘、不合并并发加载：这些由 [AssetService] 编排，读盘走 [ResourceLoaderAdapter]。

#region Constants
## 未传参时的缓存估算上限。贴图按 RGBA8 上界；默认 32MB，给低端机留余量。
const DEFAULT_MAX_BYTES: int = 32 * 1024 * 1024
## 未再次读取命中超过此时长则过期；默认 2 分钟，闲置尽快放槽。
const DEFAULT_TTL_MSEC: int = 2 * 60 * 1000
## 估算占用达到上限的这个比例就开始挤；默认 80%，避免顶格才动。
const WATERMARK: float = 0.8
## PackedScene 等估不出体积时计入水位的占位，避免上限被架空。
const UNKNOWN_BYTES: int = 256 * 1024
## 闲置扫描间隔。内存淘汰走入库时的 [method BudgetCache.flush]，默认 30 秒。
const FLUSH_INTERVAL_MSEC: int = 30 * 1000
#endregion

#region State
var _cache: BudgetCache
var _disposed: bool = false
#endregion

#region Lifecycle
func _init(max_bytes: int = DEFAULT_MAX_BYTES, ttl_msec: int = DEFAULT_TTL_MSEC) -> void:
	_cache = BudgetCache.new(max_bytes, ttl_msec, WATERMARK)
	_schedule_next_flush()


## 停止闲置扫描并清空缓存。
func dispose() -> void:
	_disposed = true
	clear()
#endregion

#region Public API
## 命中返回 [Resource] 并续 TTL；未命中或已过期返回 [code]null[/code]。
func read(path: String) -> Variant:
	return _cache.read(path)


## 估算体积并入库（使用默认 TTL）。放不下返回 [code]false[/code]，不占槽。
func store(path: String, resource: Resource) -> bool:
	var info := MemoryUtils.inspect(resource)
	var bytes: int = int(info.bytes) if info.known else UNKNOWN_BYTES
	return _cache.put(path, resource, bytes, 0)


## 钉住 [param path]，期间不会被挤出。
func pin(path: String) -> void:
	_cache.pin(path)


## 解除钉住。
func unpin(path: String) -> void:
	_cache.unpin(path)


## 丢掉 [param path] 的槽位。不在缓存里是空操作。
func drop(path: String) -> void:
	_cache.drop(path)


## 丢掉全部槽位。
func clear() -> void:
	_cache.clear()
#endregion

#region Internal
func _schedule_next_flush() -> void:
	if _disposed:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.create_timer(FLUSH_INTERVAL_MSEC / 1000.0).timeout.connect(_on_flush_timeout)


func _on_flush_timeout() -> void:
	if _disposed:
		return
	if _cache != null:
		_cache.flush(0)
	_schedule_next_flush()
#endregion
