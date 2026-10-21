class_name AudioSystem
extends BaseAudioSystem

## 音频系统：提供 BGM/SFX 分组总线音量控制、BGM 跨场景交叉淡变、音画避让解耦与 SFX 智能声道池。[br]
##
## [b]核心设计特性：[/b][br]
## 1. [b]同步缓存热路径（Zero-Coroutine Hot Path）[/b]：[method play_sfx] 与 [method play_bgm] 主入口不挂 [code]await[/code]；
##    当传入 [AudioStream] 或路径已命中 [BaseAssetSystem.get_cached] 时，零协程状态机分配、零帧延迟当场播放；[br]
## 2. [b]异步切歌竞态守卫（BGM Request Versioning）[/b]：通过单调递增版本号 [code]_bgm_request_id[/code]
##    拦截异步加载期间过期的切歌或停止指令，彻底消除快速切场景时的 BGM 覆盖串音；[br]
## 3. [b]正交音画避让（Orthogonal BGM Ducking）[/b]：将用户设定音量 [code]_user_bus_volumes[/code] 与避让衰减系数
##    [code]_bgm_duck_scale[/code] 分离存储，过场视频避让期间 [method get_bus_volume] 仍返回真实用户设定值，永不污染玩家配置。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"audio"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"asset", &"logger"]
#endregion

#region Constants & Enums
const _BUS_MASTER: String = BUS_MASTER
const _BUS_BGM: String = BUS_BGM
const _BUS_BGM_ALIAS: String = "Music"
const _BUS_SFX: String = BUS_SFX

const _SILENT_DB: float = BgmPlayer.SILENT_DB  ## 视作静音的分贝值(≈线性 0)
const MIN_INTERVAL_MS: int = 30                ## 同音效最小播放间隔（毫秒）
const _MAX_THROTTLE_KEYS: int = 128            ## 限频时间戳表容量上限，防止无限增长
#endregion

#region Dependencies & State
var _asset_system: BaseAssetSystem
var _logger: BaseFrameworkLogger

## BGM 双播放器交叉淡变；[method _ready] 时创建。
var _bgm: BgmPlayer
## SFX 播放器池；[method _ready] 时创建。
var _sfx: SfxPool

## 音效标识 -> 上次播放时间戳（毫秒）
var _last_played_times: Dictionary = {}
## 当前正在播放或请求播放的 BGM 标识
var _current_bgm_key: String = ""
## BGM 异步请求单调递增版本号，用于拦截过期异步加载回调
var _bgm_request_id: int = 0

## 用户设定的各总线线性音量（0.0 ~ 1.0），与临时 ducking 衰减解耦
var _user_bus_volumes: Dictionary = {
	_BUS_MASTER: 1.0,
	_BUS_BGM: 1.0,
	_BUS_SFX: 1.0,
}
## BGM 避让线性衰减比例（1.0 为正常无衰减，0.0 为完全静音避让）
var _bgm_duck_scale: float = 1.0
var _duck_tween: Tween = null
var _is_paused: bool = false
var _disposed: bool = false
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
	_sync_initial_bus_volumes()
	_bgm = BgmPlayer.new(self, _BUS_BGM)
	_sfx = SfxPool.new(self, _BUS_SFX)


func dispose() -> void:
	_disposed = true
	_bgm_request_id += 1
	_current_bgm_key = ""
	_last_played_times.clear()
	_kill_duck_tween()
	if _bgm != null:
		_bgm.kill_tween()
	if _sfx != null:
		_sfx.stop_all()
	if is_inside_tree():
		queue_free()
#endregion

#region Public API
#region BGM Playback
## 播放背景音乐（支持传入 String 路径或 AudioStream 实例；缓存命中时零协程同步播放）。
func play_bgm(source: Variant, volume: float = 0.0, fade: float = BgmPlayer.DEFAULT_FADE, loop: bool = true) -> void:
	if _disposed or source == null or _bgm == null:
		return

	# 1. 直接传入 AudioStream 实例：同步零延迟播放
	if source is AudioStream:
		var direct_stream := source as AudioStream
		_bgm_request_id += 1
		_current_bgm_key = direct_stream.resource_path if not direct_stream.resource_path.is_empty() else str(direct_stream.get_instance_id())
		_bgm.play(direct_stream, volume, fade, loop)
		return

	if not (source is String):
		return
	var path := source as String
	if path.is_empty():
		return

	# 2. 同路径且当前正在播放：直接调整目标音量与循环标记
	if path == _current_bgm_key and _bgm.active_stream != null and _bgm.is_playing():
		_bgm_request_id += 1
		_bgm.play(_bgm.active_stream, volume, fade, loop)
		return

	_bgm_request_id += 1
	var req_id := _bgm_request_id
	_current_bgm_key = path

	# 3. 同步缓存快路径：若已在 AssetCache 中命中，当场直接播放，免创建异步协程
	var cached_stream := _get_cached_audio(path)
	if cached_stream != null:
		_bgm.play(cached_stream, volume, fade, loop)
		return

	# 4. 缓存未命中慢路径：交由内部异步协程加载
	_play_bgm_async(path, req_id, volume, fade, loop)


