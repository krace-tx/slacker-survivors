class_name VideoBackendType
extends RefCounted

## 视频播放底层驱动架构分类（Video Backend Architecture Types）。[br]
##
## 标识当前运行环境生效的跨平台底层解码核心与适配驱动。

enum {
	## 智能自动推导：根据当前宿主操作系统与 ClassDB 插件注册表自动选择最优解
	AUTO = 0,
	
	## 开源专业插件后端：基于 GDExtension FFmpeg（Windows / macOS / Linux / 通用桌面）
	ADDON_FFMPEG = 1,
	
	## 移动端原生硬件后端：基于 Android ExoPlayer / iOS AVPlayer 原生插件系统
	NATIVE_MOBILE = 2,
	
	## 引擎内置软解保底：基于 Godot 原生 VideoStreamTheora（全平台零依赖安全降级）
	ENGINE_THEORA = 3,
}


## 将驱动枚举转换为易读的字符串名称，方便日志与状态诊断。
static func to_string_name(backend_type: int) -> String:
	match backend_type:
		AUTO: return "AUTO"
		ADDON_FFMPEG: return "ADDON_FFMPEG"
		NATIVE_MOBILE: return "NATIVE_MOBILE"
		ENGINE_THEORA: return "ENGINE_THEORA"
		_: return "UNKNOWN(%d)" % backend_type
