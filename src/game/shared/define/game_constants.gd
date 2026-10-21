class_name GameConstants
extends RefCounted

## 游戏全局静态常量定义表（位于 src/game/shared/define/）。[br]
## 仅存放跨 2 个及以上模块共享的编译期静态常量（存储 Key、音频总线名等）。[br]
## 路由级场景路径由插件自动注入至 [GameScenes]（位于 [code]src/game/shared/define/generated/game_scenes.gd[/code]）。

#region Scene Route Aliases (Delegated to Auto-Generated GameScenes)
const SCENE_BOOTSTRAP: String = GameScenes.Scene.BOOTSTRAP
const SCENE_SPLASH: String = GameScenes.Scene.SPLASH
const SCENE_LOBBY: String = GameScenes.Scene.LOBBY
const SCENE_BATTLE: String = GameScenes.Scene.BATTLE
#endregion

#region Storage Keys
const KEY_PLAYER_DATA: String = "player_data"
const KEY_GAME_SETTINGS: String = "game_settings"
const KEY_RUN_SAVE: String = "current_run_save"
#endregion

#region Audio Groups
const BUS_MASTER: StringName = &"Master"
const BUS_BGM: StringName = &"BGM"
const BUS_SFX: StringName = &"SFX"
#endregion
