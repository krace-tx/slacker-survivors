class_name VideoPlayer
extends BaseVideoPlayer

## 视频播放器门面核心实现类（Video Player Facade Orchestrator）。[br]
##
## 遵循单一职责与“UI 无关（UI-Agnostic）”原则，本类仅负责顶层状态机流转、跨平台适配器路由、BGM 正交避让与异步播放协程，[br]
## 绝不在框架层内硬编码创建任何业务 UI 按钮或额外 CanvasLayer。具体底层子域已解耦委托至专属内部组件：[br]
## - [VideoStreamHost]：桌面端离屏透明渲染宿主、前后台帧缓冲锁存、业务 [TextureRect] 弱引用绑定与静音首帧挂起（Standby）；[br]
## - [VideoPrewarmer]：512KB 文件头（[code]moov[/code]）异步预热与 [VideoStream] 内存预热池；[br]
## - [VideoCacheManager]：沙盒视频缓存（[code]user://cache/video[/code]）实体化、128MB LRU 裁剪与“播完即焚”治理。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"video"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"audio", &"logger"]
#endregion

const DEFAULT_NATIVE_TIMEOUT_SECONDS: float = 300.0

#region Injected Dependencies
var _audio_system: BaseAudioSystem
var _logger: BaseFrameworkLogger
#endregion

#region Collaborators & Platform Adapters
var _cache_manager: VideoCacheManager
var _prewarmer: VideoPrewarmer
var _stream_host: VideoStreamHost

var _addon_adapter: AddonVideoAdapter
var _native_adapter: NativeMobileVideoAdapter
var _engine_adapter: EngineVideoAdapter
var _active_adapter: VideoPlayerAdapter
#endregion

#region Playback & Coroutine Guard State
var _state: int = VideoPlaybackState.IDLE
var _current_file: String = ""
var _current_options: VideoPlayOptions = null
var _was_bgm_ducked: bool = false

## 递增操作令牌：每次打开、停止或切换视频时自增，用于快速失效旧有异步过场协程
var _operation_token: int = 0
var _native_cutscene_waiting: bool = false
var _suppress_native_terminal_signal: bool = false
#endregion


