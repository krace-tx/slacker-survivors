class_name NativeMobileVideoAdapter
extends VideoPlayerAdapter

## 移动端原生硬件加速播放适配器（Android ExoPlayer / iOS AVPlayer）。[br]
##
## 针对移动端（Android / iOS）进行专属适配优化：[br]
## - Android：通过 Godot Android Plugin (.gdap) 桥接 Android 原生 ExoPlayer / MediaPlayer；[br]
## - iOS：通过 Godot iOS Plugin (.gdip) 桥接 Apple 原生 AVPlayerViewController；[br]
## - 特点：零 CPU 软解消耗、全硬件 VPU 芯片级解码、零发热、不增加任何额外包体。[br]
## - 兼容性：广泛兼容社区主流开源插件单例（GodotVideoPlayer, godot-exoplayer, AVPlayer 等）。

const KNOWN_ANDROID_SINGLETONS: Array[StringName] = [
	&"GodotVideoPlayer",
	&"GodotExoPlayer",
	&"ExoPlayer",
	&"VideoPlayer",
]

const KNOWN_IOS_SINGLETONS: Array[StringName] = [
	&"AVPlayer",
	&"GodotVideoPlayer",
	&"GodotAVPlayer",
	&"NativeVideoPlayer",
]

## 支持的移动端标准硬件解码视频格式
const SUPPORTED_EXTENSIONS: Array[String] = [
	"mp4", "m4v", "mov", "webm", "3gp", "ts", "mkv"
]

signal native_playback_completed()
signal native_playback_error(message: String)
signal native_playback_started()
signal native_playback_paused()
signal native_playback_resumed()

var _current_file: String = ""
var _volume: float = 1.0
var _loop: bool = false
var _speed_scale: float = 1.0
var _playing: bool = false
var _paused: bool = false


func is_available() -> bool:
	return _get_active_singleton() != null


func get_adapter_name() -> String:
	var os := OS.get_name()
	var singleton_name := _get_active_singleton_name()
	if singleton_name != &"":
		if os == "Android":
			return "Android Native Player (%s / ExoPlayer)" % String(singleton_name)
		elif os == "iOS":
			return "iOS Native Player (%s / AVPlayer)" % String(singleton_name)
		return "Mobile Native Player (%s)" % String(singleton_name)
	return "Mobile Native Player (Inactive on %s)" % os


func can_handle(file_path: String) -> bool:
	if not is_available():
		return false
	var ext := file_path.get_extension().to_lower()
	return ext in SUPPORTED_EXTENSIONS


## 原生播放器无法通过 VideoStreamPlayer 暴露资源，因此把原路径保留在
## 适配器中，并只在插件明确需要本地路径时转换可访问的文件。
func get_current_file() -> String:
	return _current_file


func get_volume() -> float:
	return _volume


func is_looping() -> bool:
	return _loop


func is_playing() -> bool:
	var singleton := _get_active_singleton()
	var value: Variant = _query_singleton(singleton, [&"isPlaying", &"is_playing"])
	if value != null:
		_playing = bool(value)
	return _playing and not _paused


func is_paused() -> bool:
	return _paused


func get_duration() -> float:
	var value: Variant = _query_singleton(_get_active_singleton(), [&"getDuration", &"get_duration"])
	return float(value) if value != null else -1.0


func get_playback_position() -> float:
	var value: Variant = _query_singleton(_get_active_singleton(), [&"getCurrentPosition", &"get_current_position", &"getPlaybackPosition"])
	return float(value) if value != null else 0.0


func get_video_texture() -> Texture2D:
	var singleton := _get_active_singleton()
	if singleton == null:
		return null
	var value: Variant = _query_singleton(singleton, [&"getVideoTexture", &"get_video_texture"])
	return value as Texture2D if value is Texture2D else null


