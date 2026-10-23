class_name VideoCacheManager
extends RefCounted

## 沙盒视频缓存安全与生命周期治理器（Sandbox Video Cache Governance Manager）。[br]
##
## 负责管理封包内视频资源（[code]res://[/code]）在沙盒可读写卷（[code]user://cache/video[/code]）中的按需流式实体化、[br]
## 512KB 文件头（[code]moov[/code]）OS PageCache 预热、128MB LRU 容量预算淘汰、临时残余文件自愈与“播完即焚”安全策略。

## 移动端与外部插件封包视频实体化沙盒缓存目录（统一收敛于二级缓存域 user://cache/video）
const VIDEO_CACHE_DIR: String = FileUtils.USER_VIDEO_CACHE_DIR

## 默认沙盒视频缓存容量预算上限（128 MB）
const DEFAULT_MAX_CACHE_BYTES: int = 134217728

## 默认文件头（MP4 ftyp + moov + 首关键帧簇）预热读取字节数（512 KB）
const DEFAULT_PREWARM_HEAD_BYTES: int = 524288

var _cache_mutex: Mutex = Mutex.new()
var _cache_access_ticks: Dictionary = {}
var _active_cache_virtual_path: String = ""


## 初始化缓存治理器：清理异常中断遗留的临时文件并执行初始容量预算裁剪
func setup() -> void:
	purge_transient_artifacts()
	prune_cache(DEFAULT_MAX_CACHE_BYTES)


## 销毁缓存治理器：释放活跃引用并执行容量预算裁剪
func dispose() -> void:
	_cache_mutex.lock()
	_active_cache_virtual_path = ""
	_cache_mutex.unlock()
	prune_cache(DEFAULT_MAX_CACHE_BYTES)


## 将虚拟路径解析为原生播放器可直接读取的物理路径，并登记活跃缓存与 LRU 时间戳
func resolve_playable_path(file_path: String) -> String:
	var clean_path := file_path.strip_edges().replace("\\", "/")
	var mat_res := FileUtils.materialize_res_file(clean_path, VIDEO_CACHE_DIR)
	if mat_res.is_ok():
		if clean_path.begins_with("res://"):
			var cache_virtual := FileUtils.get_materialized_cache_path(clean_path, VIDEO_CACHE_DIR)
			_cache_mutex.lock()
			_active_cache_virtual_path = cache_virtual
			_cache_access_ticks[cache_virtual] = Time.get_ticks_msec()
			_cache_mutex.unlock()
			prune_cache(DEFAULT_MAX_CACHE_BYTES, true)
		return str(mat_res.value)
	return clean_path


## 后台线程安全调用：按需实体化封包视频并流式预读文件前 [param head_bytes] 字节至 OS PageCache
func materialize_and_warm(
	file_path: String,
	head_bytes: int = DEFAULT_PREWARM_HEAD_BYTES,
	materialize_res: bool = false
) -> Result:
	var clean_path := file_path.strip_edges().replace("\\", "/")
	if clean_path.is_empty():
		return Result.err_code(VideoError.EMPTY_PATH, "Video file path cannot be empty.")

	var target_path := clean_path
	if materialize_res and clean_path.begins_with("res://"):
		var mat_res := FileUtils.materialize_res_file(clean_path, VIDEO_CACHE_DIR)
		if mat_res.is_err():
			return mat_res
		target_path = str(mat_res.value)
		var cache_virtual := FileUtils.get_materialized_cache_path(clean_path, VIDEO_CACHE_DIR)
		touch_cache_entry(cache_virtual)

	var warm_res := FileUtils.warm_file_head(target_path, head_bytes)
	if warm_res.is_err():
		return warm_res
	return Result.ok(target_path)


## 刷新指定沙盒缓存虚拟路径的最近访问时间戳（线程安全）
func touch_cache_entry(cache_virtual: String) -> void:
	if cache_virtual.is_empty():
		return
	_cache_mutex.lock()
	_cache_access_ticks[cache_virtual] = Time.get_ticks_msec()
	_cache_mutex.unlock()


## 清除当前活跃缓存路径占用标记（当视频停止或自然结束时调用）
func release_active_path() -> void:
	_cache_mutex.lock()
	_active_cache_virtual_path = ""
	_cache_mutex.unlock()


