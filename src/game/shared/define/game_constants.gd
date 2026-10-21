class_name GameConstants
extends RefCounted

## 游戏全局静态常量定义表（位于 src/game/shared/define/）。[br]
## 仅存放跨 2 个及以上模块共享的编译期静态常量（存储 Key、音频总线名等）。[br]
## 路由级场景路径统一直接使用自动生成的 [GameScenes]（位于 [code]src/game/shared/define/generated/game_scenes.gd[/code]），严禁在此二次别名。

#region Storage Keys
const KEY_GAME_SETTINGS: StringName = &"game_settings"
const KEY_PLAYER_PROFILE: StringName = &"player_profile"
#endregion

#region Audio Buses
const BUS_MASTER: StringName = &"Master"
const BUS_BGM: StringName = &"BGM"
const BUS_SFX: StringName = &"SFX"
#endregion