## 唤起移动端原生全屏硬件播放器播放视频流
func play_native_cutscene(file_path: String, options: VideoPlayOptions = null) -> Result:
	var singleton: Object = _get_active_singleton()
	if singleton == null:
		return Result.err_code(
			"Video.NativePluginUnavailable",
			"Native mobile video plugin singleton is not loaded on %s." % OS.get_name()
		)
	
	_current_file = file_path
	_playing = false
	_paused = false
	var real_path := _resolve_path(file_path)
	_apply_options(singleton, options)
	
	# 连接原生插件的完成与异常信号 (支持多种信号名变体)
	_connect_signal_if_exists(singleton, "video_completed", _on_native_completed)
	_connect_signal_if_exists(singleton, "playback_completed", _on_native_completed)
	_connect_signal_if_exists(singleton, "completed", _on_native_completed)
	_connect_persistent_signal_if_exists(singleton, "video_started", _on_native_started)
	_connect_persistent_signal_if_exists(singleton, "playback_started", _on_native_started)
	_connect_persistent_signal_if_exists(singleton, "started", _on_native_started)
	_connect_persistent_signal_if_exists(singleton, "video_paused", _on_native_paused)
	_connect_persistent_signal_if_exists(singleton, "paused", _on_native_paused)
	_connect_persistent_signal_if_exists(singleton, "video_resumed", _on_native_resumed)
	_connect_persistent_signal_if_exists(singleton, "resumed", _on_native_resumed)
	
	_connect_signal_if_exists(singleton, "video_error", _on_native_error)
	_connect_signal_if_exists(singleton, "playback_error", _on_native_error)
	_connect_signal_if_exists(singleton, "error", _on_native_error)
	
	# 调用原生播放方法 (支持 playVideo / playFullScreen / play / play_video)
	var allow_skip := true
	if options != null:
		allow_skip = options.allow_skip
	
	if singleton.has_method("playVideo"):
		singleton.call("playVideo", real_path, allow_skip)
	elif singleton.has_method("play_video"):
		singleton.call("play_video", real_path, allow_skip)
	elif singleton.has_method("play"):
		singleton.call("play", real_path)
	elif singleton.has_method("play_fullscreen"):
		singleton.call("play_fullscreen", real_path)
	else:
		return Result.err_code("Video.MethodNotFound", "Native singleton has no recognized play method.")

	if options != null and options.start_position > 0.0:
		# Both ExoPlayer and AVPlayer accept a pending seek before the first
		# frame is rendered; the platform backend applies it once prepared.
		seek(options.start_position)
	_playing = true
	return Result.ok()


## 打开普通视频。多数移动插件只有全屏播放 API，因此在缺少 prepare/open
## 方法时先启动再立即暂停，仍然保持 BaseVideoPlayer 的 open 语义。
func open_native(file_path: String, options: VideoPlayOptions = null) -> Result:
	var result := play_native_cutscene(file_path, options)
	if result.is_err():
		return result
	if options != null and not options.auto_play:
		pause()
	return result


func play() -> void:
	var singleton := _get_active_singleton()
	if singleton == null:
		return
	if singleton.has_method("resumeVideo"):
		singleton.call("resumeVideo")
	elif singleton.has_method("resume"):
		singleton.call("resume")
	elif singleton.has_method("play"):
		singleton.call("play")
	_playing = true
	_paused = false


## 控制方法：暂停
func pause() -> void:
	var singleton: Object = _get_active_singleton()
	if singleton == null:
		return
	if singleton.has_method("pauseVideo"):
		singleton.call("pauseVideo")
	elif singleton.has_method("pause"):
		singleton.call("pause")
	_playing = false
	_paused = true


## 控制方法：恢复
func resume() -> void:
	var singleton: Object = _get_active_singleton()
	if singleton == null:
		return
	if singleton.has_method("resumeVideo"):
		singleton.call("resumeVideo")
	elif singleton.has_method("resume"):
		singleton.call("resume")
	elif singleton.has_method("play"):
		singleton.call("play")
	_playing = true
	_paused = false


