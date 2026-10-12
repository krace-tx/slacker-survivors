class_name AssetSystem
extends BaseAssetSystem

## 按 [code]res://[/code] 路径异步加载资源。已加载过的走缓存。
## 纯 RefCounted 实现，轻量、无需挂载场景树。
## 调用方必须 [code]await[/code] [method load]；不要先接到变量上再二次 await。
## [method release] / [method clear] 只放掉本服务的引用；正在 [method load] 的完成后也不再写回。
## TTL 与内存上限只决定是否留在缓存；[method load] 成功时调度方一定能拿到 [Resource]。
##
## 本服务只负责编排（缓存命中 → 合并并发 → 读盘 → 入库）：
## 缓存策略在 [AssetCache]，引擎加载在 [ResourceLoaderAdapter]。

#region State
## 已完成的加载。TTL / 水位 / LRU / 闲置扫描由 [AssetCache] 管。
var _cache: AssetCache
## 引擎边界：存在性检查与后台线程加载。
var _loader: ResourceLoaderAdapter

## 尚未结束的加载（同一 path 只打一次 I/O）。
## key: [String] 与 [_cache] 相同的路径
## value: [code]null[/code] = 仍在读盘；[Result] = 已完成，等其它并发 [method load] 取走
var _inflight: Dictionary = {}

## [method release] 发生在 load 完成前：完成后不要写进 [_cache]。
## key: [String] 路径；value: [code]true[/code]
var _released: Dictionary = {}
#endregion

#region Lifecycle
func _init(max_bytes: int = AssetCache.DEFAULT_MAX_BYTES, ttl_msec: int = AssetCache.DEFAULT_TTL_MSEC) -> void:
	_cache = AssetCache.new(max_bytes, ttl_msec)
	_loader = ResourceLoaderAdapter.new()


func initialize() -> Result:
	return Result.ok()


func dispose() -> void:
	_cache.dispose()
	for inflight_path in _inflight:
		_released[inflight_path] = true
#endregion

#region Public API
## 加载 [param path]。必须 [code]await[/code] 才能拿到 [Result]；成功时 [member Result.value] 为 [Resource]。
func load(path: String) -> Result:
	# 1. 空路径直接失败。命中缓存时不要 exists（低端机上反复查 PCK 也贵）。
	if path.is_empty():
		return Result.err("Load failed: path is empty.")

	# 2. 已经在内存里：同步返回，不再 I/O。命中续 TTL；过期则当 miss，下面再读盘。
	var cached: Variant = _cache.read(path)
	if cached != null:
		return Result.ok(cached)

	# 3. 别人正在加载同一份：挂到那次请求上，避免重复读盘。
	if _inflight.has(path):
		return await _join_inflight(path)

	# 4. 自己当发起方：先确认磁盘上有，再占坑读盘。
	if not _loader.exists(path):
		return Result.err("Asset not found: %s." % path)
	_inflight[path] = null
	var fetched: Result = await _loader.load_threaded(path)
	_inflight[path] = fetched
	# 完成前已被 release / clear：调用方仍拿到 Result，只是不占槽。失败也要清标记，避免漏到下一次 load。
	if _released.has(path):
		_released.erase(path)
	elif fetched.is_ok():
		# 估算体积并入库；放不下就不占槽，Result 照还。
		if _cache.store(path, fetched.value as Resource):
			# 让出一帧给等待者期间，禁止把刚入库的这条挤掉。
			_cache.pin(path)

	# 5. 再让出一帧，让步骤 3 里的等待者读到 Result，然后再清坑。
	var tree := _get_tree()
	if tree != null:
		await tree.process_frame
	_cache.unpin(path)
	_inflight.erase(path)
	return fetched


## 释放 [param path] 占用的缓存槽。空路径 / 不在缓存里是空操作。
## 不取消进行中的 [method load]；若正在加载，完成后也不再写回。
func release(path: String) -> void:
	if path.is_empty():
		return
	_cache.drop(path)
	if _inflight.has(path):
		_released[path] = true


## 丢掉全部缓存。正在 [method load] 的完成后也不再写回。
func clear() -> void:
	_cache.clear()
	for inflight_path in _inflight:
		_released[inflight_path] = true
#endregion

#region Internal
func _get_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## 挂到已有的同 path 加载上，避免重复读盘。可 await。
func _join_inflight(path: String) -> Result:
	var tree := _get_tree()
	if tree == null:
		return Result.err("Asset load failed: SceneTree unavailable for %s." % path)
	# 坑还在且值为 null：发起方还在读盘，继续等。
	while _inflight.has(path) and _inflight[path] == null:
		await tree.process_frame
	# 发起方已写入缓存或 Result；优先走缓存。
	var cached: Variant = _cache.read(path)
	if cached != null:
		return Result.ok(cached)
	var done: Result = _inflight.get(path)
	if done == null:
		return Result.err("Asset load failed: %s." % path)
	return done
#endregion
