class_name GameEnums
extends RefCounted

## 跨模块共享业务枚举定义表（位于 src/game/shared/define/）。[br]
## 仅收纳被 2 个及以上垂直业务模块共同引用的通用枚举契约。

## 全局画质预设档位枚举
enum QualityPreset {
	LOW = 0,     ## 省电/低配流畅（0.75x 3D 渲染倍率，关闭抗锯齿）
	MEDIUM = 1,  ## 均衡标准（1.0x 渲染倍率，开启 FXAA 屏幕空间抗锯齿）
	HIGH = 2,    ## 高清画质（1.0x 渲染倍率，2X MSAA + FXAA）
	ULTRA = 3,   ## 极致画质（1.0x 渲染倍率，4X MSAA + SMAA）
	CUSTOM = 4,  ## 自定义微调（单独修改任一渲染管线参数后自动切入此档位）
}
