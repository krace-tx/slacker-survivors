class_name VideoPlaybackState
extends RefCounted

## 视频播放器运行状态命名空间。[br]
## 描述当前播放器实例处于的生命周期阶段。

enum {
	## 空闲状态：尚未加载任何视频流
	IDLE = 0,
	
	## 正在打开/装载视频资源与解码器缓冲
	OPENING = 1,
	
	## 正在正常播放视频
	PLAYING = 2,
	
	## 播放已暂停
	PAUSED = 3,
	
	## 播放已主动停止，进度重置至开头
	STOPPED = 4,
	
	## 视频自然播放至结尾完成
	FINISHED = 5,
	
	## 播放过程中出现解码异常或文件缺失
	ERROR = 6,
}


## 将状态枚举转换为易读的字符串名称，方便日志与调试排查。
static func to_string_name(state: int) -> String:
	match state:
		IDLE: return "IDLE"
		OPENING: return "OPENING"
		PLAYING: return "PLAYING"
		PAUSED: return "PAUSED"
		STOPPED: return "STOPPED"
		FINISHED: return "FINISHED"
		ERROR: return "ERROR"
		_: return "UNKNOWN"
