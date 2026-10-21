class_name InputContextType
extends RefCounted

## 输入上下文作用域枚举（Input Mapping Context Types）。[br]
##
## 采用栈式作用域（Context Stack）隔离不同游戏状态下的输入响应与改键冲突检测：[br]
## - 当栈顶为 [constant Context.UI] 或 [constant Context.REBIND] 时，底层 [constant Context.GAMEPLAY] 动作轮询自动挂起；[br]
## - 改键冲突检测仅在同一 Context 内部执行（如 Space 在 UI 下为确认、在 GAMEPLAY 下为冲刺，二者天然共存不冲突）。

enum Context {
	GAMEPLAY = 0, ## 局内战斗与角色控制层（默认栈底作用域）
	UI = 1,       ## 界面菜单与模态弹窗层（激活时屏蔽 GAMEPLAY 离散动作）
	SYSTEM = 2,   ## 系统级全局快捷键层（如截图、全屏切换、调试面板，不受 UI 弹窗屏蔽）
	REBIND = 3,   ## 交互式按键录制独占层（激活时吞没一切下层输入，防止按 ESC 误关弹窗）
}


## 判断指定上下文激活时是否应当阻塞 [constant Context.GAMEPLAY] 输入
static func blocks_gameplay(ctx: int) -> bool:
	return ctx == Context.UI or ctx == Context.REBIND


## 将上下文枚举转换为可读标识
static func to_string_name(ctx: int) -> StringName:
	match ctx:
		Context.GAMEPLAY:
			return &"GAMEPLAY"
		Context.UI:
			return &"UI"
		Context.SYSTEM:
			return &"SYSTEM"
		Context.REBIND:
			return &"REBIND"
		_:
			return &"UNKNOWN"
