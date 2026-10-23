class_name VideoPrewarmer
extends RefCounted

## 视频 512KB 文件头（[code]moov[/code]）异步预热调度器与 [VideoStream] 内存预热池（Video Prewarmer）。[br]
##
## 负责在后台线程（[WorkerThreadPool]）流式预读视频前 512KB 数据块至操作系统文件页缓存（OS PageCache），[br]
## 并在桌面端维护固定上限（LRU）的 [VideoStream] 预实例化池，消除起播瞬间的磁盘寻道与资源构造卡顿。

signal prewarm_completed(file_path: String, success: bool)

## 默认预读文件头字节数（512 KB，覆盖 MP4 ftyp + 前置 moov 原子 + 首个关键帧簇）
const PREWARM_CHUNK_BYTES: int = 524288

## 桌面端预实例化 VideoStream 内存缓存池容量上限
const MAX_PREWARMED_STREAMS: int = 4

var _cache_manager: VideoCacheManager
var _mutex: Mutex = Mutex.new()
var _prewarmed_paths: Dictionary = {}
var _prewarming_tasks: Dictionary = {}
var _prewarmed_streams: Dictionary = {}
var _prewarmed_stream_order: Array[String] = []


func _init(cache_manager: VideoCacheManager) -> void:
	_cache_manager = cache_manager


## 启动指定视频路径的异步文件头预热，并可选通过桌面端适配器预创建 [VideoStream]
func schedule(
	clean_path: String,
	is_remote_uri: bool,
	materialize_for_mobile: bool,
	stream_adapter: VideoPlayerAdapter = null
) -> VideoStream:
	if is_remote_uri:
		_mutex.lock()
		_prewarmed_paths[clean_path] = true
		_mutex.unlock()
		prewarm_completed.emit(clean_path, true)
		return null

	_mutex.lock()
	var already_running := _prewarming_tasks.has(clean_path)
	var already_warmed := _prewarmed_paths.has(clean_path)
	_mutex.unlock()

	if not already_running and not already_warmed:
		var task_id := WorkerThreadPool.add_task(
			_run_io_task.bind(clean_path, materialize_for_mobile),
			false,
			"VideoPrewarm:%s" % clean_path.get_file()
		)
		_mutex.lock()
		_prewarming_tasks[clean_path] = task_id
		_mutex.unlock()
	elif already_warmed:
		call_deferred("_emit_completed_deferred", clean_path, true)

	if stream_adapter != null:
		var stream := get_cached_stream(clean_path)
		if stream == null:
			var stream_res := stream_adapter.create_stream(clean_path)
			if stream_res.is_ok():
				stream = stream_res.value as VideoStream
				cache_stream(clean_path, stream)
		return stream

	return null


## 等待指定路径正在后台执行的预热任务完成（防打开文件时发生句柄冲突）
func wait_task(clean_path: String) -> void:
	var task_id: int = -1
	_mutex.lock()
	if _prewarming_tasks.has(clean_path):
		task_id = int(_prewarming_tasks[clean_path])
		_prewarming_tasks.erase(clean_path)
	_mutex.unlock()
	if task_id != -1:
		WorkerThreadPool.wait_for_task_completion(task_id)


## 等待所有后台预热任务完成（用于销毁或全量清理缓存前同步）
func wait_all_tasks() -> void:
	var task_ids: Array[int] = []
	_mutex.lock()
	for key in _prewarming_tasks.keys():
		task_ids.append(int(_prewarming_tasks[key]))
	_prewarming_tasks.clear()
	_mutex.unlock()

	for task_id in task_ids:
		if task_id != -1:
			WorkerThreadPool.wait_for_task_completion(task_id)


## 将预创建的 [VideoStream] 放入固定容量 LRU 内存池
func cache_stream(clean_path: String, stream: VideoStream) -> void:
	if clean_path.is_empty() or stream == null:
		return
	_mutex.lock()
	if _prewarmed_streams.has(clean_path):
		_prewarmed_stream_order.erase(clean_path)
	elif _prewarmed_stream_order.size() >= MAX_PREWARMED_STREAMS:
		var oldest := _prewarmed_stream_order.pop_front() as String
		_prewarmed_streams.erase(oldest)
	_prewarmed_streams[clean_path] = stream
	_prewarmed_stream_order.append(clean_path)
	_mutex.unlock()


## 获取已预创建的 [VideoStream] 实例（未命中时返回 null）
func get_cached_stream(clean_path: String) -> VideoStream:
	_mutex.lock()
	var stream: VideoStream = _prewarmed_streams.get(clean_path, null) as VideoStream
	_mutex.unlock()
	return stream


## 查询指定路径是否已完成文件头预热或存在于内存流缓存池中
func is_prewarmed(clean_path: String) -> bool:
	if clean_path.is_empty():
		return false
	_mutex.lock()
	var warmed := _prewarmed_paths.has(clean_path) or _prewarmed_streams.has(clean_path)
	_mutex.unlock()
	return warmed


## 淘汰指定路径的内存预热记录与缓存流
func evict(clean_path: String) -> void:
	if clean_path.is_empty():
		return
	_mutex.lock()
	_prewarmed_paths.erase(clean_path)
	_prewarmed_streams.erase(clean_path)
	_prewarmed_stream_order.erase(clean_path)
	_mutex.unlock()


## 清空全部内存预热标记与缓存流
func clear_memory_state() -> void:
	_mutex.lock()
	_prewarmed_paths.clear()
	_prewarmed_streams.clear()
	_prewarmed_stream_order.clear()
	_mutex.unlock()


#region Internal Worker Callbacks
func _run_io_task(clean_path: String, materialize_for_mobile: bool) -> void:
	var io_ok := false
	if _cache_manager != null:
		var warm_res := _cache_manager.materialize_and_warm(
			clean_path,
			PREWARM_CHUNK_BYTES,
			materialize_for_mobile
		)
		io_ok = warm_res.is_ok()

	_mutex.lock()
	if io_ok:
		_prewarmed_paths[clean_path] = true
	_mutex.unlock()
	call_deferred("_on_io_task_completed", clean_path, io_ok)


func _on_io_task_completed(clean_path: String, success: bool) -> void:
	var task_id: int = -1
	_mutex.lock()
	if _prewarming_tasks.has(clean_path):
		task_id = int(_prewarming_tasks[clean_path])
		_prewarming_tasks.erase(clean_path)
	_mutex.unlock()

	if task_id != -1:
		WorkerThreadPool.wait_for_task_completion(task_id)

	prewarm_completed.emit(clean_path, success)


func _emit_completed_deferred(clean_path: String, success: bool) -> void:
	prewarm_completed.emit(clean_path, success)
#endregion
