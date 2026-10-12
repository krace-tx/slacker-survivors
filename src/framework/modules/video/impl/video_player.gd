class_name VideoPlayer
extends BaseVideoPlayer

## 视频播放器门面核心实现类（Video Player Facade Core Implementation）。[br]
##
## 本类统一装配与调度全平台解码适配器、驱动状态机、管理纹理输出，
## 并与 [BaseAudioSystem] 进行 BGM 避让联动，向业务层暴露强类型无痛的统一视频操作体验。

#region Injected Dependencies
var _audio_system: BaseAudioSystem
var _logger: BaseFrameworkLogger
#endregion

#region Internal Nodes & Adapters
## 引擎底层渲染节点（用于桌面端及原生软解的 VideoStreamPlayer）
var _stream_player: VideoStreamPlayer

## 各平台具体解码适配器
var _addon_adapter: AddonVideoAdapter
var _native_adapter: NativeMobileVideoAdapter
var _engine_adapter: EngineVideoAdapter
var _active_adapter: VideoPlayerAdapter
#endregion

#region Playback State Variables
var _state: int = VideoPlaybackState.IDLE
var _current_file: String = ""
var _current_options: VideoPlayOptions = null

## 递增操作令牌：每次打开、停止或切换视频时自增，用于快速失效旧有异步过场协程
var _operation_token: int = 0
var _native_cutscene_waiting: bool = false
var _suppress_native_terminal_signal: bool = false
#endregion

#region Audio Ducking State
var _was_bgm_ducked: bool = false
var _previous_bgm_muted: bool = false
var _previous_bgm_volume: float = 1.0
var _duck_tween: Tween = null
#endregion

const DEFAULT_NATIVE_TIMEOUT_SECONDS: float = 300.0


