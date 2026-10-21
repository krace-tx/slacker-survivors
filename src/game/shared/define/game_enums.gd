class_name GameEnums
extends RefCounted

## 跨模块共享业务枚举定义表（位于 src/game/shared/define/）。[br]
## 仅收纳被 2 个及以上垂直业务模块共同引用的枚举契约。

## 全局画质预设档位枚举
enum QualityPreset {
	LOW = 0,     ## 省电/低配流畅（0.75x 渲染倍率，关闭抗锯齿，低粒子密度，仅暴击飘字）
	MEDIUM = 1,  ## 均衡标准（1.0x 渲染倍率，开启 FXAA，中等粒子密度，全部飘字）
	HIGH = 2,    ## 高清画质（1.0x 渲染倍率，2X MSAA + FXAA，100% 粒子密度，全部飘字）
	ULTRA = 3,   ## 极致画质（1.0x 渲染倍率，4X MSAA + SMAA，100% 粒子密度，全部飘字）
	CUSTOM = 4,  ## 自定义微调（玩家单独修改某项高级渲染参数后自动切入此档位）
}

## 战斗伤害飘字显示密度模式
enum DamageNumberMode {
	OFF = 0,            ## 完全关闭伤害飘字（割草后期极限稳帧/清爽视野）
	CRITICAL_ONLY = 1,  ## 仅显示暴击与高额关键伤害
	ALL = 2,            ## 显示全部伤害飘字
}
