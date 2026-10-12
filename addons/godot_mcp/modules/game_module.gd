@tool
extends "res://addons/godot_mcp/modules/base_module.gd"

## 游戏运行时控制模块 (Game Module)
## 负责在编辑器中一键运行、停止游戏及查询运行态，实现 AI 自动化验证闭环。


func register_commands(registry: CommandRegistry) -> void:
	# 1. game.play_current
	registry.register_command(
		"game.play_current",
		"Play the currently active edited scene in the editor",
		{},
		_play_current_scene
	)
	registry.register_alias("play_current_scene", "game.play_current")

	# 2. game.play_main
	registry.register_command(
		"game.play_main",
		"Play the main project scene configured in project settings",
		{},
		_play_main_scene
	)
	registry.register_alias("play_main_scene", "game.play_main")

	# 3. game.stop
	registry.register_command(
		"game.stop",
		"Stop the currently running game instance",
		{},
		_stop_game
	)
	registry.register_alias("stop_game", "game.stop")

	# 4. game.status
	registry.register_command(
		"game.status",
		"Get running game status and current playing scene",
		{},
		_get_game_status
	)
	registry.register_alias("get_game_status", "game.status")


func _play_current_scene(_p: Dictionary) -> Variant:
	var iface := ctx.get_interface()
	if iface == null:
		return RpcError.execution_error("EditorInterface unavailable")

	iface.play_current_scene()
	return {"status": "started", "playing_scene": iface.get_playing_scene()}


func _play_main_scene(_p: Dictionary) -> Variant:
	var iface := ctx.get_interface()
	if iface == null:
		return RpcError.execution_error("EditorInterface unavailable")

	iface.play_main_scene()
	return {"status": "started", "playing_scene": iface.get_playing_scene()}


func _stop_game(_p: Dictionary) -> Variant:
	var iface := ctx.get_interface()
	if iface == null:
		return RpcError.execution_error("EditorInterface unavailable")

	if iface.is_playing_scene():
		iface.stop_playing_scene()
		return {"status": "stopped"}
	return {"status": "not_playing"}


func _get_game_status(_p: Dictionary) -> Variant:
	var iface := ctx.get_interface()
	if iface == null:
		return RpcError.execution_error("EditorInterface unavailable")

	return {
		"is_playing": iface.is_playing_scene(),
		"playing_scene": iface.get_playing_scene()
	}
