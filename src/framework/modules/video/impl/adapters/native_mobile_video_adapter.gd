class_name NativeMobileVideoAdapter
extends VideoPlayerAdapter

## 移动端原生硬件加速播放适配器（Android ExoPlayer / iOS AVPlayer）。[br]
##
## 直接桥接工程内置打包的两大官方原生硬件插件：[br]
## - Android：基于 Media3 ExoPlayer 的 [code]GodotVideoPlayer[/code] 插件单例；[br]
## - iOS：基于 AVFoundation / AVKit 的 [code]AVPlayer[/code] 插件单例；[br]
## - 沙盒缓存与实体化生命周期委托给 [VideoCacheManager] 统一治理。

## 工程标准化原生单例名称
const SINGLETON_ANDROID: StringName = &"GodotVideoPlayer"
const SINGLETON_IOS: StringName = &"AVPlayer"

## 兼容常量转发：移动端封包视频实体化沙盒缓存目录与默认容量上限（128 MB）
const VIDEO_CACHE_DIR: String = VideoCacheManager.VIDEO_CACHE_DIR
const DEFAULT_MAX_CACHE_BYTES: int = VideoCacheManager.DEFAULT_MAX_CACHE_BYTES
const DEFAULT_PREWARM_HEAD_BYTES: int = VideoCacheManager.DEFAULT_PREWARM_HEAD_BYTES

## 支持的移动端标准硬件解码视频格式
const SUPPORTED_EXTENSIONS: Array[String] = [
	"mp4", "m4v", "mov", "webm", "3gp", "ts", "mkv"
]

signal native_playback_completed()
signal native_playback_error(message: String)
signal native_playback_started()
signal native_playback_paused()
signal native_playback_resumed()

var _cache_manager: VideoCacheManager
var _current_file: String = ""
var _ephemeral_current: bool = false
var _volume: float = 1.0
var _loop: bool = false
var _speed_scale: float = 1.0
var _playing: bool = false
var _paused: bool = false


func _init(cache_manager: VideoCacheManager = null) -> void:
	_cache_manager = cache_manager if cache_manager != null else VideoCacheManager.new()


func setup() -> void:
	_cache_manager.setup()


func dispose() -> void:
	stop()
	_cache_manager.dispose()


func is_mobile_native() -> bool:
	return true


func supports_texture_output() -> bool:
	return false


func is_available() -> bool:
	return _get_active_singleton() != null


func get_adapter_name() -> String:
	var os := OS.get_name()
	if os == "Android":
		return "Android Native Player (ExoPlayer)"
	elif os == "iOS":
		return "iOS Native Player (AVPlayer)"
	return "Mobile Native Player (Inactive on %s)" % os


func can_handle(file_path: String) -> bool:
	if not is_available():
		return false
	var ext := file_path.get_extension().to_lower()
	return ext in SUPPORTED_EXTENSIONS


func get_current_file() -> String:
	return _current_file


func get_volume() -> float:
	return _volume


func is_looping() -> bool:
	return _loop


func is_playing() -> bool:
	var singleton := _get_active_singleton()
	if singleton != null and singleton.has_method("isPlaying"):
		_playing = bool(singleton.call("isPlaying"))
	return _playing and not _paused


func is_paused() -> bool:
	return _paused


func get_duration() -> float:
	var singleton := _get_active_singleton()
	if singleton != null and singleton.has_method("getDuration"):
		return float(singleton.call("getDuration"))
	return -1.0


func get_playback_position() -> float:
	var singleton := _get_active_singleton()
	if singleton != null and singleton.has_method("getCurrentPosition"):
		return float(singleton.call("getCurrentPosition"))
	return 0.0


func get_video_texture() -> Texture2D:
	return null


## 唤起移动端原生全屏硬件播放器播放视频
func play_native_cutscene(file_path: String, options: VideoPlayOptions = null) -> Result:
	var singleton: Object = _get_active_singleton()
	if singleton == null:
		return Result.err_code(
			VideoError.NATIVE_PLUGIN_UNAVAILABLE,
			"Native mobile video plugin singleton is not loaded on %s." % OS.get_name()
		)

	_cleanup_ephemeral_if_needed()
	_current_file = file_path
	_ephemeral_current = options.ephemeral_cache if options != null else false
	_playing = false
	_paused = false
	var real_path := _cache_manager.resolve_playable_path(file_path)
	_apply_options(singleton, options)

	_connect_signal(singleton, "video_completed", _on_native_completed)
	_connect_signal(singleton, "video_error", _on_native_error)
	_connect_persistent_signal(singleton, "video_started", _on_native_started)
	_connect_persistent_signal(singleton, "video_paused", _on_native_paused)
	_connect_persistent_signal(singleton, "video_resumed", _on_native_resumed)

	var allow_skip := options.allow_skip if options != null else true
	if not singleton.has_method("playVideo"):
		return Result.err_code(VideoError.METHOD_NOT_FOUND, "Native singleton missing 'playVideo' method.")

	singleton.call("playVideo", real_path, allow_skip)

	if options != null and options.start_position > 0.0:
		seek(options.start_position)

	_playing = true
	return Result.ok()


