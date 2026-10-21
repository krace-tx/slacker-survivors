class_name ApplySettingsStep
extends BaseBootStep

## 业务启动步骤 3：应用用户偏好设置与系统预热。


func get_step_name() -> String:
	return "应用系统偏好与音频预热"


func execute(context: BootContext) -> Result:
	var raw_settings: Dictionary = {}
	if App.storage != null:
		raw_settings = App.storage.get_dict(GameConstants.KEY_GAME_SETTINGS, {})

	var settings := GameSettingsModel.new(raw_settings)

	if App.audio != null:
		App.audio.set_bus_volume(GameConstants.BUS_MASTER, clampf(settings.master_volume, 0.0, 1.0))
		App.audio.set_bus_volume(GameConstants.BUS_BGM, clampf(settings.bgm_volume, 0.0, 1.0))
		App.audio.set_bus_volume(GameConstants.BUS_SFX, clampf(settings.sfx_volume, 0.0, 1.0))
		App.audio.set_music_enabled(settings.music_enabled)
		App.audio.set_sfx_enabled(settings.sfx_enabled)

	if App.haptic != null:
		App.haptic.set_enabled(settings.haptic_enabled)

	if App.input != null:
		App.input.set_joy_deadzone(clampf(settings.joy_deadzone, 0.05, 0.90))
		if not settings.input_bindings.is_empty():
			App.input.import_bindings(settings.input_bindings)

	if context != null:
		context.set_data("game_settings", settings)

	return Result.ok()
