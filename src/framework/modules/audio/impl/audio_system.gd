class_name AudioSystem
extends BaseAudioSystem

## 音频系统：提供 BGM/SFX 分组总线音量控制、BGM 跨场景交叉淡变、SFX 播放器池复用功能。
##
## 建议全项目的音频播放均通过此系统调用，避免直接实例化 AudioStreamPlayer。
## 统一管理可确保音量分组生效、跨场景 BGM 无缝衔接以及播放器资源的有效复用。
##
## BGM 与 SFX 分别使用独立的音频总线（自动创建并路由至 Master），
## 以便在设置菜单中独立调节“音乐”与“音效”音量。
## 本系统作为 Node 常驻场景树（挂载在 App 下），以保证 BGM 在场景切换时不中断。
##
## 交叉淡变实现在 [BgmPlayer]，播放器池实现在 [SfxPool]；本系统只负责资源加载、总线与限频。

#region Constants & Enums
const _BUS_MASTER: String = "Master"
const _BUS_BGM: String = "BGM"
const _BUS_SFX: String = "SFX"

const _SILENT_DB: float = BgmPlayer.SILENT_DB  ## 视作静音的分贝值(≈线性 0)
const MIN_INTERVAL_MS: int = 30     ## 同音效最小播放间隔（毫秒）
#endregion

#region Dependencies & State
var _asset_system: BaseAssetSystem
var _logger: BaseFrameworkLogger

## BGM 双播放器交叉淡变；[method _ready] 时创建。
var _bgm: BgmPlayer
## SFX 播放器池；[method _ready] 时创建。
var _sfx: SfxPool

## 路径 -> 上次播放时间戳（毫秒）
var _last_played_times: Dictionary = {}
#endregion

#region Lifecycle
func _init(asset_system: BaseAssetSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_asset_system = asset_system
	_logger = logger


func initialize() -> Result:
	return Result.ok()


func set_asset_system(asset_system: BaseAssetSystem) -> void:
	_asset_system = asset_system


func set_logger(logger: BaseFrameworkLogger) -> void:
	_logger = logger


func _ready() -> void:
	_ensure_bus(_BUS_BGM)
	_ensure_bus(_BUS_SFX)
	_bgm = BgmPlayer.new(self, _BUS_BGM)
	_sfx = SfxPool.new(self, _BUS_SFX)


func dispose() -> void:
	if _bgm != null:
		_bgm.kill_tween()
	if is_inside_tree():
		queue_free()
#endregion

#region Public API
#region BGM Playback
## 播放背景音乐,与当前曲目交叉淡变。**同一曲目正在播放则不打断**(跨场景连续的关键)。
func play_bgm_by_path(path: String, volume: float = 0.0, fade: float = BgmPlayer.DEFAULT_FADE) -> void:
	var stream: AudioStream = await load_audio(path)
	if stream == null or _bgm == null:
		return
	_bgm.play(stream, volume, fade)


## 停止背景音乐(淡出)。
func stop_bgm(fade: float = BgmPlayer.DEFAULT_FADE) -> void:
	if _bgm != null:
		_bgm.stop(fade)
#endregion

#region SFX Playback
## 播放指定路径的音效，包含同音抑制和分贝调节。
func play_sfx_by_path(path: String, volume: float = 0.0) -> void:
	var now := Time.get_ticks_msec()
	if _last_played_times.has(path) and (now - _last_played_times[path] < MIN_INTERVAL_MS):
		return
	_last_played_times[path] = now

	var stream: AudioStream = await load_audio(path)
	if stream == null or _sfx == null:
		return
	_sfx.play(stream, volume)
#endregion

#region Bus Volume & Mute
## 设置总线音量,线性 0.0~1.0 内部转为 dB。
func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	linear = clampf(linear, 0.0, 1.0)
	var db := linear_to_db(linear) if linear > 0.0001 else _SILENT_DB
	AudioServer.set_bus_volume_db(idx, db)


## 获取总线当前线性音量 0.0~1.0。
func get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 0.0
	var db := AudioServer.get_bus_volume_db(idx)
	return 0.0 if db <= _SILENT_DB else db_to_linear(db)


## 设置总线静音。
func set_bus_mute(bus_name: String, mute: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_mute(idx, mute)


## 查询总线是否静音。
func is_bus_muted(bus_name: String) -> bool:
	var idx := AudioServer.get_bus_index(bus_name)
	return AudioServer.is_bus_mute(idx) if idx != -1 else false
#endregion

#region Semantic Shortcuts
func set_music_enabled(enabled: bool) -> void:
	set_bus_mute(_BUS_BGM, not enabled)


func is_music_enabled() -> bool:
	return not is_bus_muted(_BUS_BGM)


func set_sfx_enabled(enabled: bool) -> void:
	set_bus_mute(_BUS_SFX, not enabled)


func is_sfx_enabled() -> bool:
	return not is_bus_muted(_BUS_SFX)


## 暂停/恢复所有播放(切后台、打开全屏菜单时使用)。
func set_paused(paused: bool) -> void:
	if _bgm != null:
		_bgm.set_paused(paused)
	if _sfx != null:
		_sfx.set_paused(paused)
#endregion

#region Asset Loading
## 异步加载音频资源（优先走 BaseAssetSystem 缓存，降级走 ResourceLoader）
func load_audio(path: String) -> AudioStream:
	if path.is_empty():
		return null
	
	var stream: AudioStream = null
	if _asset_system != null:
		var result := await _asset_system.load(path)
		if result.is_ok():
			stream = result.value as AudioStream
	else:
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path) as AudioStream

	if stream == null:
		if _logger != null:
			_logger.warn("AudioSystem", "Audio file not found or load failed: %s" % path)
		else:
			push_warning("AudioSystem: Audio file not found or load failed: %s" % path)
		return null
		
	return stream
#endregion
#endregion

#region Internal
## 确保音频总线存在,不存在则创建并 send 到 Master(免去手工维护 default_bus_layout.tres)。
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, _BUS_MASTER)
#endregion
