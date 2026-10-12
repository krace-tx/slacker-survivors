class_name VideoPlayer
extends BaseVideoPlayer

## 视频播放器门面核心实现类。[br]
## 调度底层适配器、驱动状态机、管理纹理输出，并与 [BaseAudioSystem] 进行 BGM 避让联动。

var _audio_system: BaseAudioSystem
var _logger: BaseFrameworkLogger

## 内部真正的 Godot VideoStreamPlayer 节点
var _stream_player: VideoStreamPlayer

## 适配器注册表
var _addon_adapter: AddonVideoAdapter
var _native_adapter: NativeMobileVideoAdapter
var _engine_adapter: EngineVideoAdapter
var _active_adapter: VideoPlayerAdapter

## 当前状态
var _state: int = VideoPlaybackState.IDLE
var _current_file: String = ""
var _current_options: VideoPlayOptions = null

## BGM 避让记录
var _was_bgm_ducked: bool = false
var _previous_bgm_muted: bool = false

## 每次打开/停止视频都会递增，用于取消仍在等待原生回调的过场协程。
var _operation_token: int = 0
var _native_cutscene_waiting: bool = false
var _suppress_native_terminal_signal: bool = false

const DEFAULT_NATIVE_TIMEOUT_SECONDS: float = 300.0


