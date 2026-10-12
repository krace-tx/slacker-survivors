class_name VideoPlayerTestScene
extends BaseScene

## 沉浸式全屏视频播放器场景。
##
## 提供如电影/原生流媒体播放器般的整页无边框视频体验：
## - 纯净全屏视频画面渲染与自适应比例贴合
## - 悬浮返回按钮（左上角）
## - 极简白线控制栏（快退、播放/暂停圆形切换、快进、跳过）
## - 屏幕交互式触控（点击暂停/播放、闲置自动淡隐控制栏）
## - 底部流线型微型时间进度条与时间码

const DEFAULT_MP4_PATH := "res://src/test/video/assets/big_buck_bunny_1080p_30sec.mp4"
const DEFAULT_OGV_PATH := "res://src/test/video/assets/sample.ogv"
const HIDE_TIMEOUT_SECONDS := 3.2

const ICON_PLAY: Texture2D = preload("res://src/test/video/assets/icons/play_circle.svg")
const ICON_PAUSE: Texture2D = preload("res://src/test/video/assets/icons/pause_circle.svg")

@onready var _screen: TextureRect = %VideoScreen
@onready var _touch_overlay: Control = %TouchOverlay
@onready var _overlay_container: Control = %OverlayContainer
@onready var _back_button: BaseTextureButton = %BackButton
@onready var _notice_pill: PanelContainer = %NoticePill
@onready var _notice_label: Label = %NoticeLabel

@onready var _current_time_label: Label = %CurrentTimeLabel
@onready var _total_time_label: Label = %TotalTimeLabel
@onready var _progress_slider: HSlider = %ProgressSlider

@onready var _rewind_button: BaseTextureButton = %RewindButton
@onready var _play_pause_button: BaseTextureButton = %PlayPauseButton
@onready var _forward_button: BaseTextureButton = %ForwardButton
@onready var _skip_button: BaseTextureButton = %SkipButton

var _video_ready := false
var _initialization_started := false
var _signals_connected := false
var _updating_progress := false
var _controls_visible := true
var _hide_countdown := HIDE_TIMEOUT_SECONDS
var _fade_tween: Tween = null
var _notice_tween: Tween = null


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_play_pause_button.pressed.connect(_on_play_pause_pressed)
	_rewind_button.pressed.connect(_on_rewind_pressed)
	_forward_button.pressed.connect(_on_forward_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_progress_slider.value_changed.connect(_on_progress_changed)
	_touch_overlay.gui_input.connect(_on_touch_overlay_input)
	
	_set_playing_visual_state(false)
	call_deferred("_initialize_video_service")


func _on_enter(_params: Dictionary = {}) -> void:
	if not _initialization_started:
		_initialize_video_service()


func _on_exit() -> void:
	_disconnect_video_signals()
	if _video_ready and App != null and App.video != null:
		App.video.stop()
	_video_ready = false


func _on_pause() -> void:
	if _video_ready and App != null and App.video != null and App.video.is_playing():
		App.video.pause()
		_set_playing_visual_state(false)
		_show_controls()


func _on_resume(_params: Dictionary = {}) -> void:
	_show_controls()


func _process(delta: float) -> void:
	if not _video_ready or App == null or App.video == null:
		return
	
	# 更新当前视频画面纹理
	var texture := App.video.get_video_texture()
	if texture != null and _screen.texture != texture:
		_screen.texture = texture
	
	# 同步进度条与时间码
	var duration := App.video.get_duration()
	var position := App.video.get_playback_position()
	
	_updating_progress = true
	_progress_slider.max_value = maxf(1.0, duration)
	_progress_slider.value = clampf(position, 0.0, _progress_slider.max_value)
	_updating_progress = false
	
	_current_time_label.text = _format_time(position)
	_total_time_label.text = _format_time(duration)
	
	# 播放中控制栏自动淡隐倒计时
	if App.video.is_playing() and _controls_visible:
		_hide_countdown -= delta
		if _hide_countdown <= 0.0:
			_hide_controls()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		_show_controls()
		_reset_hide_timer()


func _initialize_video_service() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	
	var boot_result: Result = await App.bootstrap()
	if boot_result.is_err():
		_show_notice("Framework bootstrap failed: %s" % boot_result.error_message())
		return
	if App.video == null:
		_show_notice("App.video service is unavailable.")
		return
	
	_video_ready = true
	_connect_video_signals()
	
	# 启动时自动尝试装载并播放视频
	var options := VideoPlayOptions.new()
	options.auto_play = true
	options.loop = false
	options.volume = 1.0
	options.duck_bgm = true
	
	var target_path := _get_preferred_video_path()
	var open_res := App.video.open(target_path, options)
	if open_res.is_err() and target_path != DEFAULT_OGV_PATH and FileAccess.file_exists(DEFAULT_OGV_PATH):
		target_path = DEFAULT_OGV_PATH
		open_res = App.video.open(target_path, options)

	if open_res.is_err():
		var is_mac := OS.get_name() == "macOS"
		if is_mac and App.video.get_backend_type() == VideoBackendType.ENGINE_THEORA:
			_show_notice("⚠️ macOS 模式仅内置 Theora 解码器。播放 .mp4 需安装 EIRTeam.FFmpeg 插件。")
		else:
			_show_notice("打开视频失败: [%s] %s" % [open_res.error_code(), open_res.error_message()])
		_set_playing_visual_state(false)
		_show_controls()
	else:
		_set_playing_visual_state(true)
		_reset_hide_timer()


func _get_preferred_video_path() -> String:
	if App != null and App.video != null:
		var backend := App.video.get_backend_type()
		if backend == VideoBackendType.ENGINE_THEORA:
			if FileAccess.file_exists(DEFAULT_OGV_PATH):
				return DEFAULT_OGV_PATH
	if FileAccess.file_exists(DEFAULT_MP4_PATH):
		return DEFAULT_MP4_PATH
	if FileAccess.file_exists(DEFAULT_OGV_PATH):
		return DEFAULT_OGV_PATH
	return DEFAULT_OGV_PATH


func _connect_video_signals() -> void:
	if _signals_connected or App == null or App.video == null:
		return
	App.video.opened.connect(_on_video_opened)
	App.video.state_changed.connect(_on_video_state_changed)
	App.video.playback_finished.connect(_on_video_finished)
	App.video.error_occurred.connect(_on_video_error)
	_signals_connected = true


func _disconnect_video_signals() -> void:
	if not _signals_connected or App == null or App.video == null:
		return
	if App.video.opened.is_connected(_on_video_opened):
		App.video.opened.disconnect(_on_video_opened)
	if App.video.state_changed.is_connected(_on_video_state_changed):
		App.video.state_changed.disconnect(_on_video_state_changed)
	if App.video.playback_finished.is_connected(_on_video_finished):
		App.video.playback_finished.disconnect(_on_video_finished)
	if App.video.error_occurred.is_connected(_on_video_error):
		App.video.error_occurred.disconnect(_on_video_error)
	_signals_connected = false


func _on_play_pause_pressed() -> void:
	if not _video_ready or App == null or App.video == null:
		return
	
	if App.video.is_playing():
		App.video.pause()
		_set_playing_visual_state(false)
		_show_controls()
	else:
		if App.video.is_paused():
			App.video.resume()
		else:
			var state := App.video.get_state()
			if state == VideoPlaybackState.IDLE or state == VideoPlaybackState.ERROR:
				var opts := VideoPlayOptions.new()
				opts.auto_play = true
				var target_path := _get_preferred_video_path()
				var res := App.video.open(target_path, opts)
				if res.is_err() and target_path != DEFAULT_OGV_PATH and FileAccess.file_exists(DEFAULT_OGV_PATH):
					target_path = DEFAULT_OGV_PATH
					res = App.video.open(target_path, opts)
				if res.is_err():
					_show_notice("无法播放: %s" % res.error_message())
					return
			else:
				App.video.play()
		_set_playing_visual_state(true)
		_reset_hide_timer()


func _on_rewind_pressed() -> void:
	_seek_relative(-5.0)
	_reset_hide_timer()


func _on_forward_pressed() -> void:
	_seek_relative(5.0)
	_reset_hide_timer()


func _on_skip_pressed() -> void:
	if not _video_ready or App == null or App.video == null:
		return
	App.video.stop()
	_set_playing_visual_state(false)
	_show_controls()


func _on_back_pressed() -> void:
	if _video_ready and App != null and App.video != null:
		App.video.stop()
	
	if App != null and App.scene != null:
		var pop_res: Result = await App.scene.pop()
		if pop_res.is_err():
			App.scene.replace("res://src/game/features/lobby/main_menu/lobby_scene.tscn")
	else:
		get_tree().quit()


func _on_touch_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _controls_visible:
			_show_controls()
			_reset_hide_timer()
		else:
			# 点击屏幕空白区域切换 播放 / 暂停
			_on_play_pause_pressed()


func _seek_relative(offset: float) -> void:
	if not _video_ready or App == null or App.video == null:
		return
	var target := maxf(0.0, App.video.get_playback_position() + offset)
	var duration := App.video.get_duration()
	if duration > 0.0:
		target = minf(target, duration)
	App.video.seek(target)


func _on_progress_changed(value: float) -> void:
	if _updating_progress or not _video_ready or App == null or App.video == null:
		return
	App.video.seek(value)
	_reset_hide_timer()


func _set_playing_visual_state(is_playing: bool) -> void:
	if _play_pause_button == null:
		return
	if is_playing:
		_play_pause_button.texture_normal = ICON_PAUSE
	else:
		_play_pause_button.texture_normal = ICON_PLAY


func _show_controls() -> void:
	_controls_visible = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_overlay_container, "modulate:a", 1.0, 0.2) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)


