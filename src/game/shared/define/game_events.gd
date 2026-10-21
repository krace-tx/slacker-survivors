class_name GameEvents
extends RefCounted

## 游戏业务层跨模块领域事件常量集合（位于 src/game/shared/define/）。[br]
## 用于在模块与模块间解耦通讯（通过 [code]Bus.emit()[/code] 与 [code]Bus.on()[/code]）。

## 货币资产变动: {"gold": int, "delta": int}
const GOLD_CHANGED: StringName = &"game:gold_changed"

## 角色属性升级: {"talent_id": String, "level": int}
const TALENT_UPGRADED: StringName = &"game:talent_upgraded"

## 全局偏好设置已变更: {"settings": GameSettingsModel}
const SETTINGS_CHANGED: StringName = &"game:settings_changed"

## 画质档位或视觉密度已变更: {"preset": int, "particle_density": float, "damage_number_mode": int}
const QUALITY_PRESET_CHANGED: StringName = &"game:quality_preset_changed"

## 关卡战斗开始: {"stage_id": String, "difficulty": int}
const BATTLE_STARTED: StringName = &"game:battle_started"

## 关卡战斗胜利或失败结算: {"is_victory": bool, "survived_time": float, "kills": int, "rewards": Dictionary}
const BATTLE_FINISHED: StringName = &"game:battle_finished"

## 局内角色升级触发展示选卡: {"current_level": int, "choices": Array}
const BATTLE_LEVEL_UP: StringName = &"game:battle_level_up"

## 游戏业务层启动与状态加载完毕
const BOOTSTRAP_COMPLETED: StringName = &"game:bootstrap_completed"
