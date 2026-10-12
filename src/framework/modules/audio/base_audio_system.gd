@abstract
class_name BaseAudioSystem
extends NodeSubsystem

## 音频系统门面契约（Audio System Facade Contract）。[br]
##
## 本抽象基类作为业务层调度背景音乐与交互音效的唯一规范入口，核心职责：[br]
## - BGM 双通道平滑交叉淡入淡出（Cross-Fade）：避免切歌时的突兀断音；[br]
## - SFX 动态对象池：管理多路音效并发复用，防止高频触发创建过多节点；[br]
## - 引擎 AudioServer 物理总线绑定：Master / Music / SFX 线性音量控制与静音管理；[br]
## - 注入式解耦：持有 [member default_button_sfx] 供通用 UI 控件播放，不硬编码业务音频文件路径。[br]
##
## 业务代码应统一通过 [code]App.audio[/code] 访问本契约提供的方法。


## 默认全局通用按钮点击音效资源路径（由业务层在游戏启动期统一注入，解除底层控件耦合）。
var default_button_sfx: String = ""


## 返回该子系统的全局唯一注册标识符。
func get_id() -> String:
	return "audio"


#region BGM Management
## 播放指定路径的背景音乐（支持交叉淡变 Cross-Fade）。[br]
##
## [param path] 音频资源路径（[code]res://[/code] 开头）。[br]
## [param volume] 增益微调值（分贝 dB，0.0 为标准原音）。[br]
## [param fade] 交叉淡变时长（秒，默认 0.6）。新旧音乐在淡变区间内平滑过渡。
@abstract
func play_bgm_by_path(path: String, volume: float = 0.0, fade: float = 0.6) -> void


## 停止当前正在播放的背景音乐。[br]
##
## [param fade] 淡出时长（秒，默认 0.6）。音乐将在指定时间内线性降低音量直至完全静音停止。
@abstract
func stop_bgm(fade: float = 0.6) -> void
#endregion


#region SFX Management
## 播放一次指定路径的短音效（从内部 SFX 播放池自动调度可用通道）。[br]
##
## [param path] 音效资源路径（[code]res://[/code] 开头）。[br]
## [param volume] 增益微调（分贝 dB，默认 0.0）。
@abstract
func play_sfx_by_path(path: String, volume: float = 0.0) -> void
#endregion


#region Bus & Channel Volume Controls
## 设置指定音频总线的音量大小（基于 0.0 ~ 1.0 的平滑线性标量）。[br]
##
## [param bus] 总线名称（如 "Master"、"Music"、"SFX"）。[br]
## [param linear] 线性音量值（0.0 表示完全静音，1.0 表示满音量）。系统内部自动转换为 dB 分贝。
@abstract
func set_bus_volume(bus: String, linear: float) -> void


## 获取指定音频总线的当前音量线性标量（0.0 ~ 1.0）。[br]
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


## 加载指定路径的音频资源流对象。[br]
##
## [param path] 音频路径。[br]
## @return 返回 [AudioStream] 实例。
@abstract
func load_audio(path: String) -> AudioStream
#endregion