#region Lifecycle
func _init(audio_system: BaseAudioSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_audio_system = audio_system
	_logger = logger
	_cache_manager = VideoCacheManager.new()
	_prewarmer = VideoPrewarmer.new(_cache_manager)
	_stream_host = VideoStreamHost.new()
	_addon_adapter = AddonVideoAdapter.new()
	_native_adapter = NativeMobileVideoAdapter.new(_cache_manager)
	_engine_adapter = EngineVideoAdapter.new()


func initialize() -> Result:
	set_process(false)
	_stream_host.setup(self)
	_stream_host.first_frame_ready.connect(func(): first_frame_ready.emit())
	_stream_host.stream_finished.connect(_on_stream_finished)
	_prewarmer.prewarm_completed.connect(func(path: String, ok: bool): prewarm_completed.emit(path, ok))

	_native_adapter.native_playback_completed.connect(_on_native_playback_completed)
	_native_adapter.native_playback_error.connect(_on_native_playback_error)
	_native_adapter.native_playback_started.connect(_on_native_playback_started)
	_native_adapter.native_playback_paused.connect(_on_native_playback_paused)
	_native_adapter.native_playback_resumed.connect(_on_native_playback_resumed)

	_addon_adapter.setup()
	_native_adapter.setup()
	_engine_adapter.setup()

	_set_state(VideoPlaybackState.IDLE)
	_log_info("Video player initialized. Active Backends -> [GDExtension: %s, Mobile: %s, Engine: %s]" % [
		_addon_adapter.get_adapter_name(), _native_adapter.get_adapter_name(), _engine_adapter.get_adapter_name()
	])
	return Result.ok()


func _process(_delta: float) -> void:
	if not _stream_host.poll_frame():
		set_process(false)


func dispose() -> void:
	_operation_token += 1
	_native_cutscene_waiting = false
	set_process(false)
	stop()
	_prewarmer.wait_all_tasks()
	_stream_host.dispose()
	_prewarmer.clear_memory_state()
	_addon_adapter.dispose()
	_native_adapter.dispose()
	_engine_adapter.dispose()

	_set_state(VideoPlaybackState.IDLE)
	_active_adapter = null
	_current_file = ""
	_current_options = null
	if is_inside_tree():
		queue_free()


func set_audio_system(audio_system: BaseAudioSystem) -> void:
	_audio_system = audio_system


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger
#endregion


#region BaseVideoPlayer Public Facade
func prewarm(file_path: String, standby_first_frame: bool = true) -> Result:
	var clean_path := file_path.strip_edges().replace("\\", "/")
	if clean_path.is_empty():
		var err_msg := "Video file path cannot be empty."
		_emit_error(VideoError.EMPTY_PATH, err_msg)
		return Result.err_code(VideoError.EMPTY_PATH, err_msg)

	if not _path_exists_or_uri(clean_path):
		var err_msg := "Video file not found at path: %s" % clean_path
		_emit_error(VideoError.FILE_NOT_FOUND, err_msg)
		return Result.err_code(VideoError.FILE_NOT_FOUND, err_msg)

	var use_mobile := _native_adapter.is_available() and _native_adapter.can_handle(clean_path)
	var stream_adapter: VideoPlayerAdapter = null
	if not use_mobile:
		var resolve_res := _resolve_stream_adapter(clean_path)
		if resolve_res.is_ok():
			stream_adapter = resolve_res.value as VideoPlayerAdapter

	var stream := _prewarmer.schedule(clean_path, _is_remote_uri(clean_path), use_mobile, stream_adapter)
	if standby_first_frame and stream != null and not VideoPlaybackState.is_active(_state):
		if _stream_host.enter_standby(clean_path, stream):
			set_process(true)

	return Result.ok()


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

	_prewarmer.wait_task(clean_path)
	_operation_token += 1
	_native_cutscene_waiting = false

	if _active_adapter != null and (_state == VideoPlaybackState.PLAYING or _state == VideoPlaybackState.PAUSED):
		stop()
	elif _current_file != "" and _current_file != clean_path:
		_cleanup_ephemeral_cache_if_needed()
	_set_state(VideoPlaybackState.OPENING)

	_current_options = options if options != null else VideoPlayOptions.new()

	# 1. 移动端原生硬件加速路由（Android ExoPlayer / iOS AVPlayer）
	if _native_adapter.is_available() and _native_adapter.can_handle(clean_path):
		_stream_host.stop()
		_active_adapter = _native_adapter
		_suppress_native_terminal_signal = false
		_current_file = clean_path
		var native_open_res := _native_adapter.open_native(clean_path, _current_options)
		if native_open_res.is_err():
			_emit_error(native_open_res.error_code(), native_open_res.error_message())
			_set_state(VideoPlaybackState.ERROR)
			return native_open_res

		_set_state(VideoPlaybackState.PLAYING if _current_options.auto_play else VideoPlaybackState.STOPPED)
		opened.emit(clean_path, _native_adapter.get_duration())
		return Result.ok()

	# 2. 桌面端与软解路由：智能择优匹配适配器并复用 Standby 首帧或预热流
	var resolve_res := _resolve_stream_adapter(clean_path)
	if resolve_res.is_err():
		_stream_host.cancel_standby(true)
		_emit_error(resolve_res.error_code(), resolve_res.error_message())
		_set_state(VideoPlaybackState.ERROR)
		return resolve_res

	_active_adapter = resolve_res.value as VideoPlayerAdapter
	var reuse_standby := _stream_host.is_standby_for(clean_path)
	if reuse_standby:
		_stream_host.consume_standby()
	else:
		var stream := _prewarmer.get_cached_stream(clean_path)
		if stream == null:
			var stream_res := _active_adapter.create_stream(clean_path)
			if stream_res.is_err():
				_emit_error(stream_res.error_code(), stream_res.error_message())
				_set_state(VideoPlaybackState.ERROR)
				return stream_res
			stream = stream_res.value as VideoStream
		_stream_host.mount_stream(stream)

	_current_file = clean_path
	_stream_host.apply_options(_current_options)

	_log_info("Opened video '%s' via %s (Duration: %.2fs, StandbyHit: %s)" % [
		clean_path.get_file(), _active_adapter.get_adapter_name(), get_duration(), str(reuse_standby)
	])
	opened.emit(clean_path, get_duration())

	if _current_options.auto_play:
		play()
	else:
		_stream_host.pause()
		_set_state(VideoPlaybackState.STOPPED)

	return Result.ok()


func play_cutscene(
	file_path: String,
	options: VideoPlayOptions = null,
	target: TextureRect = null
) -> Result:
	var clean_path := file_path.strip_edges().replace("\\", "/")
	var opts := options if options != null else VideoPlayOptions.new()
	opts.auto_play = true

	if not _path_exists_or_uri(clean_path):
		var missing_message := "Video file not found at path: %s" % clean_path
		_emit_error(VideoError.FILE_NOT_FOUND, missing_message)
		_set_state(VideoPlaybackState.ERROR)
		return Result.err_code(VideoError.FILE_NOT_FOUND, missing_message)

	if _native_adapter.is_available() and _native_adapter.can_handle(clean_path):
		return await _play_cutscene_native(clean_path, opts)
	return await _play_cutscene_desktop(clean_path, opts, target)


func bind_display(target: TextureRect, hide_until_first_frame: bool = true) -> void:
	_stream_host.bind_display(target, hide_until_first_frame)


func unbind_display(target: TextureRect = null) -> void:
	_stream_host.unbind_display(target)


func play() -> void:
	if _active_adapter == _native_adapter:
		if _current_options != null and _current_options.duck_bgm:
			_duck_bgm()
		_native_adapter.play()
		_set_state(VideoPlaybackState.PLAYING)
		return

	if _current_options != null and _current_options.duck_bgm:
		_duck_bgm()

	var needs_poll := _stream_host.play()
	_set_state(VideoPlaybackState.PLAYING)
	set_process(needs_poll)


func pause() -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.pause()
		_set_state(VideoPlaybackState.PAUSED)
		return

	if _state != VideoPlaybackState.PLAYING:
		return
	_stream_host.pause()
	_set_state(VideoPlaybackState.PAUSED)


func resume() -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.resume()
		_set_state(VideoPlaybackState.PLAYING)
		return

	if _state != VideoPlaybackState.PAUSED:
		return
	var needs_poll := _stream_host.resume()
	_set_state(VideoPlaybackState.PLAYING)
	if needs_poll:
		set_process(true)


func stop() -> void:
	_operation_token += 1
	_native_cutscene_waiting = false
	set_process(false)

	if _active_adapter == _native_adapter:
		_suppress_native_terminal_signal = true
		_native_adapter.stop()
		_cleanup_ephemeral_cache_if_needed()
		_restore_bgm()
		_set_state(VideoPlaybackState.STOPPED)
		return

	if _state == VideoPlaybackState.IDLE:
		_stream_host.stop()
		return
	_stream_host.stop()
	_cleanup_ephemeral_cache_if_needed()
	_restore_bgm()
	_set_state(VideoPlaybackState.STOPPED)


func seek(seconds: float) -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.seek(seconds)
	else:
		_stream_host.seek(seconds)


func set_volume(linear_volume: float) -> void:
	var clamped := clampf(linear_volume, 0.0, 1.0)
	if _active_adapter == _native_adapter:
		_native_adapter.set_volume(clamped)
	else:
		_stream_host.set_volume(clamped)
	if _current_options != null:
		_current_options.volume = clamped


func get_volume() -> float:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_volume()
	return _stream_host.get_volume()


func set_looping(loop: bool) -> void:
	if _active_adapter == _native_adapter:
		_native_adapter.set_looping(loop)
	else:
		_stream_host.set_looping(loop)
	if _current_options != null:
		_current_options.loop = loop


func is_looping() -> bool:
	if _active_adapter == _native_adapter:
		return _native_adapter.is_looping()
	return _stream_host.is_looping()


func get_state() -> int:
	return _state


func is_playing() -> bool:
	if _active_adapter == _native_adapter:
		return _state == VideoPlaybackState.PLAYING and _native_adapter.is_playing()
	return _state == VideoPlaybackState.PLAYING and _stream_host.is_playing()


func is_paused() -> bool:
	if _active_adapter == _native_adapter:
		return _state == VideoPlaybackState.PAUSED or _native_adapter.is_paused()
	return _state == VideoPlaybackState.PAUSED


func get_duration() -> float:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_duration()
	return _stream_host.get_duration()


func get_playback_position() -> float:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_playback_position()
	return _stream_host.get_playback_position()


func get_video_texture() -> Texture2D:
	if _active_adapter == _native_adapter:
		return _native_adapter.get_video_texture()
	var allow_expose := (
		_state == VideoPlaybackState.PLAYING
		or _state == VideoPlaybackState.PAUSED
		or _state == VideoPlaybackState.FINISHED
	)
	return _stream_host.get_latched_texture(allow_expose)


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


func is_first_frame_ready() -> bool:
	if _active_adapter == _native_adapter:
		return _native_adapter.is_playing()
	return _stream_host.is_first_frame_ready()


func is_prewarmed(file_path: String) -> bool:
	var clean_path := file_path.strip_edges().replace("\\", "/")
	return _prewarmer.is_prewarmed(clean_path) or _stream_host.is_standby_for(clean_path)


func clear_cache() -> Result:
	_prewarmer.wait_all_tasks()
	if not VideoPlaybackState.is_active(_state):
		_stream_host.cancel_standby(true)
	_prewarmer.clear_memory_state()
	return _cache_manager.clear_cache(VideoPlaybackState.is_active(_state))


func get_cache_size_bytes() -> int:
	return _cache_manager.get_cache_size_bytes()
#endregion


#region Cutscene Execution Pipelines
func _play_cutscene_native(clean_path: String, opts: VideoPlayOptions) -> Result:
	_log_info("Executing cutscene via native mobile hardware player...")
	_prewarmer.wait_task(clean_path)
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

	var native_state := {"is_done": false, "err_message": ""}
	var on_completed := func() -> void:
		native_state["is_done"] = true
	var on_error := func(msg: String) -> void:
		native_state["err_message"] = msg
		native_state["is_done"] = true

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

	while not bool(native_state["is_done"]) and operation_token == _operation_token and is_inside_tree():
		await get_tree().process_frame
		if timeout_seconds > 0.0 and (Time.get_ticks_msec() - started_at) / 1000.0 >= timeout_seconds:
			native_state["err_message"] = "Native video playback timed out after %.1f seconds." % timeout_seconds
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

	var final_err_msg := str(native_state["err_message"])
	if operation_token != _operation_token and final_err_msg.is_empty():
		_restore_bgm()
		return Result.ok()

	_restore_bgm()
	if not final_err_msg.is_empty():
		_emit_error(VideoError.NATIVE_PLAYBACK_FAILED, final_err_msg)
		_set_state(VideoPlaybackState.ERROR)
		return Result.err_code(VideoError.NATIVE_PLAYBACK_FAILED, final_err_msg)

	_set_state(VideoPlaybackState.FINISHED)
	playback_finished.emit()
	return Result.ok()


func _play_cutscene_desktop(
	file_path: String,
	opts: VideoPlayOptions,
	target: TextureRect = null
) -> Result:
	if target != null and is_instance_valid(target):
		_stream_host.bind_display(target, opts.wait_first_frame)

	var cutscene_state := {"is_done": false}
	var on_finish := func() -> void:
		cutscene_state["is_done"] = true

	playback_finished.connect(on_finish, CONNECT_ONE_SHOT)

	var open_res := open(file_path, opts)
	if open_res.is_err():
		if playback_finished.is_connected(on_finish):
			playback_finished.disconnect(on_finish)
		if target != null:
			_stream_host.unbind_display(target)
		return open_res

	var operation_token := _operation_token
	var started_msec := Time.get_ticks_msec()
	var gate_timeout := maxf(0.0, opts.first_frame_timeout_seconds)
	var gate_fallback_triggered := not opts.wait_first_frame
	if gate_fallback_triggered:
		_stream_host.reveal_bound_display()

	while not bool(cutscene_state["is_done"]) and operation_token == _operation_token and is_inside_tree():
		if not gate_fallback_triggered and not _stream_host.is_first_frame_ready():
			var elapsed_sec := (Time.get_ticks_msec() - started_msec) / 1000.0
			if elapsed_sec >= gate_timeout:
				gate_fallback_triggered = true
				_stream_host.reveal_bound_display()
		await get_tree().process_frame

	if playback_finished.is_connected(on_finish):
		playback_finished.disconnect(on_finish)
	if target != null:
		_stream_host.unbind_display(target)

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


func _cleanup_ephemeral_cache_if_needed() -> void:
	if _current_options == null or not _current_options.ephemeral_cache or _current_file.is_empty():
		return
	var target_path := _current_file
	_prewarmer.evict(target_path)
	_cache_manager.evict_cached_file(target_path, false)


func _is_remote_uri(file_path: String) -> bool:
	return file_path.begins_with("http://") or file_path.begins_with("https://") or file_path.begins_with("content://")


func _path_exists_or_uri(file_path: String) -> bool:
	if _is_remote_uri(file_path):
		return true
	return FileUtils.resource_or_file_exists(file_path)


func _on_native_playback_completed() -> void:
	if _active_adapter != _native_adapter:
		return
	if _suppress_native_terminal_signal:
		_suppress_native_terminal_signal = false
		_restore_bgm()
		return
	_cleanup_ephemeral_cache_if_needed()
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
	_cleanup_ephemeral_cache_if_needed()
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
	set_process(false)
	_cleanup_ephemeral_cache_if_needed()
	_restore_bgm()
	_set_state(VideoPlaybackState.FINISHED)
	playback_finished.emit()


func _duck_bgm() -> void:
	if _was_bgm_ducked or _audio_system == null:
		return
	_was_bgm_ducked = true
	_audio_system.duck_bgm(0.0, _get_duck_fade_seconds())


func _restore_bgm() -> void:
	if not _was_bgm_ducked or _audio_system == null:
		return
	_was_bgm_ducked = false
	_audio_system.unduck_bgm(_get_duck_fade_seconds())


func _get_duck_fade_seconds() -> float:
	if _current_options == null:
		return 0.5
	return maxf(0.0, _current_options.duck_fade_seconds)


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
