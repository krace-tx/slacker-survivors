class_name AuthState
extends RefCounted

## 认证系统生命周期状态机定义与流转守卫（Authentication State Machine）。

enum {
	UNAUTHENTICATED = 0, ## 初始未登录或已主动登出状态
	AUTHENTICATING = 1,  ## 正在向平台 SDK 取证或向后端网关换票中
	AUTHENTICATED = 2,   ## 已完成在线平台认证或网关验签
	OFFLINE = 3,         ## 处于离线会话模式（Steam 离线模式或本地设备游客模式）
	ERROR = 4,           ## 最近一次认证尝试发生不可降级错误
}

const VALID_TRANSITIONS: Dictionary = {
	UNAUTHENTICATED: [AUTHENTICATING, AUTHENTICATED, OFFLINE, ERROR],
	AUTHENTICATING:  [AUTHENTICATED, OFFLINE, ERROR, UNAUTHENTICATED],
	AUTHENTICATED:   [AUTHENTICATING, OFFLINE, UNAUTHENTICATED, ERROR],
	OFFLINE:         [AUTHENTICATING, AUTHENTICATED, UNAUTHENTICATED, ERROR],
	ERROR:           [AUTHENTICATING, AUTHENTICATED, OFFLINE, UNAUTHENTICATED],
}


static func can_transition(from_state: int, to_state: int) -> bool:
	if from_state == to_state:
		return true
	var allowed: Array = VALID_TRANSITIONS.get(from_state, [])
	return to_state in allowed


static func is_logged_in(state: int) -> bool:
	return state == AUTHENTICATED or state == OFFLINE


static func to_string_name(state: int) -> StringName:
	match state:
		UNAUTHENTICATED: return &"UNAUTHENTICATED"
		AUTHENTICATING:  return &"AUTHENTICATING"
		AUTHENTICATED:   return &"AUTHENTICATED"
		OFFLINE:         return &"OFFLINE"
		ERROR:           return &"ERROR"
		_:               return &"UNKNOWN"
