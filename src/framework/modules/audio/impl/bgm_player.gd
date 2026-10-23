class_name BgmPlayer
extends RefCounted

## BGM 双播放器交叉淡变控制器（私有实现，仅供 [AudioSystem] 使用）。[br]
##
## [b]核心设计机制：[/b][br]
## 1. [b]双通道交叉淡变[/b]：两个 [AudioStreamPlayer] 轮流承担“当前播放/新曲淡入”角色；[br]
## 2. [b]无损播放器级循环控制[/b]：通过监听 [signal AudioStreamPlayer.finished] 信号实现循环重播，
##    绝不直接修改共享 [AudioStream] 资源的 [code]loop[/code] 属性，兼容全部内置与自定义音频流类型；[br]
## 3. [b]同曲淡出中断恢复与暂停同步[/b]：支持淡出途中重新唤醒同曲，暂停时同步冻结淡变 Tween。

const DEFAULT_FADE: float = 0.6    ## 交叉淡变默认时长(秒)
const SILENT_DB: float = -80.0     ## 视作静音的分贝值(≈线性 0)

var _host: Node
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _loop: bool = true
var _is_stopping: bool = false
var _is_paused: bool = false
var _tween: Tween


## 当前活动播放器的音频流（若未播放则为 null）。
var active_stream: AudioStream:
	get:
		if _players.is_empty():
			return null
		return _players[_active].stream


## 在 [param host] 下挂载两个走 [param bus] 总线的播放器。
func _init(host: Node, bus: String) -> void:
	_host = host
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.finished.connect(_on_player_finished.bind(i))
		NodeUtils.mount_required(p, host, "BGMPlayer_%d" % i)
		_players.append(p)


## 当前是否有 BGM 正在有效播放（不含已触发 stop 淡出收尾态）。
func is_playing() -> bool:
	if _players.is_empty():
		return false
	return _players[_active].playing and not _is_stopping


## 播放 [param stream]，与当前曲目交叉淡变。同一曲目正在播放则不打断并平滑调整目标音量。
func play(stream: AudioStream, volume: float = 0.0, fade: float = DEFAULT_FADE, loop: bool = true) -> void:
	if stream == null or _players.is_empty():
		return

	_loop = loop
	var active := _players[_active]
	var standby := _players[1 - _active]

	# 1. 同曲重入：即使此前处于淡出（_is_stopping）或音量过渡，也仅接管音量而不重头播放
	if active.stream == stream and active.playing:
		kill_tween()
		_is_stopping = false
		if standby.playing:
			standby.stop()
		if fade <= 0.0 or is_equal_approx(active.volume_db, volume):
			active.volume_db = volume
		else:
			_tween = _host.create_tween()
			_tween.tween_property(active, "volume_db", volume, fade)
			if _is_paused:
				_tween.pause()
		return

	# 2. 切换新曲目：先终止旧淡变 Tween
	kill_tween()
	_is_stopping = false
	var incoming := standby
	incoming.stream = stream

	# 3. 瞬切快路径（fade <= 0.0）：零 Tween 分配，立即停旧播新
	if fade <= 0.0:
		if active.playing:
			active.stop()
		incoming.volume_db = volume
		incoming.play()
		incoming.stream_paused = _is_paused
		_active = 1 - _active
		return

	# 4. 平滑交叉淡变：新通道从静音淡入，旧通道（仅当正在播放时）同步淡出并停止
	incoming.volume_db = SILENT_DB
	incoming.play()
	incoming.stream_paused = _is_paused

	_tween = _host.create_tween().set_parallel(true)
	_tween.tween_property(incoming, "volume_db", volume, fade)
	if active.playing:
		_tween.tween_property(active, "volume_db", SILENT_DB, fade)
		_tween.chain().tween_callback(active.stop)
	if _is_paused:
		_tween.pause()

	_active = 1 - _active


## 淡出并停止当前曲目。
func stop(fade: float = DEFAULT_FADE) -> void:
	if _players.is_empty():
		return
	var active := _players[_active]
	var standby := _players[1 - _active]

	kill_tween()
	if standby.playing:
		standby.stop()

	if not active.playing:
		_is_stopping = false
		return

	if fade <= 0.0:
		_is_stopping = false
		active.volume_db = SILENT_DB
		active.stop()
		active.stream = null
		standby.stream = null
		return

	_is_stopping = true
	_tween = _host.create_tween()
	_tween.tween_property(active, "volume_db", SILENT_DB, fade)
	_tween.tween_callback(_on_stop_finished.bind(active))
	if _is_paused:
		_tween.pause()


## 暂停 / 恢复两个播放器及进行中的淡变 Tween。
func set_paused(paused: bool) -> void:
	_is_paused = paused
	for p in _players:
		p.stream_paused = paused
	if _tween != null and _tween.is_valid():
		if paused:
			_tween.pause()
		else:
			_tween.play()


## 终止正在进行的淡变 Tween。
func kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _on_stop_finished(target_player: AudioStreamPlayer) -> void:
	_is_stopping = false
	if is_instance_valid(target_player):
		target_player.stop()


## 播放器自然结束回调：当处于活动通道、未停止且开启 loop 时自动重播（无需篡改底层 AudioStream.loop 属性）。
func _on_player_finished(player_idx: int) -> void:
	if player_idx != _active or _is_stopping or not _loop:
		return
	if _players.is_empty():
		return
	var active := _players[_active]
	if is_instance_valid(active) and active.stream != null:
		active.play()
		active.stream_paused = _is_paused