func _init(audio_system: BaseAudioSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_audio_system = audio_system
	_logger = logger
	_addon_adapter = AddonVideoAdapter.new()
	_native_adapter = NativeMobileVideoAdapter.new()
	_engine_adapter = EngineVideoAdapter.new()


func initialize() -> Result:
	_stream_player = VideoStreamPlayer.new()
	_stream_player.name = "VideoStreamPlayerNode"
	_stream_player.expand = true
	add_child(_stream_player)
	
	_stream_player.finished.connect(_on_stream_finished)
	_native_adapter.native_playback_completed.connect(_on_native_playback_completed)
	_native_adapter.native_playback_error.connect(_on_native_playback_error)
	_native_adapter.native_playback_started.connect(_on_native_playback_started)
	_native_adapter.native_playback_paused.connect(_on_native_playback_paused)
	_native_adapter.native_playback_resumed.connect(_on_native_playback_resumed)
	_set_state(VideoPlaybackState.IDLE)
	
	_log_info("Video player initialized. Active Backends -> [GDExtension: %s, Mobile: %s, Engine: %s]" % [
		_addon_adapter.get_adapter_name(), _native_adapter.get_adapter_name(), _engine_adapter.get_adapter_name()
	])
	return Result.ok()


func dispose() -> void:
	_operation_token += 1
	_native_cutscene_waiting = false
	stop()
	if _stream_player != null and is_instance_valid(_stream_player):
		_stream_player.stop()
		_stream_player.stream = null
	_set_state(VideoPlaybackState.IDLE)
	_active_adapter = null
	_current_file = ""
	_current_options = null


func set_audio_system(audio_system: BaseAudioSystem) -> void:
	_audio_system = audio_system


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger


#region BaseVideoPlayer Implementation
func open(file_path: String, options: VideoPlayOptions = null) -> Result:
	var clean_path := file_path.strip_edges()
	if clean_path.is_empty():
		var err_msg := "Video file path cannot be empty."
		_emit_error("Video.EmptyPath", err_msg)
		return Result.err_code("Video.EmptyPath", err_msg)
	
	if not _path_exists_or_uri(clean_path):
		var err_msg := "Video file not found at path: %s" % clean_path
		_emit_error("Video.FileNotFound", err_msg)
		return Result.err_code("Video.FileNotFound", err_msg)
	
	# Opening a new stream invalidates any prior native/cutscene wait.
	_operation_token += 1
	_native_cutscene_waiting = false
	if _active_adapter != null and (_state == VideoPlaybackState.PLAYING or _state == VideoPlaybackState.PAUSED):
		stop()
	_set_state(VideoPlaybackState.OPENING)

	_current_options = options if options != null else VideoPlayOptions.new()

	# Mobile plugins render their own native overlay and cannot provide a
	# VideoStream. Route ordinary open() through the same native contract so the
	# facade state/query methods remain useful on Android/iOS.
	if _native_adapter.is_available() and _native_adapter.can_handle(clean_path):
		_active_adapter = _native_adapter
		_suppress_native_terminal_signal = false
		_current_file = clean_path
		var native_open_res := _native_adapter.open_native(clean_path, _current_options)
		if native_open_res.is_err():
			_emit_error(native_open_res.error_code(), native_open_res.error_message())
			_set_state(VideoPlaybackState.ERROR)
			return native_open_res
		if _current_options.auto_play:
			_set_state(VideoPlaybackState.PLAYING)
		else:
			_set_state(VideoPlaybackState.STOPPED)
		opened.emit(clean_path, _native_adapter.get_duration())
		return Result.ok()
	
	# 智能选择适配器：优先专业插件，次选原生引擎
	var adapter: VideoPlayerAdapter = null
	if _addon_adapter.can_handle(clean_path):
		adapter = _addon_adapter
	elif _engine_adapter.can_handle(clean_path):
		adapter = _engine_adapter
	else:
		var ext := clean_path.get_extension()
		var err_msg: String
		if not _addon_adapter.is_available():
			err_msg = "Format '.%s' requires EIRTeam.FFmpeg plugin in addons/. Please install the plugin to play MP4/MKV." % ext
		else:
			err_msg = "No compatible video adapter found for format '.%s'." % ext
		_emit_error("Video.NoCompatibleAdapter", err_msg)
		_set_state(VideoPlaybackState.ERROR)
		return Result.err_code("Video.NoCompatibleAdapter", err_msg)
	
	_active_adapter = adapter
	var stream_res := _active_adapter.create_stream(clean_path)
	if stream_res.is_err():
		_emit_error(stream_res.error_code(), stream_res.error_message())
		_set_state(VideoPlaybackState.ERROR)
		return stream_res
	
	var stream: VideoStream = stream_res.value as VideoStream
	_stream_player.stream = stream
	_current_file = clean_path
	
	# 应用播放配置项
	_stream_player.loop = _current_options.loop
	_stream_player.volume = clampf(_current_options.volume, 0.0, 1.0)
	_stream_player.bus = _current_options.audio_bus
	_stream_player.speed_scale = _current_options.speed_scale
	
	if _current_options.start_position > 0.0:
		_stream_player.stream_position = _current_options.start_position
	
	_log_info("Opened video '%s' via %s (Duration: %.2fs)" % [
		clean_path.get_file(), _active_adapter.get_adapter_name(), get_duration()
	])
	
	opened.emit(clean_path, get_duration())
	
	if _current_options.auto_play:
		play()
	else:
		_set_state(VideoPlaybackState.STOPPED)
	
	return Result.ok()


func play_cutscene(file_path: String, options: VideoPlayOptions = null) -> Result:
	var opts := options if options != null else VideoPlayOptions.new()
	opts.auto_play = true
	if not _path_exists_or_uri(file_path):
		var missing_message := "Video file not found at path: %s" % file_path
		_emit_error("Video.FileNotFound", missing_message)
		_set_state(VideoPlaybackState.ERROR)
		return Result.err_code("Video.FileNotFound", missing_message)
	
	# 1. 移动端原生硬件加速路由 (Android ExoPlayer / iOS AVPlayer)
	if _native_adapter.is_available() and _native_adapter.can_handle(file_path):
		_log_info("Executing cutscene via native mobile hardware player...")
		if opts.duck_bgm:
			_duck_bgm()

		_operation_token += 1
		var operation_token := _operation_token
		_native_cutscene_waiting = true
		_suppress_native_terminal_signal = false
		_active_adapter = _native_adapter
		_current_file = file_path
		_current_options = opts
		_set_state(VideoPlaybackState.PLAYING)
		
		# 必须在调用原生播放前连接信号。Android/iOS 插件可能在同一帧
		# 发出 started/completed，晚连接会导致过场永久等待。
		var is_done := false
		var err_message := ""
		var on_completed := func():
			is_done = true
		var on_error := func(msg: String):
			err_message = msg
			is_done = true
		
		_native_adapter.native_playback_completed.connect(on_completed, CONNECT_ONE_SHOT)
		_native_adapter.native_playback_error.connect(on_error, CONNECT_ONE_SHOT)
		var native_res := _native_adapter.play_native_cutscene(file_path, opts)
		if native_res.is_err():
			_native_cutscene_waiting = false
			_restore_bgm()
			_set_state(VideoPlaybackState.ERROR)
			return native_res

		var started_at := Time.get_ticks_msec()
		var timeout_seconds := opts.timeout_seconds if opts.timeout_seconds > 0.0 else DEFAULT_NATIVE_TIMEOUT_SECONDS
		var timed_out := false
		while not is_done and operation_token == _operation_token and is_inside_tree():
			await get_tree().process_frame
			if timeout_seconds > 0.0 and (Time.get_ticks_msec() - started_at) / 1000.0 >= timeout_seconds:
				err_message = "Native video playback timed out after %.1f seconds." % timeout_seconds
				timed_out = true
				break

		_native_cutscene_waiting = false
		if _native_adapter.native_playback_completed.is_connected(on_completed):
			_native_adapter.native_playback_completed.disconnect(on_completed)
		if _native_adapter.native_playback_error.is_connected(on_error):
			_native_adapter.native_playback_error.disconnect(on_error)
		if timed_out:
			_suppress_native_terminal_signal = true
			_native_adapter.stop()

		# stop() invalidates operation_token and is treated as a normal user skip.
		if operation_token != _operation_token and err_message.is_empty():
			_restore_bgm()
			return Result.ok()

		_restore_bgm()
		if not err_message.is_empty():
			_emit_error("Video.NativePlaybackFailed", err_message)
			_set_state(VideoPlaybackState.ERROR)
			return Result.err_code("Video.NativePlaybackFailed", err_message)
		
		_set_state(VideoPlaybackState.FINISHED)
		playback_finished.emit()
		return Result.ok()
	
	# 2. 桌面端 (Win/Mac/Linux) 或引擎内置软解全屏渲染管线
	var layer := CanvasLayer.new()
	layer.layer = 95
	
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	layer.add_child(bg)
	
	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.add_child(texture_rect)
	
	var skip_btn: Button = null
	if opts.allow_skip:
		skip_btn = Button.new()
		skip_btn.text = "跳过 >>"
		skip_btn.anchor_left = 1.0
		skip_btn.anchor_top = 0.0
		skip_btn.anchor_right = 1.0
		skip_btn.anchor_bottom = 0.0
		skip_btn.offset_left = -120
		skip_btn.offset_top = 30
		skip_btn.offset_right = -30
		skip_btn.offset_bottom = 70
		if opts.min_watch_seconds > 0.0:
			skip_btn.visible = false
		layer.add_child(skip_btn)
	
	var is_cutscene_done := false
	var on_finish := func():
		is_cutscene_done = true
	
	playback_finished.connect(on_finish, CONNECT_ONE_SHOT)
	add_child(layer)
	var open_res := open(file_path, opts)
	if open_res.is_err():
		if playback_finished.is_connected(on_finish):
			playback_finished.disconnect(on_finish)
		layer.queue_free()
		return open_res
	var operation_token := _operation_token
	
	if skip_btn != null:
		skip_btn.pressed.connect(func():
			stop()
			is_cutscene_done = true
		, CONNECT_ONE_SHOT)
	
	while not is_cutscene_done and operation_token == _operation_token and is_instance_valid(layer):
		if texture_rect.texture == null:
			texture_rect.texture = get_video_texture()
		if skip_btn != null and not skip_btn.visible:
			if get_playback_position() >= opts.min_watch_seconds:
				skip_btn.visible = true
		await get_tree().process_frame
	
	if is_instance_valid(layer):
		layer.queue_free()
	
	return Result.ok()


func play() -> void:
	if _active_adapter == _native_adapter:
		if _current_options != null and _current_options.duck_bgm:
			_duck_bgm()
		_native_adapter.play()
		_set_state(VideoPlaybackState.PLAYING)
		return
	if _stream_player == null or _stream_player.stream == null:
		_log_warn("Cannot play: No video stream loaded.")
		return
	
	# 处理 BGM 自动避让 (Audio Ducking)
	if _current_options != null and _current_options.duck_bgm:
		_duck_bgm()
	
	_stream_player.play()
	_stream_player.paused = false
	_set_state(VideoPlaybackState.PLAYING)


func pause() -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.pause()
		_set_state(VideoPlaybackState.PAUSED)
		return
	if _state != VideoPlaybackState.PLAYING or _stream_player == null:
		return
	_stream_player.paused = true
	_set_state(VideoPlaybackState.PAUSED)


func resume() -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.resume()
		_set_state(VideoPlaybackState.PLAYING)
		return
	if _state != VideoPlaybackState.PAUSED or _stream_player == null:
		return
	_stream_player.paused = false
	_set_state(VideoPlaybackState.PLAYING)


func stop() -> void:
	_operation_token += 1
	_native_cutscene_waiting = false
	if _active_adapter == _native_adapter:
		# A native plugin can deliver its terminal callback after stop() has
		# returned. Suppress that late callback so a user stop/skip never looks
		# like a natural completion to the game layer.
		_suppress_native_terminal_signal = true
		_native_adapter.stop()
		_restore_bgm()
		_set_state(VideoPlaybackState.STOPPED)
		return
	if _state == VideoPlaybackState.IDLE or _stream_player == null:
		return
	_stream_player.stop()
	_restore_bgm()
	_set_state(VideoPlaybackState.STOPPED)


func seek(seconds: float) -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.seek(seconds)
		return
	if _stream_player == null or _stream_player.stream == null:
		return
	_stream_player.stream_position = maxf(0.0, seconds)


func set_volume(linear_volume: float) -> void:
	var clamped := clampf(linear_volume, 0.0, 1.0)
	if _active_adapter == _native_adapter:
		_native_adapter.set_volume(clamped)
		if _current_options != null:
			_current_options.volume = clamped
		return
	if _stream_player != null:
		_stream_player.volume = clamped
	if _current_options != null:
		_current_options.volume = clamped


func get_volume() -> float:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_volume()
	return _stream_player.volume if _stream_player != null else 1.0


func set_looping(loop: bool) -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.set_looping(loop)
		if _current_options != null:
			_current_options.loop = loop
		return
	if _stream_player != null:
		_stream_player.loop = loop
	if _current_options != null:
		_current_options.loop = loop


func is_looping() -> bool:
	if _active_adapter == _native_adapter:
		return _native_adapter.is_looping()
	return _stream_player.loop if _stream_player != null else false


func get_state() -> int:
	return _state


func is_playing() -> bool:
	if _active_adapter == _native_adapter:
		return _state == VideoPlaybackState.PLAYING and _native_adapter.is_playing()
	return _state == VideoPlaybackState.PLAYING and _stream_player != null and _stream_player.is_playing()


func is_paused() -> bool:
	if _active_adapter == _native_adapter:
		return _state == VideoPlaybackState.PAUSED or _native_adapter.is_paused()
	return _state == VideoPlaybackState.PAUSED


func get_duration() -> float:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_duration()
	return _stream_player.get_stream_length() if _stream_player != null else -1.0


func get_playback_position() -> float:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_playback_position()
	return _stream_player.get_stream_position() if _stream_player != null else 0.0


func get_video_texture() -> Texture2D:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_video_texture()
	return _stream_player.get_video_texture() if _stream_player != null else null


func get_current_file() -> String:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_current_file()
	return _current_file


func get_active_adapter_name() -> String:
	return _active_adapter.get_adapter_name() if _active_adapter != null else "None"


func get_backend_type() -> int:
	if _active_adapter == _native_adapter:
		return VideoBackendType.NATIVE_MOBILE
	elif _active_adapter == _addon_adapter:
		return VideoBackendType.ADDON_FFMPEG
	elif _active_adapter == _engine_adapter:
		return VideoBackendType.ENGINE_THEORA
	return VideoBackendType.AUTO
#endregion


#region Internal Helpers & Audio Ducking
func _path_exists_or_uri(file_path: String) -> bool:
	if file_path.begins_with("http://") or file_path.begins_with("https://") or file_path.begins_with("content://"):
		return true
	if FileAccess.file_exists(file_path):
		return true
	# ResourceLoader can see imported/PCK resources which are not ordinary files.
	return file_path.begins_with("res://") and ResourceLoader.exists(file_path)


func _on_native_playback_completed() -> void:
	if _active_adapter != _native_adapter:
		return
	if _suppress_native_terminal_signal:
		_suppress_native_terminal_signal = false
		_restore_bgm()
		return
	_set_state(VideoPlaybackState.FINISHED)
	_restore_bgm()
	if not _native_cutscene_waiting:
		playback_finished.emit()


func _on_native_playback_error(message: String) -> void:
	if _active_adapter != _native_adapter:
		return
	if _suppress_native_terminal_signal:
		_suppress_native_terminal_signal = false
		_restore_bgm()
		return
	if not _native_cutscene_waiting:
		_emit_error("Video.NativePlaybackFailed", message)
	_set_state(VideoPlaybackState.ERROR)
	_restore_bgm()


func _on_native_playback_started() -> void:
	if _active_adapter == _native_adapter:
		_set_state(VideoPlaybackState.PLAYING)


func _on_native_playback_paused() -> void:
	if _active_adapter == _native_adapter:
		_set_state(VideoPlaybackState.PAUSED)


func _on_native_playback_resumed() -> void:
	if _active_adapter == _native_adapter:
		_set_state(VideoPlaybackState.PLAYING)


func _on_stream_finished() -> void:
	if _stream_player.loop:
		_stream_player.play()
		return
	
	_restore_bgm()
	_set_state(VideoPlaybackState.FINISHED)
	playback_finished.emit()


func _duck_bgm() -> void:
	if _was_bgm_ducked or _audio_system == null:
		return
	
	_previous_bgm_muted = _audio_system.is_bus_muted("BGM")
	_audio_system.set_bus_mute("BGM", true)
	_was_bgm_ducked = true


func _restore_bgm() -> void:
	if not _was_bgm_ducked or _audio_system == null:
		return
	
	_audio_system.set_bus_mute("BGM", _previous_bgm_muted)
	_was_bgm_ducked = false


func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	var old_state := _state
	_state = new_state
	state_changed.emit(new_state, old_state)


func _emit_error(code: String, message: String) -> void:
	_log_error("[%s] %s" % [code, message])
	error_occurred.emit(code, message)


func _log_info(msg: String) -> void:
	if _logger != null:
		_logger.info("Video", msg)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, "Video", msg)


func _log_warn(msg: String) -> void:
	if _logger != null:
		_logger.warn("Video", msg)
	else:
		FrameworkLogger.print_raw(LogLevel.WARN, "Video", msg)


func _log_error(msg: String) -> void:
	if _logger != null:
		_logger.error("Video", msg)
	else:
		FrameworkLogger.print_raw(LogLevel.ERROR, "Video", msg)
#endregion
