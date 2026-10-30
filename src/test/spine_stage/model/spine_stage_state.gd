class_name SpineStageState
extends RefCounted

## 2.5D「方案 B」舞台实时运行态快照（驱动 HUD 面板与换装高亮）。[br]
##
## [b]核心职责：[/b][br]
## 1. 记录当前激活的武器索引、服饰套装索引与 3D 舞台光照预设；[br]
## 2. 记录当前骨骼动作语义标签、连击命中数与累计伤害并在变更时发射 [signal state_changed]。

#region Signals
signal state_changed
#endregion

#region Public Properties
## 当前装备的武器索引（0=骑士剑, 1=死神镰, 2=符文锤）。
var weapon_index: int = 0

## 当前穿戴的服饰套装索引（0=翡翠游侠, 1=暗金铁卫, 2=深渊狂猎）。
var outfit_index: int = 1

## 当前 3D 场景光影模式（参见 [enum SpineStageConfig.LightingMode]）。
var lighting_mode: int = SpineStageConfig.LightingMode.DUSK_COURTYARD

## 当前主角 2D 骨骼状态展示文案。
var action_status_text: String = "IDLE · 待机呼吸"

## 累计命中木偶连击次数。
var combo_hits: int = 0

## 累计造成测试伤害总量。
var total_damage: int = 0
#endregion


#region Public API
## 触发状态变更广播，通知 [SpineStagePresenter] 刷新视图。
func notify_changed() -> void:
	state_changed.emit()
#endregion
