class_name VideoPlaybackState
extends RefCounted

## 视频播放器运行状态机（Video Playback State Machine）。[br]
##
## 定义播放器完整生命周期阶段，并提供合法状态流转拓扑（State Transition Matrix）。[br]
## 状态机流转图如下：[br]
## [code]
## IDLE ──> OPENING ──> PLAYING <──> PAUSED
##   ^         │           │           │
##   │         │           ▼           │
##   └─────────┴─────> STOPPED <───────┘
##                     FINISHED
##                      ERROR
## [/code]

enum {
	## 空闲状态：尚未加载任何视频流或播放器已重置
	IDLE = 0,
	
	## 正在打开/装载视频资源与解析解码器
	OPENING = 1,
	
	## 视频正在正常解码并向前推进播放
	PLAYING = 2,
	
	## 视频播放已挂起/暂停，画面保持在当前帧
	PAUSED = 3,
	
	## 视频播放已主动停止，播放头已重置至开头
	STOPPED = 4,
	
	## 视频已自然播放至结尾完成（单次播放模式下）
	FINISHED = 5,
	
	## 视频在打开、解析或播放过程中遭遇异常故障
	ERROR = 6,
}

## 合法状态流转矩阵：定义每个状态允许跃迁的目标状态集合
const VALID_TRANSITIONS: Dictionary = {
	IDLE: [OPENING, ERROR],
	OPENING: [PLAYING, STOPPED, ERROR],
	PLAYING: [PAUSED, STOPPED, FINISHED, ERROR, OPENING],
	PAUSED: [PLAYING, STOPPED, ERROR, OPENING],
	STOPPED: [PLAYING, OPENING, IDLE, ERROR],
	FINISHED: [PLAYING, STOPPED, OPENING, IDLE, ERROR],
	ERROR: [OPENING, IDLE, STOPPED],
}


## 校验从 [param from_state] 跃迁至 [param to_state] 是否符合状态机图谱规范。
static func can_transition(from_state: int, to_state: int) -> bool:
	if from_state == to_state:
		return true
	if VALID_TRANSITIONS.has(from_state):
		var allowed: Array = VALID_TRANSITIONS[from_state]
		return to_state in allowed
	return true


## 查询指定状态是否属于活跃播放阶段（正在播放或处于暂停中）。
static func is_active(state: int) -> bool:
	return state == PLAYING or state == PAUSED


## 查询指定状态是否属于终止态（播放已结束、已停止、发生错误或处于初始空闲）。
static func is_terminal(state: int) -> bool:
	return state in [FINISHED, STOPPED, ERROR, IDLE]


## 将状态枚举转换为易读的英文字符串，便于日志记录与诊断排查。
static func to_string_name(state: int) -> String:
	match state:
		IDLE: return "IDLE"
		OPENING: return "OPENING"
		PLAYING: return "PLAYING"
		PAUSED: return "PAUSED"
		STOPPED: return "STOPPED"
		FINISHED: return "FINISHED"
		ERROR: return "ERROR"
		_: return "UNKNOWN(%d)" % state
