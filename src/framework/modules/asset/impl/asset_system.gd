class_name AssetSystem
extends BaseAssetSystem

## 按 [code]res://[/code] 路径加载与管理资源。纯 RefCounted 实现，轻量、零 SceneTree 定时器耦合。[br]
##
## [b]核心设计机制：[/b][br]
## 1. [b]同步缓存直通（[method get_cached]）[/b]：高频路径（如 SFX 播放）同步读取已缓存资源，零协程状态机分配、零帧延迟；[br]
## 2. [b]信号驱动请求合并（Signal-Driven Inflight Ticket）[/b]：同一路径的并发 [method load] 挂接在同一票据信号上，
##    主加载完成当帧立即广播唤醒所有等待协程，彻底消除逐帧轮询与 1 帧人为延迟；[br]
## 3. [b]双阶段真并发预加载（[method preload_batch]）[/b]：先批量向引擎多线程队列点火全部未缓存路径，再统一等待收割；[br]
## 4. [b]释放屏障（Release Barrier）[/b]：若加载尚未完成期间外部调用了 [method release] 或 [method clear]，
##    当前请求调用方仍能拿到 [Resource] 结果，但不再写回缓存池，杜绝脏复活。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"asset"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = []
#endregion

#region Inner Types
class _InflightTicket extends RefCounted:
	signal completed(result: Result)
	var released_before_done: bool = false
	var resolved: bool = false
	var result: Result = null

	func resolve(p_result: Result) -> void:
		if resolved:
			return
		resolved = true
		result = p_result
		completed.emit(p_result)
#endregion

#region State
## 已完成的加载。TTL / 水位 / LRU 由 [AssetCache] 管。
var _cache: AssetCache
## 引擎边界：存在性检查、C++ 缓存直通与后台线程加载。
var _loader: ResourceLoaderAdapter
## 正在进行中的异步加载票据表：path (String) -> _InflightTicket
var _inflight: Dictionary = {}
var _disposed: bool = false
#endregion

#region Lifecycle
func _init(max_bytes: int = AssetCache.DEFAULT_MAX_BYTES, ttl_msec: int = AssetCache.DEFAULT_TTL_MSEC) -> void:
	_cache = AssetCache.new(max_bytes, ttl_msec)
	_loader = ResourceLoaderAdapter.new()


func initialize() -> Result:
	return Result.ok()


func dispose() -> void:
	_disposed = true
	_cache.dispose()
	for path in _inflight:
		var ticket: _InflightTicket = _inflight[path]
		if ticket != null:
			ticket.released_before_done = true
#endregion

#region Public API
## 同步获取已缓存在内存中的资源实例（零协程分配、零磁盘 I/O）。未命中返回 null。
func get_cached(path: String) -> Resource:
	if _disposed or path.is_empty():
		return null
	var cached := _cache.read(path) as Resource
	if cached != null:
		return cached
	# 若引擎 C++ ResourceCache 中已有活跃引用，直接提升至 AssetCache 并同步返回
	var engine_res := _loader.get_engine_cached(path)
	if engine_res != null:
		_cache.store(path, engine_res)
		return engine_res
	return null


## 异步加载 [param path]。必须 [code]await[/code] 才能拿到 [Result]；成功时 [member Result.value] 为 [Resource]。
func load(path: String) -> Result:
	if _disposed:
		return Result.err_code("Asset.Disposed", "AssetSystem has been disposed.")
	if path.is_empty():
		return Result.err_code("Asset.EmptyPath", "Load failed: path is empty.")

	# 1. 缓存命中快路径（含引擎 C++ 缓存提升）：零磁盘 I/O、零帧等待直接返回
	var cached := get_cached(path)
	if cached != null:
		return Result.ok(cached)

	# 2. 并发合并快路径：若同一路径正在加载中，直接挂接票据信号，当帧同步唤醒
	if _inflight.has(path):
		var existing_ticket: _InflightTicket = _inflight[path]
		if existing_ticket.resolved:
			return existing_ticket.result
		return await existing_ticket.completed

	# 3. 首次发起加载：先校验磁盘/PCK 存在性，再创建信号票据并发起后台加载
	if not _loader.exists(path):
		return Result.err_code("Asset.NotFound", "Asset not found: '%s'." % path)

	var ticket := _InflightTicket.new()
	_inflight[path] = ticket

	var fetched: Result = await _loader.load_threaded(path)

	# 4. 先摘除 inflight 占位，再按释放屏障决定是否写入缓存，最后立即广播唤醒所有等待者
	_inflight.erase(path)
	if not _disposed and not ticket.released_before_done and fetched.is_ok():
		_cache.store(path, fetched.value as Resource)

	ticket.resolve(fetched)
	return fetched


## 双阶段真并发批量预加载一组资源路径至内存缓存中。
func preload_batch(paths: Array[String]) -> Result:
	if _disposed:
		return Result.err_code("Asset.Disposed", "AssetSystem has been disposed.")
	if paths.is_empty():
		return Result.ok({})

	var loaded_map: Dictionary = {}
	var pending_paths: Array[String] = []

	# 阶段一：同步筛除已缓存项，并将所有未缓存项一次性提交至底层多线程加载队列（打满并发 I/O）
	for path in paths:
		if path.is_empty() or loaded_map.has(path):
			continue
		var cached := get_cached(path)
		if cached != null:
			loaded_map[path] = cached
			continue
		if not _loader.exists(path):
			return Result.err_code("Asset.NotFound", "Asset not found in batch preload: '%s'." % path)
		_loader.request_threaded(path)
		pending_paths.append(path)

	# 阶段二：收割已在后台并行解码的资源结果
	for path in pending_paths:
		var res: Result = await self.load(path)
		if res.is_err():
			return res
		loaded_map[path] = res.value

	return Result.ok(loaded_map)


## 查询指定路径的资源当前是否已在内存缓存池中命中（未过期）。
func has_cached(path: String) -> bool:
	if path.is_empty() or _disposed:
		return false
	return _cache.has(path)


## 钉住指定路径的缓存资源，期间不会被 TTL 或 LRU 水位淘汰。
func pin(path: String) -> void:
	if path.is_empty() or _disposed:
		return
	_cache.pin(path)


## 解除指定路径缓存资源的钉住状态。
func unpin(path: String) -> void:
	if path.is_empty() or _disposed:
		return
	_cache.unpin(path)


## 释放 [param path] 占用的缓存槽。若该路径正在加载中，标记完成后不再写回缓存。
func release(path: String) -> void:
	if path.is_empty():
		return
	_cache.drop(path)
	if _inflight.has(path):
		var ticket: _InflightTicket = _inflight[path]
		if ticket != null:
			ticket.released_before_done = true


## 丢掉全部缓存。正在 [method load] 的完成后也不再写回。
func clear() -> void:
	_cache.clear()
	for path in _inflight:
		var ticket: _InflightTicket = _inflight[path]
		if ticket != null:
			ticket.released_before_done = true
#endregion