## 按原始资源路径或缓存路径淘汰对应的沙盒实体化明文缓存文件
func evict_cached_file(file_path: String, is_playing_active: bool = false) -> Result:
	var clean_path := file_path.strip_edges().replace("\\", "/")
	if clean_path.is_empty():
		return Result.ok()
	var cache_virtual := (
		clean_path
		if clean_path.begins_with(VIDEO_CACHE_DIR)
		else FileUtils.get_materialized_cache_path(clean_path, VIDEO_CACHE_DIR)
	)
	if cache_virtual.is_empty():
		return Result.ok()

	_cache_mutex.lock()
	_cache_access_ticks.erase(cache_virtual)
	if _active_cache_virtual_path == cache_virtual and not is_playing_active:
		_active_cache_virtual_path = ""
	_cache_mutex.unlock()
	return FileUtils.remove_file(cache_virtual)


## 按最大容量预算（LRU 最近最少使用策略）裁剪沙盒视频缓存目录
func prune_cache(max_bytes: int = DEFAULT_MAX_CACHE_BYTES, preserve_active: bool = true) -> Result:
	purge_transient_artifacts()
	if not FileUtils.dir_exists(VIDEO_CACHE_DIR):
		return Result.ok(0)

	var file_paths := FileUtils.list_file_paths(VIDEO_CACHE_DIR, true, false)
	if file_paths.is_empty():
		return Result.ok(0)

	var budget := maxi(0, max_bytes)
	var total_bytes := 0
	var candidates: Array[Dictionary] = []

	_cache_mutex.lock()
	var active_virtual := _active_cache_virtual_path if preserve_active else ""
	for path in file_paths:
		var size := maxi(0, FileUtils.get_file_size(path))
		total_bytes += size
		if not active_virtual.is_empty() and path == active_virtual:
			continue
		var tick: int = int(_cache_access_ticks.get(path, FileUtils.get_modified_time(path) * 1000))
		candidates.append({
			"path": path,
			"size": size,
			"tick": tick
		})
	_cache_mutex.unlock()

	if total_bytes <= budget:
		return Result.ok(total_bytes)

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["tick"]) < int(b["tick"])
	)

	for entry in candidates:
		if total_bytes <= budget:
			break
		var entry_path: String = str(entry["path"])
		var entry_size: int = int(entry["size"])
		var rm_res := FileUtils.remove_file(entry_path)
		if rm_res.is_ok():
			total_bytes = maxi(0, total_bytes - entry_size)
			_cache_mutex.lock()
			_cache_access_ticks.erase(entry_path)
			_cache_mutex.unlock()

	return Result.ok(total_bytes)


## 清理沙盒视频缓存目录下的所有缓存文件（可选保留当前正在播放的活动文件）
func clear_cache(preserve_active: bool = true) -> Result:
	purge_transient_artifacts()
	if not FileUtils.dir_exists(VIDEO_CACHE_DIR):
		return Result.ok()

	var file_paths := FileUtils.list_file_paths(VIDEO_CACHE_DIR, true, false)
	_cache_mutex.lock()
	var active_virtual := _active_cache_virtual_path if preserve_active else ""
	_cache_mutex.unlock()

	for path in file_paths:
		if not active_virtual.is_empty() and path == active_virtual:
			continue
		var rm_res := FileUtils.remove_file(path)
		if rm_res.is_err():
			return rm_res
		_cache_mutex.lock()
		_cache_access_ticks.erase(path)
		_cache_mutex.unlock()

	return Result.ok()


## 获取当前沙盒视频缓存目录占用的总字节数
func get_cache_size_bytes() -> int:
	if not FileUtils.dir_exists(VIDEO_CACHE_DIR):
		return 0
	var total := 0
	for path in FileUtils.list_file_paths(VIDEO_CACHE_DIR, true, false):
		var sz := FileUtils.get_file_size(path)
		if sz > 0:
			total += sz
	return total


## 清理因异常断电或强退遗留在缓存目录中的 `.tmp` 与 `.swap_bak` 碎片文件
func purge_transient_artifacts() -> void:
	if not FileUtils.dir_exists(VIDEO_CACHE_DIR):
		return
	for path in FileUtils.list_file_paths(VIDEO_CACHE_DIR, false, false):
		if path.ends_with(FileUtils.TMP_SUFFIX) or path.ends_with(FileUtils.SWAP_SUFFIX):
			FileUtils.remove_file(path)
