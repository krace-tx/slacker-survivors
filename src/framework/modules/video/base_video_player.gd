@abstract
class_name BaseVideoPlayer
extends Node

## 视频播放器门面契约接口（Video Player Facade Contract）。[br]
##
## 本抽象基类作为业务层与 UI 层控制视频播放的统一规范入口，核心职责：[br]
## - [b]极简纯粹的播放控制[/b]：[method open]、[method play]、[method pause]、[method stop]、[method seek]；[br]
## - [b]全平台过场管线[/b]：[method play_cutscene] 提供一体化剧情 CG 播放与跳过调度；[br]
## - [b]状态与生命周期驱动[/b]：提供基于 [VideoPlaybackState] 的完整状态机迁移通知；[br]
## - [b]画面纹理输出[/b]：通过 [method get_video_texture] 暴露当前解码帧，支持 UI（[TextureRect]）或 3D 材质渲染；[br]
## - [b]音画避让协同[/b]：与 [BaseAudioSystem] 联动，视频播放期间自动淡出避让游戏 BGM；[br]
## - [b]底层适配器隔离[/b]：透明桥接 [code]addons/ffmpeg[/code]、移动端原生插件与引擎内置软解。[br]
##
## 业务代码应统一通过 [code]App.video[/code] 访问本契约提供的方法。

#region Signals
## 当视频资源成功打开并装载就绪时触发。[br]
## [param file_path] 打开的视频资源路径。[br]
## [param duration] 视频总时长（秒，若为未知或流媒体则返回 -1.0）。
signal opened(file_path: String, duration: float)

## 当播放器内部状态发生改变时触发。[br]
## [param new_state] 改变后的新状态（见 [VideoPlaybackState]）。[br]
## [param old_state] 改变前的旧状态。
signal state_changed(new_state: int, old_state: int)

## 当视频自然播放至结尾时触发（单次播放模式下）。
signal playback_finished()

## 当打开视频或播放过程中出现异常故障时触发。[br]
## [param error_code] 标准化错误码（见 [VideoError]，如 [constant VideoError.FILE_NOT_FOUND]）。[br]
## [param message] 详尽的错误诊断说明。
signal error_occurred(error_code: String, message: String)
#endregion


#region Playback Control Methods
## 打开并准备指定的视频资源。[br]
##
## [param file_path] 视频文件路径（支持 [code]res://[/code] 或本地绝对路径）。[br]
## [param options] 播放行为配置项，为 null 时采用默认配置。[br]
## @return 返回 [Result] 对象。成功时包含有效状态，失败时携带 [VideoError] 标准错误码。
@abstract
func open(file_path: String, options: VideoPlayOptions = null) -> Result


## 播放全屏剧情/片头 CG 视频（全平台一体化便捷接口）。[br]
## 针对当前运行环境进行智能路由调度：[br]
## - 移动端（Android / iOS）：在原生插件可用时唤起系统播放器；[br]
## - 桌面端（Windows / macOS / Linux）：在顶层画幅上渲染播放，并支持跳过交互；[br]
## - 全局联动：自动完成 BGM 避让、生命周期等待并在结束时返回 [Result]。[br]
##
## [param file_path] 视频文件路径。[br]
## [param options] 播放配置项。[br]
## @return 播放完成或跳过后返回 [Result]。
@abstract
func play_cutscene(file_path: String, options: VideoPlayOptions = null) -> Result


## 开始或恢复播放当前已打开的视频流。
@abstract
func play() -> void


## 暂停当前正在播放的视频流。
@abstract
func pause() -> void


## 恢复暂停中的视频流。
@abstract
func resume() -> void


## 停止播放当前视频流，将播放头重置回开头并恢复之前避让的 BGM。
@abstract
func stop() -> void


## 跳转播放进度至指定的绝对秒数。[br]
##
## [param seconds] 目标时间偏移（秒）。
@abstract
func seek(seconds: float) -> void


## 设置当前视频流的音量大小。[br]
##
## [param linear_volume] 线性音量标量（0.0 表示静音，1.0 表示原声音量）。
@abstract
func set_volume(linear_volume: float) -> void


## 获取当前视频流的线性音量标量（0.0 ~ 1.0）。
@abstract
func get_volume() -> float


## 设置当前视频流是否循环播放。[br]
##
## [param loop] 是否开启循环。
@abstract
func set_looping(loop: bool) -> void


## 查询当前视频是否开启了循环播放。
@abstract
func is_looping() -> bool
#endregion


#region State & Query Methods
## 获取播放器当前的生命周期状态（对应 [VideoPlaybackState] 枚举值）。
@abstract
func get_state() -> int


## 查询当前视频流是否正在正常播放中。
@abstract
func is_playing() -> bool


## 查询当前视频流是否处于暂停状态。
@abstract
func is_paused() -> bool


## 获取当前打开的视频总时长（秒）。[br]
## @return 浮点数秒数；若未打开视频或格式不支持获取时长，则返回 -1.0。
@abstract
func get_duration() -> float


## 获取当前播放进度的已流逝时间（秒）。
@abstract
func get_playback_position() -> float


## 获取当前渲染的视频帧纹理对象。[br]
## 业务层可将该纹理直接赋值给 [TextureRect] 或 3D 材质作为动态画面输出。[br]
## @return [Texture2D] 纹理实例；若未打开或尚未解出第一帧，返回 null。
@abstract
func get_video_texture() -> Texture2D


## 获取当前正在播放/已打开的视频文件路径。未打开任何视频时返回空字符串。
@abstract
func get_current_file() -> String


## 获取当前底层实际生效的解码适配器名称（如 "FFmpeg (GDExtension)" 或 "Godot Engine Native"）。
@abstract
func get_active_adapter_name() -> String


## 获取当前生效的视频底层驱动类型（见 [VideoBackendType] 枚举）。
@abstract
func get_backend_type() -> int
#endregion