## 控制方法：跳转
func seek(seconds: float) -> void:
	var singleton: Object = _get_active_singleton()
	if singleton == null:
		return
	if singleton.has_method("seekTo"):
		singleton.call("seekTo", seconds)
	elif singleton.has_method("seek"):
		singleton.call("seek", seconds)


func set_volume(linear_volume: float) -> void:
	_volume = clampf(linear_volume, 0.0, 1.0)
	_call_singleton(_get_active_singleton(), [&"setVolume", &"set_volume"], _volume)


func set_looping(loop: bool) -> void:
	_loop = loop
	_call_singleton(_get_active_singleton(), [&"setLooping", &"set_looping", &"setRepeat"], loop)


func set_speed_scale(speed_scale: float) -> void:
	_speed_scale = maxf(0.01, speed_scale)
	_call_singleton(_get_active_singleton(), [&"setPlaybackSpeed", &"set_playback_speed", &"setSpeed"], _speed_scale)


## 控制方法：停止
func stop() -> void:
	var singleton: Object = _get_active_singleton()
	if singleton == null:
		return
	if singleton.has_method("stopVideo"):
		singleton.call("stopVideo")
	elif singleton.has_method("stop"):
		singleton.call("stop")
	_playing = false
	_paused = false


func _get_active_singleton_name() -> StringName:
	var os := OS.get_name()
	if os == "Android":
		for s_name in KNOWN_ANDROID_SINGLETONS:
			if Engine.has_singleton(s_name):
				return s_name
	elif os == "iOS":
		for s_name in KNOWN_IOS_SINGLETONS:
			if Engine.has_singleton(s_name):
				return s_name
	return &""


func _get_active_singleton() -> Object:
	var s_name := _get_active_singleton_name()
	if s_name != &"":
		return Engine.get_singleton(s_name)
	return null


func _connect_signal_if_exists(target: Object, sig_name: String, callable: Callable) -> void:
	if target.has_signal(sig_name):
		if not target.is_connected(sig_name, callable):
			target.connect(sig_name, callable, CONNECT_ONE_SHOT)


func _connect_persistent_signal_if_exists(target: Object, sig_name: String, callable: Callable) -> void:
	if target != null and target.has_signal(sig_name) and not target.is_connected(sig_name, callable):
		target.connect(sig_name, callable)


func _resolve_path(file_path: String) -> String:
	if not file_path.begins_with("res://"):
		return file_path
	var global_path := ProjectSettings.globalize_path(file_path)
	# Exported PCK resources do not necessarily have a filesystem path. Keep the
	# original URI so plugins that understand Godot resources can resolve it.
	return global_path if FileAccess.file_exists(global_path) else file_path


func _apply_options(singleton: Object, options: VideoPlayOptions) -> void:
	if options == null:
		return
	_volume = clampf(options.volume, 0.0, 1.0)
	_loop = options.loop
	_speed_scale = maxf(0.01, options.speed_scale)
	_call_singleton(singleton, [&"setVolume", &"set_volume"], _volume)
	_call_singleton(singleton, [&"setLooping", &"set_looping", &"setRepeat"], _loop)
	_call_singleton(singleton, [&"setPlaybackSpeed", &"set_playback_speed", &"setSpeed"], _speed_scale)


func _call_singleton(target: Object, method_names: Array[StringName], argument: Variant) -> bool:
	if target == null:
		return false
	for method_name in method_names:
		if target.has_method(method_name):
			target.call(method_name, argument)
			return true
	return false


func _query_singleton(target: Object, method_names: Array[StringName]) -> Variant:
	if target == null:
		return null
	for method_name in method_names:
		if target.has_method(method_name):
			return target.call(method_name)
	return null


func _on_native_completed() -> void:
	_playing = false
	_paused = false
	native_playback_completed.emit()


func _on_native_error(error_msg: Variant) -> void:
	_playing = false
	_paused = false
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
