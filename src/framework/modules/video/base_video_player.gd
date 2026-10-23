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
@warning_ignore("unused_signal")
signal opened(file_path: String, duration: float)

## 当播放器内部状态发生改变时触发。[br]
## [param new_state] 改变后的新状态（见 [VideoPlaybackState]）。[br]
## [param old_state] 改变前的旧状态。
@warning_ignore("unused_signal")
signal state_changed(new_state: int, old_state: int)

## 当视频自然播放至结尾时触发（单次播放模式下）。
@warning_ignore("unused_signal")
signal playback_finished()

## 当当前打开的视频流成功解码并锁存第一帧有效画面纹理时触发（用于消除首帧黑屏闪烁）。
@warning_ignore("unused_signal")
signal first_frame_ready()

## 当指定视频的 512KB 文件头（moov）异步预热与首帧挂起准备完成时触发。[br]
## [param file_path] 完成预热的标准化视频路径。[br]
## [param success] 预热任务是否成功完成。
@warning_ignore("unused_signal")
signal prewarm_completed(file_path: String, success: bool)

## 当打开视频或播放过程中出现异常故障时触发。[br]
## [param error_code] 标准化错误码（见 [VideoError]，如 [constant VideoError.FILE_NOT_FOUND]）。[br]
## [param message] 详尽的错误诊断说明。
@warning_ignore("unused_signal")
signal error_occurred(error_code: String, message: String)
#endregion


#region Playback Control Methods
## 异步预热指定的视频资源（512KB [code]moov[/code] 头 OS PageCache 预读 + 可选首帧解码挂起）。[br]
## - 后台线程自动预读文件头部 512KB（移动端同步提前完成 [code]user://cache/video[/code] 实体化），消除起播磁盘 I/O 尖峰；[br]
## - 桌面端在播放器空闲时可将流置于静音首帧挂起态（Standby），使随后的 [method open] 或 [method play_cutscene] 达到 0ms 瞬时响应。[br]
##
## [param file_path] 视频文件路径（支持 [code]res://[/code] 或本地绝对路径）。[br]
## [param standby_first_frame] 是否在播放器空闲时预挂载解码流并锁存首帧画面。默认为 true。[br]
## @return 返回 [Result] 对象。启动预热成功时为 ok，路径非法或文件缺失时返回对应 [VideoError]。
@abstract
func prewarm(file_path: String, standby_first_frame: bool = true) -> Result


## 打开并准备指定的视频资源。[br]
##
## [param file_path] 视频文件路径（支持 [code]res://[/code] 或本地绝对路径）。[br]
## [param options] 播放行为配置项，为 null 时采用默认配置。[br]
## @return 返回 [Result] 对象。成功时包含有效状态，失败时携带 [VideoError] 标准错误码。
@abstract
func open(file_path: String, options: VideoPlayOptions = null) -> Result


## 播放剧情/片头 CG 视频并异步等待播放完成（无内置 UI 耦合的跨端一体化协程接口）。[br]
## 针对当前运行环境进行智能路由调度：[br]
## - 移动端（Android / iOS）：在原生插件可用时唤起系统硬件播放器；[br]
## - 桌面端（Windows / macOS / Linux）：驱动当前已绑定或传入的 [param target]（[TextureRect]）渲染画面（首帧就绪自动揭幕，业务层可通过自建跳过按钮调用 [method stop] 提前结束）；[br]
## - 全局联动：自动完成 BGM 避让、生命周期等待并在结束或被跳过时自动恢复 BGM 并返回 [Result]。[br]
##
## [param file_path] 视频文件路径。[br]
## [param options] 播放配置项。[br]
## [param target] 可选，桌面端用于呈现视频画面的业务层 [TextureRect] 节点（播放结束后自动解绑清空）。[br]
## @return 播放完成或被调用 [method stop] 跳过后返回 [Result]。
@abstract
func play_cutscene(
	file_path: String,
	options: VideoPlayOptions = null,
	target: TextureRect = null
) -> Result


## 将业务层场景中的 [TextureRect] 绑定为当前视频画面的显示目标（弱引用持有，零内存泄漏）。[br]
## - 绑定后，当解码器锁存第一帧有效画面（[signal first_frame_ready]）时自动将纹理赋给 [param target] 并恢复不透明度；[br]
## - 当调用 [method stop] 或切换新视频流时自动清空 [param target] 的纹理，彻底消除首帧闪黑与旧视频尾帧残留。[br]
##
## [param target] 业务视图（[code].tscn[/code]）中的 [TextureRect] 实例。[br]
## [param hide_until_first_frame] 在首帧有效纹理解码完成前是否将 [param target] 透明度置为 0.0。默认为 true。
@abstract
func bind_display(target: TextureRect, hide_until_first_frame: bool = true) -> void


## 解除业务层 [TextureRect] 的视频画面绑定并清空其纹理引用。[br]
##
## [param target] 可选，仅当当前绑定目标等于 [param target] 时解绑；传 null 时无条件解绑当前目标。
@abstract
func unbind_display(target: TextureRect = null) -> void


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


## 查询当前打开的视频流是否已成功解码并锁存第一帧有效画面纹理。
@abstract
func is_first_frame_ready() -> bool


## 查询指定路径的视频资源是否已完成 512KB 文件头预热或处于首帧挂起就绪态。
@abstract
func is_prewarmed(file_path: String) -> bool


## 清理沙盒视频实体化缓存（[code]user://cache/video[/code]）与内存预热流缓存（正在播放中的活动文件除外）。
@abstract
func clear_cache() -> Result


## 获取当前沙盒视频缓存目录（[code]user://cache/video[/code]）占用的总字节数。
@abstract
func get_cache_size_bytes() -> int
#endregion