## 按路径播放背景音乐（兼容接口）。
func play_bgm_by_path(path: String, volume: float = 0.0, fade: float = BgmPlayer.DEFAULT_FADE) -> void:
	play_bgm(path, volume, fade, true)


## 停止背景音乐（淡出）。
func stop_bgm(fade: float = BgmPlayer.DEFAULT_FADE) -> void:
	_bgm_request_id += 1
	_current_bgm_key = ""
	if _bgm != null:
		_bgm.stop(fade)


## 压低（避让）背景音乐音量，与用户设定的 BGM 总线音量正交。
func duck_bgm(target_scale: float = 0.0, fade: float = 0.5) -> void:
	if _disposed:
		return
	target_scale = clampf(target_scale, 0.0, 1.0)
	_kill_duck_tween()
	if fade <= 0.0 or not is_inside_tree() or is_equal_approx(_bgm_duck_scale, target_scale):
		_set_bgm_duck_scale(target_scale)
		return
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_bgm_duck_scale, _bgm_duck_scale, target_scale, fade)
	if _is_paused:
		_duck_tween.pause()


## 恢复被压低（避让）的背景音乐音量。
func unduck_bgm(fade: float = 0.5) -> void:
	duck_bgm(1.0, fade)
#endregion

#region SFX Playback
## 播放短音效（支持传入 String 路径或 AudioStream 实例；缓存命中时零协程同步瞬发）。
func play_sfx(source: Variant, volume: float = 0.0, pitch_scale: float = 1.0) -> void:
	if _disposed or source == null or _sfx == null or not is_sfx_enabled():
		return

	# 1. 直接传入 AudioStream 实例
	if source is AudioStream:
		var direct_stream := source as AudioStream
		var key := direct_stream.resource_path if not direct_stream.resource_path.is_empty() else str(direct_stream.get_instance_id())
		if not _allow_sfx_trigger(key):
			return
		_sfx.play(direct_stream, volume, pitch_scale)
		return

	if not (source is String):
		return
	var path := source as String
	if path.is_empty() or not _allow_sfx_trigger(path):
		return

	# 2. 同步缓存热路径（99.9% 命中场景）：零协程分配、零帧延迟当场播放
	var cached_stream := _get_cached_audio(path)
	if cached_stream != null:
		_sfx.play(cached_stream, volume, pitch_scale)
		return

	# 3. 首次冷加载慢路径：交由内部异步协程加载后播放
	_play_sfx_async(path, volume, pitch_scale)


## 按路径播放短音效（兼容接口）。
func play_sfx_by_path(path: String, volume: float = 0.0, pitch_scale: float = 1.0) -> void:
	play_sfx(path, volume, pitch_scale)


## 立即停止当前 SFX 播放池中的所有音效。
func stop_all_sfx() -> void:
	if _sfx != null:
		_sfx.stop_all()
#endregion

#region Bus Volume & Mute
## 设置指定音频总线的用户音量（线性 0.0~1.0，内部正交叠加避让系数后转为 dB）。
func set_bus_volume(bus_name: String, linear: float) -> void:
	var canonical := _canonical_bus_name(bus_name)
	var idx := AudioServer.get_bus_index(canonical)
	if idx == -1:
		return
	linear = clampf(linear, 0.0, 1.0)
	_user_bus_volumes[canonical] = linear
	_apply_bus_volume(canonical, idx)


## 获取指定音频总线的用户设定线性音量（0.0~1.0，不受临时 BGM 避让影响）。
func get_bus_volume(bus_name: String) -> float:
	var canonical := _canonical_bus_name(bus_name)
	if _user_bus_volumes.has(canonical):
		return float(_user_bus_volumes[canonical])
	var idx := AudioServer.get_bus_index(canonical)
	if idx == -1:
		return 0.0
	var db := AudioServer.get_bus_volume_db(idx)
	return 0.0 if db <= _SILENT_DB else clampf(db_to_linear(db), 0.0, 1.0)


