class_name SfxPool
extends RefCounted

## SFX 播放器池（私有实现，仅供 [AudioSystem] 使用）。[br]
## 固定数量的 [AudioStreamPlayer] 轮转使用，超过并发数会打断最早的那个(可接受)。

const DEFAULT_SIZE: int = 8   ## SFX 并发播放上限

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


## 在 [param host] 下挂载 [param size] 个走 [param bus] 总线的播放器。
func _init(host: Node, bus: String, size: int = DEFAULT_SIZE) -> void:
	for i in size:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		NodeUtils.mount_required(p, host, "SFXPlayer_%d" % i)
		_players.append(p)


## 用下一个轮转播放器播放 [param stream]。
func play(stream: AudioStream, volume: float = 0.0) -> void:
	if _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume
	p.play()


## 暂停 / 恢复池内全部播放器。
func set_paused(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused
