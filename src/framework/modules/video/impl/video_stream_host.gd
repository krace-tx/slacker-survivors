class_name VideoStreamHost
extends RefCounted

## 桌面端与引擎软解视频流离屏宿主及前后台帧缓冲隔离器（Video Stream Offscreen Host & Frame Buffer Latch）。[br]
##
## 核心职责：[br]
## - [b]离屏透明隔离[/b]：维护 [code]self_modulate.a = 0.0[/code] 且零尺寸的 [VideoStreamPlayer] 节点，
##   既确保 Godot 渲染管线每帧驱动视频纹理解码，又彻底杜绝根视口 [code](0, 0)[/code] 裸绘穿帮与鼠标遮挡；[br]
## - [b]前后台帧缓冲锁存[/b]：仅当底层解码器输出有效宽高（[code]> 1x1[/code]）首帧纹理时才锁存至前台缓冲并触发 [signal first_frame_ready]，
##   停播时立即清空锁存纹理，根除起播闪黑与旧视频尾帧残留；[br]
## - [b]业务画布无侵入绑定[/b]：支持通过弱引用绑定业务层自定义的 [TextureRect]，首帧就绪时自动投射画面并揭幕，停播时自动清空；[br]
## - [b]静音首帧挂起（Standby）[/b]：支持在空闲期预挂载视频流、静音解码并锁存第一帧画面后暂停于 [code]0.0s[/code]，实现正式起播 0ms 瞬时响应。

signal first_frame_ready()
signal stream_finished()

const STANDBY_MAX_WAIT_SECONDS: float = 0.25

var _stream_player: VideoStreamPlayer = null
var _first_frame_ready: bool = false
var _latched_front_texture: Texture2D = null
var _standby_file: String = ""
var _is_in_standby: bool = false
var _standby_started_msec: int = 0

var _bound_target_ref: WeakRef = null
var _hide_bound_until_first_frame: bool = true


## 创建并挂载离屏透明隔离的底层 [VideoStreamPlayer] 节点
func setup(owner_node: Node) -> void:
	_stream_player = VideoStreamPlayer.new()
	_stream_player.name = "VideoStreamPlayerNode"
	_stream_player.expand = true
	_stream_player.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	_stream_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stream_player.focus_mode = Control.FOCUS_NONE
	_stream_player.size = Vector2.ZERO
	owner_node.add_child(_stream_player)
	_stream_player.finished.connect(_on_internal_stream_finished)


## 释放底层播放器流句柄与帧缓冲引用
func dispose() -> void:
	_is_in_standby = false
	_standby_file = ""
	_first_frame_ready = false
	_latched_front_texture = null
	unbind_display()
	if _stream_player != null and is_instance_valid(_stream_player):
		_stream_player.stop()
		_stream_player.stream = null


## 绑定业务层自定义的 [TextureRect] 画布组件（弱引用持有，首帧就绪自动赋纹理并揭幕，停播自动清空）
func bind_display(target: TextureRect, hide_until_first_frame: bool = true) -> void:
	if target == null or not is_instance_valid(target):
		unbind_display()
		return
	var prev := _get_bound_target()
	if prev != null and prev != target:
		prev.texture = null

	_bound_target_ref = weakref(target)
	_hide_bound_until_first_frame = hide_until_first_frame

	if _first_frame_ready and is_valid_decoded_texture(_latched_front_texture) and not _is_in_standby:
		target.texture = _latched_front_texture
		target.modulate.a = 1.0
	else:
		target.texture = null
		if _hide_bound_until_first_frame:
			target.modulate.a = 0.0


## 解除业务层 [TextureRect] 绑定并清空其残留纹理
func unbind_display(target: TextureRect = null) -> void:
	var bound := _get_bound_target()
	if target != null and bound != null and bound != target:
		return
	if bound != null:
		bound.texture = null
	_bound_target_ref = null


## 强制揭幕已绑定的 [TextureRect]（用于首帧等待超时兜底）
func reveal_bound_display() -> void:
	var bound := _get_bound_target()
	if bound == null:
		return
	if _latched_front_texture != null and bound.texture != _latched_front_texture:
		bound.texture = _latched_front_texture
	bound.modulate.a = 1.0