#region Lifecycle & Subsystem Contract
func _init(audio_system: BaseAudioSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_audio_system = audio_system
	_logger = logger
	_addon_adapter = AddonVideoAdapter.new()
	_native_adapter = NativeMobileVideoAdapter.new()
	_engine_adapter = EngineVideoAdapter.new()


func initialize() -> Result:
	# 1. 构建并挂载内部 VideoStreamPlayer
	_stream_player = VideoStreamPlayer.new()
	_stream_player.name = "VideoStreamPlayerNode"
	_stream_player.expand = true
	add_child(_stream_player)
	
	# 2. 监听桌面流播放完毕信号
	_stream_player.finished.connect(_on_stream_finished)
	
	# 3. 监听移动端原生播放器信号
	_native_adapter.native_playback_completed.connect(_on_native_playback_completed)
	_native_adapter.native_playback_error.connect(_on_native_playback_error)
	_native_adapter.native_playback_started.connect(_on_native_playback_started)
	_native_adapter.native_playback_paused.connect(_on_native_playback_paused)
	_native_adapter.native_playback_resumed.connect(_on_native_playback_resumed)
	
	# 4. 初始化子适配器
	_addon_adapter.setup()
	_native_adapter.setup()
	_engine_adapter.setup()
	
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
	
	_addon_adapter.dispose()
	_native_adapter.dispose()
	_engine_adapter.dispose()
	
	_set_state(VideoPlaybackState.IDLE)
	_active_adapter = null
	_current_file = ""
	_current_options = null
	_cancel_duck_tween()


func set_audio_system(audio_system: BaseAudioSystem) -> void:
	_audio_system = audio_system


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger
#endregion


#region BaseVideoPlayer Public Facade
func open(file_path: String, options: VideoPlayOptions = null) -> Result:
	var clean_path := file_path.strip_edges().replace("\\", "/")
	if clean_path.is_empty():
		var err_msg := "Video file path cannot be empty."
		_emit_error(VideoError.EMPTY_PATH, err_msg)
		return Result.err_code(VideoError.EMPTY_PATH, err_msg)
	
	if not _path_exists_or_uri(clean_path):
		var err_msg := "Video file not found at path: %s" % clean_path
		_emit_error(VideoError.FILE_NOT_FOUND, err_msg)
		return Result.err_code(VideoError.FILE_NOT_FOUND, err_msg)
	
	# 切换新视频流：递增操作令牌以使旧过场等待协程安全退出
	_operation_token += 1
	_native_cutscene_waiting = false
	if _active_adapter != null and (_state == VideoPlaybackState.PLAYING or _state == VideoPlaybackState.PAUSED):
		stop()
	_set_state(VideoPlaybackState.OPENING)

	_current_options = options if options != null else VideoPlayOptions.new()

	# 1. 移动端原生硬件加速路由（Android ExoPlayer / iOS AVPlayer）
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
	
	# 2. 桌面端与软解路由：智能择优匹配适配器
	var resolve_res := _resolve_stream_adapter(clean_path)
	if resolve_res.is_err():
		_emit_error(resolve_res.error_code(), resolve_res.error_message())
		_set_state(VideoPlaybackState.ERROR)
		return resolve_res
	
	_active_adapter = resolve_res.value as VideoPlayerAdapter
	var stream_res := _active_adapter.create_stream(clean_path)
	if stream_res.is_err():
		_emit_error(stream_res.error_code(), stream_res.error_message())
		_set_state(VideoPlaybackState.ERROR)
		return stream_res
	
	var stream: VideoStream = stream_res.value as VideoStream
	_stream_player.stream = stream
	_current_file = clean_path
	
	# 3. 装配播放参数
	_apply_stream_options(_current_options)
	
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
	var clean_path := file_path.strip_edges().replace("\\", "/")
	var opts := options if options != null else VideoPlayOptions.new()
	opts.auto_play = true
	
	if not _path_exists_or_uri(clean_path):
		var missing_message := "Video file not found at path: %s" % clean_path
		_emit_error(VideoError.FILE_NOT_FOUND, missing_message)
		_set_state(VideoPlaybackState.ERROR)
		return Result.err_code(VideoError.FILE_NOT_FOUND, missing_message)
	
	# 1. 移动端原生硬件加速过场路由
	if _native_adapter.is_available() and _native_adapter.can_handle(clean_path):
		return await _play_cutscene_native(clean_path, opts)
	
	# 2. 桌面端 (Win/Mac/Linux) 与引擎软解过场渲染路由（使用独立 VideoCutsceneOverlay）
	return await _play_cutscene_desktop(clean_path, opts)


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
	elif _stream_player != null:
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
	elif _stream_player != null:
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


#region Cutscene Execution Pipelines
func _play_cutscene_native(clean_path: String, opts: VideoPlayOptions) -> Result:
	_log_info("Executing cutscene via native mobile hardware player...")
	if opts.duck_bgm:
		_duck_bgm()

	_operation_token += 1
	var operation_token := _operation_token
	_native_cutscene_waiting = true
	_suppress_native_terminal_signal = false
	_active_adapter = _native_adapter
	_current_file = clean_path
	_current_options = opts
	_set_state(VideoPlaybackState.PLAYING)
	
	var is_done := false
	var err_message := ""
	var on_completed := func():
		is_done = true
	var on_error := func(msg: String):
		err_message = msg
		is_done = true
	
	_native_adapter.native_playback_completed.connect(on_completed, CONNECT_ONE_SHOT)
	_native_adapter.native_playback_error.connect(on_error, CONNECT_ONE_SHOT)
	var native_res := _native_adapter.play_native_cutscene(clean_path, opts)
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

	if operation_token != _operation_token and err_message.is_empty():
		_restore_bgm()
		return Result.ok()

	_restore_bgm()
	if not err_message.is_empty():
		_emit_error(VideoError.NATIVE_PLAYBACK_FAILED, err_message)
		_set_state(VideoPlaybackState.ERROR)
		return Result.err_code(VideoError.NATIVE_PLAYBACK_FAILED, err_message)
	
	_set_state(VideoPlaybackState.FINISHED)
	playback_finished.emit()
	return Result.ok()


func _play_cutscene_desktop(file_path: String, opts: VideoPlayOptions) -> Result:
	# 构造专用的过场遮罩 UI 组件
	var overlay := VideoCutsceneOverlay.new()
	overlay.setup(opts)
	add_child(overlay)
	
	var is_cutscene_done := false
	var on_finish := func():
		is_cutscene_done = true
	
	playback_finished.connect(on_finish, CONNECT_ONE_SHOT)
	overlay.skip_requested.connect(func():
		stop()
		is_cutscene_done = true
	, CONNECT_ONE_SHOT)
	
	var open_res := open(file_path, opts)
	if open_res.is_err():
		if playback_finished.is_connected(on_finish):
			playback_finished.disconnect(on_finish)
		overlay.close()
		return open_res
	
	var operation_token := _operation_token
	
	while not is_cutscene_done and operation_token == _operation_token and is_instance_valid(overlay):
		overlay.update_texture(get_video_texture())
		overlay.update_progress(get_playback_position())
		await get_tree().process_frame
	
	if is_instance_valid(overlay):
		overlay.close()
	
	return Result.ok()
#endregion


#region Internal Helpers & Signal Handlers
func _resolve_stream_adapter(clean_path: String) -> Result:
	if _addon_adapter.can_handle(clean_path):
		return Result.ok(_addon_adapter)
	elif _engine_adapter.can_handle(clean_path):
		return Result.ok(_engine_adapter)
	
	var ext := clean_path.get_extension()
	return Result.err_code(
		VideoError.NO_COMPATIBLE_ADAPTER,
		"No compatible video adapter found for format '.%s'." % ext
	)


func _apply_stream_options(options: VideoPlayOptions) -> void:
	if options == null or _stream_player == null:
		return
	_stream_player.loop = options.loop
	_stream_player.volume = clampf(options.volume, 0.0, 1.0)
	_stream_player.bus = options.audio_bus
	_stream_player.speed_scale = options.speed_scale
	
	if options.start_position > 0.0:
		_stream_player.stream_position = options.start_position


func _path_exists_or_uri(file_path: String) -> bool:
	if file_path.begins_with("http://") or file_path.begins_with("https://") or file_path.begins_with("content://"):
		return true
	if FileAccess.file_exists(file_path):
		return true
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
		_emit_error(VideoError.NATIVE_PLAYBACK_FAILED, message)
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
	_previous_bgm_volume = _audio_system.get_bus_volume("BGM")
	_was_bgm_ducked = true
	if _previous_bgm_muted:
		return
	
	var fade_seconds := _get_duck_fade_seconds()
	_audio_system.set_bus_mute("BGM", false)
	if fade_seconds <= 0.0 or not is_inside_tree():
		_audio_system.set_bus_volume("BGM", 0.0)
		return
	
	_cancel_duck_tween()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_bgm_volume, _previous_bgm_volume, 0.0, fade_seconds)