## 打开普通视频。移动插件通过全屏硬件层呈现，在非 auto_play 时唤起后立即挂起
func open_native(file_path: String, options: VideoPlayOptions = null) -> Result:
	var result := play_native_cutscene(file_path, options)
	if result.is_err():
		return result
	if options != null and not options.auto_play:
		pause()
		_playing = false
		_paused = false
	return result


func play() -> void:
	var singleton := _get_active_singleton()
	if singleton != null and singleton.has_method("resumeVideo"):
		singleton.call("resumeVideo")
	_playing = true
	_paused = false


func pause() -> void:
	var singleton: Object = _get_active_singleton()
	if singleton != null and singleton.has_method("pauseVideo"):
		singleton.call("pauseVideo")
	_playing = false
	_paused = true


func resume() -> void:
	var singleton: Object = _get_active_singleton()
	if singleton != null and singleton.has_method("resumeVideo"):
		singleton.call("resumeVideo")
	_playing = true
	_paused = false


func seek(seconds: float) -> void:
	var singleton: Object = _get_active_singleton()
	if singleton != null and singleton.has_method("seekTo"):
		singleton.call("seekTo", maxf(0.0, seconds))


func set_volume(linear_volume: float) -> void:
	_volume = clampf(linear_volume, 0.0, 1.0)
	var singleton := _get_active_singleton()
	if singleton != null and singleton.has_method("setVolume"):
		singleton.call("setVolume", _volume)


func set_looping(loop: bool) -> void:
	_loop = loop
	var singleton := _get_active_singleton()
	if singleton != null and singleton.has_method("setLooping"):
		singleton.call("setLooping", _loop)


func set_speed_scale(speed_scale: float) -> void:
	_speed_scale = maxf(0.01, speed_scale)
	var singleton := _get_active_singleton()
	if singleton != null and singleton.has_method("setPlaybackSpeed"):
		singleton.call("setPlaybackSpeed", _speed_scale)


func stop() -> void:
	var singleton: Object = _get_active_singleton()
	if singleton != null and singleton.has_method("stopVideo"):
		singleton.call("stopVideo")
	_playing = false
	_paused = false
	_cleanup_ephemeral_if_needed()


#region Cache Governance Forwarding
func materialize_and_warm(file_path: String, head_bytes: int = DEFAULT_PREWARM_HEAD_BYTES) -> Result:
	return _cache_manager.materialize_and_warm(file_path, head_bytes, true)


func evict_cached_file(file_path: String) -> Result:
	return _cache_manager.evict_cached_file(file_path, _playing)


func prune_cache(max_bytes: int = DEFAULT_MAX_CACHE_BYTES) -> Result:
	return _cache_manager.prune_cache(max_bytes, _playing)


func clear_cache(preserve_active: bool = true) -> Result:
	return _cache_manager.clear_cache(preserve_active and _playing)


func get_cache_size_bytes() -> int:
	return _cache_manager.get_cache_size_bytes()
#endregion


#region Internal Helpers
func _get_active_singleton() -> Object:
	var os := OS.get_name()
	if os == "Android" and Engine.has_singleton(SINGLETON_ANDROID):
		return Engine.get_singleton(SINGLETON_ANDROID)
	elif os == "iOS" and Engine.has_singleton(SINGLETON_IOS):
		return Engine.get_singleton(SINGLETON_IOS)
	return null


func _connect_signal(target: Object, sig_name: String, callable: Callable) -> void:
	if target.has_signal(sig_name) and not target.is_connected(sig_name, callable):
		target.connect(sig_name, callable, CONNECT_ONE_SHOT)


func _connect_persistent_signal(target: Object, sig_name: String, callable: Callable) -> void:
	if target != null and target.has_signal(sig_name) and not target.is_connected(sig_name, callable):
		target.connect(sig_name, callable)


func _cleanup_ephemeral_if_needed() -> void:
	if not _ephemeral_current:
		_cache_manager.release_active_path()
		return
	_ephemeral_current = false
	if not _current_file.is_empty():
		_cache_manager.evict_cached_file(_current_file, false)
	_cache_manager.release_active_path()


func _apply_options(singleton: Object, options: VideoPlayOptions) -> void:
	if options == null:
		return
	_volume = clampf(options.volume, 0.0, 1.0)
	_loop = options.loop
	_speed_scale = maxf(0.01, options.speed_scale)
	if singleton.has_method("setVolume"):
		singleton.call("setVolume", _volume)
	if singleton.has_method("setLooping"):
		singleton.call("setLooping", _loop)
	if singleton.has_method("setPlaybackSpeed"):
		singleton.call("setPlaybackSpeed", _speed_scale)


func _on_native_completed() -> void:
	_playing = false
	_paused = false
	_cleanup_ephemeral_if_needed()
	native_playback_completed.emit()


func _on_native_error(error_msg: Variant) -> void:
	_playing = false
	_paused = false
	_cleanup_ephemeral_if_needed()
	native_playback_error.emit(str(error_msg))


func _on_native_started() -> void:
	_playing = true
	_paused = false
	native_playback_started.emit()


func _on_native_paused() -> void:
	_playing = false
	_paused = true
	native_playback_paused.emit()


func _on_native_resumed() -> void:
	_playing = true
	_paused = false
	native_playback_resumed.emit()
#endregion
