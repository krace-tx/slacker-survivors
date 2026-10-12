class_name VideoBackendType
extends RefCounted

## 视频播放底层驱动类型枚举。[br]
## 标识当前环境所采用的跨平台播放内核。

enum {
	## 智能推导：根据当前运行操作系统与已加载插件自动选择最优后端
	AUTO = 0,
	
	## 开源专业插件后端：基于 GDExtension FFmpeg (Windows / macOS / Linux / Android)
	ADDON_FFMPEG = 1,
	
	## 移动端原生硬件后端：基于 Android ExoPlayer / iOS AVPlayer 原生插件
	NATIVE_MOBILE = 2,
	
	## 引擎内置软解后端：基于 Godot 原生 VideoStreamTheora (全平台免插件兜底)
	ENGINE_THEORA = 3,
}


static func to_string_name(backend_type: int) -> String:
	match backend_type:
		AUTO: return "AUTO"
		ADDON_FFMPEG: return "ADDON_FFMPEG"
		NATIVE_MOBILE: return "NATIVE_MOBILE"
		ENGINE_THEORA: return "ENGINE_THEORA"
		_: return "UNKNOWN"
