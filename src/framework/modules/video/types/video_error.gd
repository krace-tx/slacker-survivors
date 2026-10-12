class_name VideoError
extends RefCounted

## 视频模块标准化错误码定义（Video Module Standard Error Codes）。[br]
##
## 本命名空间收录视频子系统在打开、解码、播放与跨平台调度过程中可能触发的所有标准错误码。[br]
## 严格遵循框架统一的 [code]{Module}.{Reason}[/code] 契约规范，配合 [FrameworkError] 与 [Result] 使用。

## 传入的视频文件路径为空字符串
const EMPTY_PATH: String = "Video.EmptyPath"

## 指定路径的视频资源文件不存在或不可访问（含本地路径与 res:// 虚拟路径）
const FILE_NOT_FOUND: String = "Video.FileNotFound"

## 视频编码/容器格式不受支持（例如引擎原生软解环境尝试解析 MP4/H.264）
const CODEC_UNSUPPORTED: String = "Video.CodecUnsupported"

## 没有匹配的底层适配器可用于处理该视频格式
const NO_COMPATIBLE_ADAPTER: String = "Video.NoCompatibleAdapter"

## 缺少开源扩展插件（如未安装或未加载 addons/ffmpeg/ GDExtension 插件）
const ADDON_NOT_INSTALLED: String = "Video.AddonNotInstalled"

## 视频流资源对象（VideoStream）通过 ClassDB 反射实例化失败
const INSTANTIATION_FAILED: String = "Video.InstantiationFailed"

## 引擎原生内置流类缺失（如当前导出模板未启用 VideoStreamTheora）
const ENGINE_STREAM_MISSING: String = "Video.EngineStreamMissing"

## 移动端原生硬件播放插件不可用或未载入系统单例（Android / iOS）
const NATIVE_PLUGIN_UNAVAILABLE: String = "Video.NativePluginUnavailable"

## 移动端原生插件未实现对应的播放控制接口
const METHOD_NOT_FOUND: String = "Video.MethodNotFound"

## 移动端原生播放过程中发生异常（如解码崩溃、格式损坏或网络流中断）
const NATIVE_PLAYBACK_FAILED: String = "Video.NativePlaybackFailed"

## 适配器未实现具体的视频流创建逻辑
const NOT_IMPLEMENTED: String = "Video.NotImplemented"

## 通用播放或调度异常
const PLAYBACK_FAILED: String = "Video.PlaybackFailed"