## 帧级轮询钩子：检测首帧解码完成或 Standby 超时；返回 true 表示仍需继续每帧轮询，false 表示可挂起 _process
func poll_frame() -> bool:
	if _stream_player == null or _stream_player.stream == null:
		return false

	var live_tex := _stream_player.get_video_texture()
	if is_valid_decoded_texture(live_tex):
		_latched_front_texture = live_tex
		if not _first_frame_ready:
			_first_frame_ready = true
			if _is_in_standby:
				_stream_player.paused = true
				_stream_player.stream_position = 0.0
			else:
				_sync_bound_display_frame()
				first_frame_ready.emit()
		else:
			_sync_bound_display_frame()
		return false

	if _is_in_standby:
		var elapsed := (Time.get_ticks_msec() - _standby_started_msec) / 1000.0
		if elapsed >= STANDBY_MAX_WAIT_SECONDS:
			_stream_player.paused = true
			_stream_player.stream_position = 0.0
			return false
		return true

	return not _first_frame_ready


## 在播放器空闲时进入静音首帧解码挂起态（Standby）；返回是否需要开启 _process 轮询等待首帧
func enter_standby(clean_path: String, stream: VideoStream) -> bool:
	if _stream_player == null or stream == null:
		return false
	if _is_in_standby and _standby_file == clean_path and _stream_player.stream == stream:
		return not _first_frame_ready

	_is_in_standby = true
	_standby_file = clean_path
	_first_frame_ready = false
	_latched_front_texture = null
	_stream_player.stop()
	_stream_player.stream = stream
	_stream_player.volume = 0.0
	_stream_player.loop = false
	_stream_player.play()
	_standby_started_msec = Time.get_ticks_msec()

	var live_tex := _stream_player.get_video_texture()
	if is_valid_decoded_texture(live_tex):
		_latched_front_texture = live_tex
		_first_frame_ready = true
		_stream_player.paused = true
		_stream_player.stream_position = 0.0
		return false
	return true


## 判断当前是否处于指定视频路径的 Standby 首帧挂起态
func is_standby_for(clean_path: String) -> bool:
	return (
		_is_in_standby
		and _standby_file == clean_path
		and _stream_player != null
		and _stream_player.stream != null
	)


## 接管并消费当前 Standby 热流（转为正式活动流，保留已锁存的首帧纹理）
func consume_standby() -> void:
	_is_in_standby = false
	_standby_file = ""


## 取消 Standby 首帧挂起态
func cancel_standby(stop_player: bool = true) -> void:
	if not _is_in_standby:
		return
	_is_in_standby = false
	_standby_file = ""
	if stop_player and _stream_player != null:
		_stream_player.stop()


## 挂载新的视频流并重置首帧锁存状态
func mount_stream(stream: VideoStream) -> void:
	cancel_standby(true)
	_first_frame_ready = false
	_latched_front_texture = null
	_reset_bound_display_for_new_stream()
	if _stream_player != null:
		_stream_player.stream = stream


## 将 [VideoPlayOptions] 参数装配到底层 [VideoStreamPlayer]
func apply_options(options: VideoPlayOptions) -> void:
	if options == null or _stream_player == null:
		return
	_hide_bound_until_first_frame = options.wait_first_frame
	_stream_player.loop = options.loop
	_stream_player.volume = clampf(options.volume, 0.0, 1.0)
	_stream_player.bus = options.audio_bus
	_stream_player.speed_scale = options.speed_scale
	if options.start_position > 0.0:
		_stream_player.stream_position = options.start_position


## 启动或继续播放底层视频流；返回 true 表示尚未解码出首帧、需开启 _process 轮询
func play() -> bool:
	if _stream_player == null or _stream_player.stream == null:
		return false
	_is_in_standby = false
	_standby_file = ""
	if not _stream_player.is_playing():
		_stream_player.play()
	_stream_player.paused = false

	var live_tex := _stream_player.get_video_texture()
	if is_valid_decoded_texture(live_tex):
		_latched_front_texture = live_tex
		if not _first_frame_ready:
			_first_frame_ready = true
			_sync_bound_display_frame()
			first_frame_ready.emit()
		else:
			_sync_bound_display_frame()
		return false
	if _first_frame_ready and is_valid_decoded_texture(_latched_front_texture):
		_sync_bound_display_frame()
		first_frame_ready.emit()
		return false
	return true


