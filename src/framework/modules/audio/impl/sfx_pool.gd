class_name SfxPool
extends RefCounted

## SFX 智能播放器池（私有实现，仅供 [AudioSystem] 使用）。[br]
##
## 采用“空闲通道优先（Idle-First）+ 最早播放抢占（Oldest-Active Stealing）”混合调度策略：[br]
## - 当池中存在空闲通道时，绝不打断正在播放的长音效（如 Boss 咆哮、技能持续音）；[br]
## - 仅当全部通道满载时，才抢占最早启动的声道，兼顾高并发弹幕音效与长音效完整性。

const DEFAULT_SIZE: int = 16   ## SFX 并发播放通道上限

var _players: Array[AudioStreamPlayer] = []
var _started_at: PackedInt64Array = PackedInt64Array()
var _next: int = 0
var _is_paused: bool = false


## 在 [param host] 下挂载 [param size] 个走 [param bus] 总线的播放器。
func _init(host: Node, bus: String, size: int = DEFAULT_SIZE) -> void:
	var pool_size := maxi(1, size)
	_started_at.resize(pool_size)
	for i in pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		NodeUtils.mount_required(p, host, "SFXPlayer_%d" % i)
		_players.append(p)
		_started_at[i] = 0


## 调度一个可用通道播放 [param stream]。
func play(stream: AudioStream, volume: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _players.is_empty():
		return
	var idx := _acquire_slot()
	var p := _players[idx]
	_started_at[idx] = Time.get_ticks_msec()
	p.stream = stream
	p.volume_db = volume
	p.pitch_scale = maxf(0.01, pitch_scale)
	p.play()
	p.stream_paused = _is_paused


## 立即停止池内全部正在播放的音效并释放流引用。
func stop_all() -> void:
	for i in _players.size():
		var p := _players[i]
		if p.playing:
			p.stop()
		p.stream = null
		_started_at[i] = 0


## 暂停 / 恢复池内全部播放器。
func set_paused(paused: bool) -> void:
	_is_paused = paused
	for p in _players:
		p.stream_paused = paused


## 优先选择空闲通道；全忙时淘汰启动时间最早的通道。
func _acquire_slot() -> int:
	var count := _players.size()
	# 1. 空闲优先扫描
	for offset in count:
		var idx := (_next + offset) % count
		if not _players[idx].playing:
			_next = (idx + 1) % count
			return idx

	# 2. 全满载：抢占最早启动的声道
	var oldest_idx := _next
	var oldest_time := _started_at[oldest_idx]
	for i in count:
		if _started_at[i] < oldest_time:
			oldest_time = _started_at[i]
			oldest_idx = i
	_next = (oldest_idx + 1) % count
	return oldest_idx