func _hide_controls() -> void:
	if not _video_ready or App == null or App.video == null or not App.video.is_playing():
		return
	_controls_visible = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_overlay_container, "modulate:a", 0.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_IN)


func _reset_hide_timer() -> void:
	_hide_countdown = HIDE_TIMEOUT_SECONDS


func _show_notice(message: String) -> void:
	if _notice_pill == null or _notice_label == null:
		return
	_notice_label.text = message
	_notice_pill.visible = true
	_notice_pill.modulate.a = 0.0
	
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_property(_notice_pill, "modulate:a", 1.0, 0.3)
	_notice_tween.tween_interval(4.5)
	_notice_tween.tween_property(_notice_pill, "modulate:a", 0.0, 0.5)
	_notice_tween.tween_callback(func(): _notice_pill.visible = false)


func _on_video_opened(_path: String, _duration: float) -> void:
	_set_playing_visual_state(App.video.is_playing())


func _on_video_state_changed(new_state: int, _old_state: int) -> void:
	match new_state:
		VideoPlaybackState.PLAYING:
			_set_playing_visual_state(true)
			_reset_hide_timer()
		VideoPlaybackState.PAUSED, VideoPlaybackState.STOPPED, VideoPlaybackState.FINISHED, VideoPlaybackState.IDLE, VideoPlaybackState.ERROR:
			_set_playing_visual_state(false)
			_show_controls()


func _on_video_finished() -> void:
	_set_playing_visual_state(false)
	_show_controls()


func _on_video_error(error_code: String, message: String) -> void:
	_set_playing_visual_state(false)
	_show_notice("播放器错误 [%s]: %s" % [error_code, message])
	_show_controls()


func _format_time(seconds: float) -> String:
	if seconds < 0.0 or is_nan(seconds):
		return "00:00"
	var total_secs := int(seconds)
	var mins := total_secs / 60
	var secs := total_secs % 60
	return "%02d:%02d" % [mins, secs]