## 暂停底层视频流
func pause() -> void:
	if _stream_player != null:
		_stream_player.paused = true


## 恢复暂停的底层视频流；返回是否仍需轮询等待首帧
func resume() -> bool:
	if _stream_player == null:
		return false
	_stream_player.paused = false
	return not _first_frame_ready


## 停止播放并清空锁存的前台帧缓冲纹理与绑定画布（防止旧视频尾帧残留）
func stop() -> void:
	cancel_standby(false)
	_first_frame_ready = false
	_latched_front_texture = null
	_clear_bound_display_frame()
	if _stream_player != null:
		_stream_player.stop()


## 跳转播放位置（秒）
func seek(seconds: float) -> void:
	if _stream_player != null and _stream_player.stream != null:
		_stream_player.stream_position = maxf(0.0, seconds)


func set_volume(linear_volume: float) -> void:
	if _stream_player != null:
		_stream_player.volume = clampf(linear_volume, 0.0, 1.0)


func get_volume() -> float:
	return _stream_player.volume if _stream_player != null else 1.0


func set_looping(loop: bool) -> void:
	if _stream_player != null:
		_stream_player.loop = loop


func is_looping() -> bool:
	return _stream_player.loop if _stream_player != null else false


func is_playing() -> bool:
	return _stream_player != null and _stream_player.is_playing()


func get_duration() -> float:
	return _stream_player.get_stream_length() if _stream_player != null else -1.0


func get_playback_position() -> float:
	return _stream_player.get_stream_position() if _stream_player != null else 0.0


## 获取锁存的前台有效视频纹理（当未就绪或不允许暴露时返回 null）
func get_latched_texture(allow_expose: bool) -> Texture2D:
	if not allow_expose or _stream_player == null or _stream_player.stream == null:
		return null
	var live_tex := _stream_player.get_video_texture()
	if is_valid_decoded_texture(live_tex):
		_latched_front_texture = live_tex
		if not _first_frame_ready and not _is_in_standby:
			_first_frame_ready = true
			_sync_bound_display_frame()
			first_frame_ready.emit()
		else:
			_sync_bound_display_frame()
	return _latched_front_texture


## 查询当前视频流是否已解码并锁存第一帧有效画面纹理
func is_first_frame_ready() -> bool:
	if not _first_frame_ready and _stream_player != null and _stream_player.stream != null:
		var live_tex := _stream_player.get_video_texture()
		if is_valid_decoded_texture(live_tex):
			_latched_front_texture = live_tex
			_first_frame_ready = true
			if not _is_in_standby:
				_sync_bound_display_frame()
				first_frame_ready.emit()
	return _first_frame_ready


## 校验纹理是否为解码器输出的有效画面帧（过滤 null 与 0x0 / 1x1 占位黑纹理）
static func is_valid_decoded_texture(tex: Texture2D) -> bool:
	return tex != null and tex.get_width() > 1 and tex.get_height() > 1


#region Internal Display Binding Helpers
func _get_bound_target() -> TextureRect:
	if _bound_target_ref == null:
		return null
	var obj: Variant = _bound_target_ref.get_ref()
	if obj != null and is_instance_valid(obj) and obj is TextureRect:
		return obj as TextureRect
	_bound_target_ref = null
	return null


func _sync_bound_display_frame() -> void:
	var bound := _get_bound_target()
	if bound == null or _latched_front_texture == null:
		return
	if bound.texture != _latched_front_texture:
		bound.texture = _latched_front_texture
	bound.modulate.a = 1.0


func _reset_bound_display_for_new_stream() -> void:
	var bound := _get_bound_target()
	if bound == null:
		return
	bound.texture = null
	if _hide_bound_until_first_frame:
		bound.modulate.a = 0.0


func _clear_bound_display_frame() -> void:
	var bound := _get_bound_target()
	if bound == null:
		return
	bound.texture = null
	if _hide_bound_until_first_frame:
		bound.modulate.a = 0.0


func _on_internal_stream_finished() -> void:
	if _is_in_standby:
		if _stream_player != null:
			_stream_player.paused = true
			_stream_player.stream_position = 0.0
		return
	if _stream_player != null and _stream_player.loop:
		_stream_player.play()
		return
	stream_finished.emit()
#endregion
