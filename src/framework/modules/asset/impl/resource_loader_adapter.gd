class_name ResourceLoaderAdapter
extends RefCounted

## 引擎边界：封装 [ResourceLoader] 的存在性检查、C++ 引擎缓存直通与后台线程加载（私有实现，仅供 [AssetSystem] 使用）。[br]
## 统一返回携带 [code]Asset.*[/code] 标准错误码的 [Result]，调用方不直接接触 [code]ResourceLoader.THREAD_LOAD_*[/code] 状态机。


## 资源是否存在（res:// 或已导入的 PCK 路径）。
func exists(path: String) -> bool:
	return ResourceLoader.exists(path)


## 若引擎底层 C++ ResourceCache 已持有该资源的活跃引用，直接 O(1) 同步取回（零磁盘 I/O）。
func get_engine_cached(path: String) -> Resource:
	if not path.is_empty() and ResourceLoader.has_cached(path):
		return ResourceLoader.load(path)
	return null


## 仅向引擎底层登记后台多线程加载请求（不挂起等待），供批量并发预加载第一阶段批量点火使用。
func request_threaded(path: String) -> Error:
	if path.is_empty() or ResourceLoader.has_cached(path):
		return OK
	var err := ResourceLoader.load_threaded_request(path)
	return OK if (err == OK or err == ERR_BUSY) else err


## 向引擎登记后台加载并按帧轮询完成状态。必须 [code]await[/code]；成功时 [member Result.value] 为 [Resource]。
func load_threaded(path: String) -> Result:
	# 1. 快路径：若引擎底层 C++ ResourceCache 已持有该资源引用，直接 O(1) 同步取回，免除线程调度与帧等待
	var engine_cached := get_engine_cached(path)
	if engine_cached != null:
		return Result.ok(engine_cached)

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Result.err_code(
			"Asset.SceneTreeUnavailable",
			"Asset load failed: SceneTree unavailable for '%s'." % path
		)

	# 2. 向引擎登记后台线程加载。ERR_BUSY 表示同一路径已在引擎底层加载队列中，直接进入状态轮询
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK and err != ERR_BUSY:
		return Result.err_code(
			"Asset.RequestFailed",
			"Failed to request threaded load for '%s' (err=%d)." % [path, err]
		)

	# 3. 轮询加载状态：若首检即已完成则零帧返回；进行中则按帧让出主线程
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await tree.process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				var res := ResourceLoader.load_threaded_get(path)
				if res == null:
					return Result.err_code(
						"Asset.LoadFailed",
						"Threaded load returned null resource for '%s'." % path
					)
				return Result.ok(res)
			_:
				return Result.err_code(
					"Asset.LoadFailed",
					"Threaded load failed for '%s' (status=%d)." % [path, status]
				)
	return Result.err_code("Asset.LoadFailed", "Asset load aborted: '%s'." % path)
