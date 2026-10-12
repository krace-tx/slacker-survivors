class_name SceneTransitionType
extends RefCounted

## 场景流转过渡动画类型常量定义。
enum Type {
	AUTO,        ## 智能匹配（Push 进场淡入，Pop 溶解揭开，Replace 景深缩放）
	CROSS_PUSH,  ## 进场淡入覆盖 (0.0 -> 1.0)
	CROSS_POP,   ## 退场溶解揭开 (1.0 -> 0.0)
	DEPTH_ZOOM,  ## 景深弹性缩放 (0.96x -> 1.0x)
	NONE,        ## 瞬切（调试/无动画）
}

const AUTO = Type.AUTO
const CROSS_PUSH = Type.CROSS_PUSH
const CROSS_POP = Type.CROSS_POP
const DEPTH_ZOOM = Type.DEPTH_ZOOM
const NONE = Type.NONE
