@abstract
class_name BaseAudioSystem
extends Node

## 音频系统门面契约（Audio System Facade Contract）。[br]
##
## 本抽象基类作为业务层调度背景音乐与交互音效的唯一规范入口，核心职责：[br]
## - 统一双态入口（[method play_bgm] / [method play_sfx]）：同时支持传入 [code]res://[/code] 路径字符串或已加载的 [AudioStream] 实例；[br]
## - 同步缓存热路径：已缓存音效与音乐零协程分配、零帧延迟当场播放；[br]
## - BGM 双通道平滑交叉淡变与无损循环：通过播放器 [signal AudioStreamPlayer.finished] 信号控制循环，绝不篡改共享 [AudioStream] 资源属性；[br]
## - 音画避让解耦（[method duck_bgm] / [method unduck_bgm]）：独立维护系统避让衰减系数，永不污染或覆盖用户设定的总线音量；[br]
## - 注入式解耦：持有 [member default_button_sfx] 供通用 UI 控件播放，不硬编码业务音频文件路径。[br]
##
## 业务代码应统一通过 [code]App.audio[/code] 访问本契约提供的方法。


const BUS_MASTER: String = "Master"  ## 主音量总线名称
const BUS_BGM: String = "BGM"        ## 背景音乐总线名称
const BUS_SFX: String = "SFX"        ## 音效总线名称

## 默认全局通用按钮点击音效资源路径（由业务层在游戏启动期统一注入，解除底层控件耦合）。
var default_button_sfx: String = ""


#region BGM Management
## 播放背景音乐（支持交叉淡变、无损循环控制与异步竞态守卫）。[br]
##
## [param source] 音频资源路径（[code]res://[/code] [String]）或已加载的 [AudioStream] 实例。[br]
## [param volume] 增益微调值（分贝 dB，0.0 为标准原音）。[br]
## [param fade] 交叉淡变时长（秒，默认 0.6）；传 0.0 则立即瞬切。[br]
## [param loop] 曲目播放完毕后是否自动循环重播（默认 true，不篡改底层资源属性）。
@abstract
func play_bgm(source: Variant, volume: float = 0.0, fade: float = 0.6, loop: bool = true) -> void


## 按路径播放背景音乐（兼容别名，等价于 [method play_bgm]）。
@abstract
func play_bgm_by_path(path: String, volume: float = 0.0, fade: float = 0.6) -> void


## 停止当前正在播放的背景音乐。[br]
##
## [param fade] 淡出时长（秒，默认 0.6）。音乐将在指定时间内线性降低音量直至完全静音停止。
@abstract
func stop_bgm(fade: float = 0.6) -> void


## 压低（避让）背景音乐音量（如播放过场视频或关键语音期间）。[br]
##
## 该衰减系数与用户设定的总线音量正交相乘，[method get_bus_volume] 仍返回真实的用户设定音量。[br]
##
## [param target_scale] 目标衰减线性比例（0.0 表示完全静音避让，0.2 表示压低至 20%）。[br]
## [param fade] 过渡时长（秒，默认 0.5）。
@abstract
func duck_bgm(target_scale: float = 0.0, fade: float = 0.5) -> void


## 恢复被压低（避让）的背景音乐至用户设定音量。[br]
##
## [param fade] 恢复过渡时长（秒，默认 0.5）。
@abstract
func unduck_bgm(fade: float = 0.5) -> void
#endregion


#region SFX Management
## 播放一次短音效（自动从内部 16 通道空闲优先池调度；已缓存音效零协程同步瞬发）。[br]
##
## [param source] 音效资源路径（[code]res://[/code] [String]）或已加载的 [AudioStream] 实例。[br]
## [param volume] 增益微调（分贝 dB，默认 0.0）。[br]
## [param pitch_scale] 播放音高倍率（默认 1.0 原速原调，可用于高频同类音效防听觉疲劳微调）。
@abstract
func play_sfx(source: Variant, volume: float = 0.0, pitch_scale: float = 1.0) -> void


## 按路径播放短音效（兼容别名，等价于 [method play_sfx]）。
@abstract
func play_sfx_by_path(path: String, volume: float = 0.0, pitch_scale: float = 1.0) -> void


## 立即停止当前 SFX 播放池中正在播放的所有音效（如战斗退场或场景切换时清理残余长音效）。
@abstract
func stop_all_sfx() -> void
#endregion


#region Bus & Channel Volume Controls
## 设置指定音频总线的用户音量大小（基于 0.0 ~ 1.0 的平滑线性标量）。[br]
##
## [param bus] 总线名称（如 "Master"、"BGM"、"SFX"）。[br]
## [param linear] 线性音量值（0.0 表示完全静音，1.0 表示满音量）。系统内部自动转换为 dB 分贝。
@abstract
func set_bus_volume(bus: String, linear: float) -> void


## 获取指定音频总线的用户设定音量线性标量（0.0 ~ 1.0，不受临时 BGM 避让影响）。[br]
##
## [param bus] 总线名称。[br]
## @return 返回 0.0 ~ 1.0 的浮点数。
@abstract
func get_bus_volume(bus: String) -> float


## 设置指定音频总线的静音状态。[br]
##
## [param bus] 总线名称。[br]
## [param mute] 是否静音。
@abstract
func set_bus_mute(bus: String, mute: bool) -> void


## 查询指定音频总线是否处于静音状态。[br]
##
## [param bus] 总线名称。[br]
## @return 返回布尔值。
@abstract
func is_bus_muted(bus: String) -> bool


## 设置音乐总开关。[br]
##
## [param enabled] 是否启用音乐。
@abstract
func set_music_enabled(enabled: bool) -> void


## 查询音乐总开关是否开启。[br]
##
## @return 返回布尔值。
@abstract
func is_music_enabled() -> bool


## 设置音效总开关。[br]
##
## [param enabled] 是否启用音效。
@abstract
func set_sfx_enabled(enabled: bool) -> void


## 查询音效总开关是否开启。[br]
##
## @return 返回布尔值。
@abstract
func is_sfx_enabled() -> bool


## 全局暂停或恢复所有音频播放（如应用切到后台时静音）。[br]
##
## [param paused] 是否全局暂停。
@abstract
func set_paused(paused: bool) -> void


## 异步加载指定路径的音频资源流对象。[br]
##
## [param path] 音频路径。[br]
## @return 返回 [AudioStream] 实例。
@abstract
func load_audio(path: String) -> AudioStream
#endregion
