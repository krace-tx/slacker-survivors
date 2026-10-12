class_name BgmPlayer
extends RefCounted

## BGM 双播放器交叉淡变（私有实现，仅供 [AudioSystem] 使用）。[br]
##
## 两个 [AudioStreamPlayer] 轮流做"当前/淡入"角色，实现真正的交叉淡变（旧的淡出同时新的淡入）。
## Tween 挂在宿主节点上；宿主随 App 常驻，保证 BGM 跨场景不中断。

const DEFAULT_FADE: float = 0.6    ## 交叉淡变默认时长(秒)
const SILENT_DB: float = -80.0     ## 视作静音的分贝值(≈线性 0)

var _host: Node
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0

## 当前正在进行的交叉淡变 tween。新切换前先 kill 它，避免快速连切时旧淡变
## 的收尾 stop() 误杀新曲(fire-and-forget 竞态)。
var _tween: Tween


## 在 [param host] 下挂载两个走 [param bus] 总线的播放器。
func _init(host: Node, bus: String) -> void:
	_host = host
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		NodeUtils.mount_required(p, host, "BGMPlayer_%d" % i)
		_players.append(p)


## 播放 [param stream]，与当前曲目交叉淡变。**同一曲目正在播放则不打断**(跨场景连续的关键)。[br]
## 会强制开启循环播放。
func play(stream: AudioStream, volume: float = 0.0, fade: float = DEFAULT_FADE) -> void:
	_ensure_stream_loop(stream)

	var active := _players[_active]
	if active.stream == stream and active.playing:
		return

	kill_tween()
	var incoming := _players[1 - _active]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()

	_tween = _host.create_tween().set_parallel(true)
	_tween.tween_property(active, "volume_db", SILENT_DB, fade)
	_tween.tween_property(incoming, "volume_db", volume, fade)
	_tween.chain().tween_callback(active.stop)

	_active = 1 - _active


## 淡出并停止当前曲目。
func stop(fade: float = DEFAULT_FADE) -> void:
	var active := _players[_active]
	if not active.playing:
		return
	kill_tween()
	_tween = _host.create_tween()
	_tween.tween_property(active, "volume_db", SILENT_DB, fade)
	_tween.tween_callback(active.stop)


## 暂停 / 恢复两个播放器。
func set_paused(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused


## kill 掉正在进行的 tween(若有)，让新的淡变从当前状态接管。
func kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


## 尝试根据具体音频流类型开启循环播放
func _ensure_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
