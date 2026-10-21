class_name InputConflictPolicy
extends RefCounted

## 改键冲突裁决策略枚举（Input Rebind Conflict Policy）。[br]
##
## 当玩家将某个单键或组合键绑定到目标动作时，若同一 [InputContextType] 作用域与同一设备轨道下的另一可改键动作已占用该按键，按此策略裁决。

enum Policy {
	SWAP = 0,           ## 无感互换（默认推荐）：将原动作槽位与被冲突动作槽位的按键对调，体验最连贯
	REJECT = 1,         ## 严格拒绝：返回 InputError.BINDING_CONFLICT 错误并携带冲突动作名，不修改原绑定
	CLEAR_EXISTING = 2, ## 覆盖清空：强制绑定到新动作，并将原冲突动作的对应槽位置空
	ALLOW = 3,          ## 允许共存：不做冲突拦截，允许同一按键同时驱动多个同域动作
}
