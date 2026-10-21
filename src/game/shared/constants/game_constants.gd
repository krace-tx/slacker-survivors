class_name GameConstants
extends RefCounted

## 游戏全局静态常量定义表。

#region Scene Paths
const SCENE_SPLASH: String = "res://src/game/bootstrap/scene/splash_scene.tscn"
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