func _restore_bgm() -> void:
	if not _was_bgm_ducked or _audio_system == null:
		return

	_cancel_duck_tween()
	if _previous_bgm_muted:
		_audio_system.set_bus_mute("BGM", true)
	else:
		_audio_system.set_bus_mute("BGM", false)
		var fade_seconds := _get_duck_fade_seconds()
		if fade_seconds <= 0.0 or not is_inside_tree():
			_audio_system.set_bus_volume("BGM", _previous_bgm_volume)
		else:
			_duck_tween = create_tween()
			_duck_tween.tween_method(_set_bgm_volume, _audio_system.get_bus_volume("BGM"), _previous_bgm_volume, fade_seconds)
	_was_bgm_ducked = false


func _get_duck_fade_seconds() -> float:
	if _current_options == null:
		return 0.5
	return maxf(0.0, _current_options.duck_fade_seconds)


func _set_bgm_volume(volume: float) -> void:
	if _audio_system != null:
		_audio_system.set_bus_volume("BGM", volume)


func _cancel_duck_tween() -> void:
	if _duck_tween != null and is_instance_valid(_duck_tween):
		_duck_tween.kill()
	_duck_tween = null


func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	
	if not VideoPlaybackState.can_transition(_state, new_state):
		_log_warn("Illegal state transition from %s to %s ignored." % [
			VideoPlaybackState.to_string_name(_state),
			VideoPlaybackState.to_string_name(new_state)
		])
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
