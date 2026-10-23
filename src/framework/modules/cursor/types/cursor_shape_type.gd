class_name CursorShapeType
extends RefCounted

## 语义化鼠标光标形状枚举与引擎映射契约（Semantic Cursor Shape Contract）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一定义跨项目通用的 11 种语义光标类型（覆盖常规 UI、拖拽、战斗准星、锁定攻击、场景交互、观察与等待）；[br]
## 2. 提供与 Godot 原生 [enum DisplayServer.CursorShape] 及 [enum Control.CursorShape] 的双向映射；[br]
## 3. 定义按压态（Left Mouse Pressed）自动形变配对关系（如 [constant Shape.GRAB] 按下自动变为 [constant Shape.GRABBED]）。

#region Shape Enum
enum Shape {
	DEFAULT = 0,   ## 默认标准箭头（主菜单、大厅、弹窗空白处）
	POINTER = 1,   ## 可点击手型（悬停于可用按钮、页签、超链接）
	FORBIDDEN = 2, ## 禁用/不可操作（悬停于 disabled 按钮或冷却锁死槽位）
	GRAB = 3,      ## 可抓取/张开手（悬停于可拖拽卡牌、装备格、可平移画布）
	GRABBED = 4,   ## 抓取中/握紧手（正在按住拖拽物品或平移视野）
	CROSSHAIR = 5, ## 战斗瞄准准星（局内射击/割草战斗默认状态）
	ATTACK = 6,    ## 锁定攻击目标（悬停于可攻击敌人、Boss 弱点、可破坏物）
	INTERACT = 7,  ## 场景交互/对话（悬停于 NPC、宝箱、饮水机、传送门）
	INSPECT = 8,   ## 观察/查看详情（悬停于掉落物、线索、图鉴细节）
	IBEAM = 9,     ## 文本输入光标（悬停于 LineEdit / TextEdit 输入框）
	WAIT = 10,     ## 忙碌等待光标（网络请求或同步事务期间强锁）
	HELP = 8,      ## 语义别名：帮助/查看提示（同 INSPECT）
	ZOOM_IN = 8,   ## 语义别名：放大检视（同 INSPECT）
	ZOOM_OUT = 8,  ## 语义别名：缩小检视（同 INSPECT）
}

## 全部合法语义光标形状列表
const ALL_SHAPES: Array[int] = [
	Shape.DEFAULT,
	Shape.POINTER,
	Shape.FORBIDDEN,
	Shape.GRAB,
	Shape.GRABBED,
	Shape.CROSSHAIR,
	Shape.ATTACK,
	Shape.INTERACT,
	Shape.INSPECT,
	Shape.IBEAM,
	Shape.WAIT,
]
#endregion


#region Conversion & Pairing Helpers
## 将光标形状枚举转换为可读的 [StringName] 标识。
static func to_string_name(shape: int) -> StringName:
	match shape:
		Shape.DEFAULT: return &"DEFAULT"
		Shape.POINTER: return &"POINTER"
		Shape.FORBIDDEN: return &"FORBIDDEN"
		Shape.GRAB: return &"GRAB"
		Shape.GRABBED: return &"GRABBED"
		Shape.CROSSHAIR: return &"CROSSHAIR"
		Shape.ATTACK: return &"ATTACK"
		Shape.INTERACT: return &"INTERACT"
		Shape.INSPECT: return &"INSPECT"
		Shape.IBEAM: return &"IBEAM"
		Shape.WAIT: return &"WAIT"
		_: return &"DEFAULT"


## 获取当鼠标左键按住时该光标形状自动演变的配对形状（如 GRAB -> GRABBED）。
static func get_pressed_counterpart(shape: int) -> int:
	if shape == Shape.GRAB:
		return Shape.GRABBED
	return shape


## 将语义光标形状映射为 Godot 底层 [enum DisplayServer.CursorShape]。
static func to_display_server_shape(shape: int) -> DisplayServer.CursorShape:
	match shape:
		Shape.POINTER, Shape.INTERACT:
			return DisplayServer.CURSOR_POINTING_HAND
		Shape.FORBIDDEN:
			return DisplayServer.CURSOR_FORBIDDEN
		Shape.GRAB:
			return DisplayServer.CURSOR_CAN_DROP
		Shape.GRABBED:
			return DisplayServer.CURSOR_DRAG
		Shape.CROSSHAIR, Shape.ATTACK:
			return DisplayServer.CURSOR_CROSS
		Shape.INSPECT:
			return DisplayServer.CURSOR_HELP
		Shape.IBEAM:
			return DisplayServer.CURSOR_IBEAM
		Shape.WAIT:
			return DisplayServer.CURSOR_WAIT
		_:
			return DisplayServer.CURSOR_ARROW


## 将 UI 控件的 [enum Control.CursorShape] 映射为语义光标形状。
static func from_control_cursor_shape(ctrl_shape: Control.CursorShape) -> int:
	match ctrl_shape:
		Control.CURSOR_POINTING_HAND:
			return Shape.POINTER
		Control.CURSOR_FORBIDDEN:
			return Shape.FORBIDDEN
		Control.CURSOR_CAN_DROP:
			return Shape.GRAB
		Control.CURSOR_DRAG, Control.CURSOR_MOVE:
			return Shape.GRABBED
		Control.CURSOR_CROSS:
			return Shape.CROSSHAIR
		Control.CURSOR_HELP:
			return Shape.INSPECT
		Control.CURSOR_IBEAM:
			return Shape.IBEAM
		Control.CURSOR_WAIT, Control.CURSOR_BUSY:
			return Shape.WAIT
		_:
			return Shape.DEFAULT
#endregion
