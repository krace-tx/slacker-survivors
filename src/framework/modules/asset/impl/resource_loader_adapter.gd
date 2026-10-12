class_name ResourceLoaderAdapter
extends RefCounted

## 引擎边界：封装 [ResourceLoader] 的存在性检查与后台线程加载（私有实现，仅供 [AssetService] 使用）。[br]
## 统一返回 [Result]，调用方不直接接触 [code]ResourceLoader.THREAD_LOAD_*[/code] 状态机。

## 资源是否存在（res:// 或已导入的 PCK 路径）。
func exists(path: String) -> bool:
	return ResourceLoader.exists(path)


## 向引擎登记后台加载并每帧 poll。必须 [code]await[/code]；成功时 [member Result.value] 为 [Resource]。
func load_threaded(path: String) -> Result:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Result.err("Asset load failed: SceneTree unavailable for %s." % path)

	# 向引擎登记后台加载。ERR_BUSY = 同 path 已在引擎队列里，直接去 poll。
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK and err != ERR_BUSY:
		return Result.err("Asset load failed: %s." % path)

	# 每帧问一次进度：进行中让出主线程；完成取 Resource；其余当失败。
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await tree.process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				var res := ResourceLoader.load_threaded_get(path)
				if res == null:
					return Result.err("Asset load failed: %s." % path)
				return Result.ok(res)
			_:
				return Result.err("Asset load failed: %s." % path)
	return Result.err("Asset load failed: %s." % path)