## 设置总线静音。
func set_bus_mute(bus_name: String, mute: bool) -> void:
	var idx := _resolve_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_mute(idx, mute)


## 查询总线是否静音。
func is_bus_muted(bus_name: String) -> bool:
	var idx := _resolve_bus_index(bus_name)
	return AudioServer.is_bus_mute(idx) if idx != -1 else false
#endregion

#region Semantic Shortcuts
func set_music_enabled(enabled: bool) -> void:
	set_bus_mute(_BUS_BGM, not enabled)


func is_music_enabled() -> bool:
	return not is_bus_muted(_BUS_BGM)


func set_sfx_enabled(enabled: bool) -> void:
	set_bus_mute(_BUS_SFX, not enabled)
	if not enabled and _sfx != null:
		_sfx.stop_all()


func is_sfx_enabled() -> bool:
	return not is_bus_muted(_BUS_SFX)


## 暂停/恢复所有播放（切后台、打开全屏菜单时使用）。
func set_paused(paused: bool) -> void:
	_is_paused = paused
	if _bgm != null:
		_bgm.set_paused(paused)
	if _sfx != null:
		_sfx.set_paused(paused)
	if _duck_tween != null and _duck_tween.is_valid():
		if paused:
			_duck_tween.pause()
		else:
			_duck_tween.play()
#endregion

#region Asset Loading
## 异步加载音频资源（优先走 BaseAssetSystem 缓存，降级走 ResourceLoader）。
func load_audio(path: String) -> AudioStream:
	if path.is_empty() or _disposed:
		return null

	var cached := _get_cached_audio(path)
	if cached != null:
		return cached

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
func _get_cached_audio(path: String) -> AudioStream:
	if _asset_system != null:
		return _asset_system.get_cached(path) as AudioStream
	if ResourceLoader.has_cached(path):
		return ResourceLoader.load(path) as AudioStream
	return null


func _play_bgm_async(path: String, req_id: int, volume: float, fade: float, loop: bool) -> void:
	var stream: AudioStream = await load_audio(path)
	if _disposed or req_id != _bgm_request_id:
		return
	if stream == null or _bgm == null:
		_current_bgm_key = ""
		return
	_bgm.play(stream, volume, fade, loop)


func _play_sfx_async(path: String, volume: float, pitch_scale: float) -> void:
	var stream: AudioStream = await load_audio(path)
	if _disposed or stream == null or _sfx == null or not is_sfx_enabled():
		return
	_sfx.play(stream, volume, pitch_scale)


func _allow_sfx_trigger(key: String) -> bool:
	var now := Time.get_ticks_msec()
	if _last_played_times.has(key) and (now - int(_last_played_times[key]) < MIN_INTERVAL_MS):
		return false
	if _last_played_times.size() >= _MAX_THROTTLE_KEYS:
		_last_played_times.clear()
	_last_played_times[key] = now
	return true


func _canonical_bus_name(bus_name: String) -> String:
	return _BUS_BGM if bus_name == _BUS_BGM_ALIAS else bus_name


func _resolve_bus_index(bus_name: String) -> int:
	return AudioServer.get_bus_index(_canonical_bus_name(bus_name))


func _sync_initial_bus_volumes() -> void:
	for bus_name in [_BUS_MASTER, _BUS_BGM, _BUS_SFX]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx != -1:
			var db := AudioServer.get_bus_volume_db(idx)
			_user_bus_volumes[bus_name] = 0.0 if db <= _SILENT_DB else clampf(db_to_linear(db), 0.0, 1.0)


func _set_bgm_duck_scale(scale_val: float) -> void:
	_bgm_duck_scale = clampf(scale_val, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(_BUS_BGM)
	if idx != -1:
		_apply_bus_volume(_BUS_BGM, idx)


func _apply_bus_volume(canonical_bus: String, bus_idx: int) -> void:
	var user_linear: float = float(_user_bus_volumes.get(canonical_bus, 1.0))
	var effective_linear: float = user_linear * _bgm_duck_scale if canonical_bus == _BUS_BGM else user_linear
	var db := linear_to_db(effective_linear) if effective_linear > 0.0001 else _SILENT_DB
	AudioServer.set_bus_volume_db(bus_idx, db)


func _kill_duck_tween() -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = null


## 确保音频总线存在，不存在则创建并路由至 Master。
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, _BUS_MASTER)
#endregion
