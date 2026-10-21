class_name GameEvents
extends RefCounted

## 游戏业务层跨模块领域事件常量集合（位于 src/game/shared/define/）。[br]
## 用于在垂直模块间通过 [code]Bus.emit()[/code] 与 [code]Bus.on_scoped()[/code] 解耦通讯。

## 业务启动管线全部加载完毕: {"total_boot_ms": int, "is_first_launch": bool, "is_offline_mode": bool, "target_scene_path": String, "tasks_ms": Dictionary, "warnings": Array[String]}
const BOOTSTRAP_COMPLETED: StringName = &"game:bootstrap_completed"

## 全局偏好设置已变更: {"settings": GameSettingsModel}
const SETTINGS_CHANGED: StringName = &"game:settings_changed"

## 全局画质预设档位或视口渲染管线已变更: {"preset": int, "render_scale": float, "msaa_2d": int, "msaa_3d": int, "screen_space_aa": int}
const QUALITY_PRESET_CHANGED: StringName = &"game:quality_preset_changed"

## 玩家全局档案数据已更新: {"profile": PlayerProfileModel}
const PROFILE_UPDATED: StringName = &"game:profile_updated"
