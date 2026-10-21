class_name GameSettingsService
extends RefCounted

## 全局游戏设置业务服务（位于 src/game/shared/service/settings/）。[br]
##
## [b]核心职责：[/b][br]
## 1. [b]单一权威运行时协调点[/b]：统一持有当前生效的 [GameSettingsModel]，供启动管线与各业务模块随时访问；[br]
## 2. [b]硬件与引擎子系统同步[/b]：将纯数据模型一键或分域同步至 [code]App.audio[/code]、[code]App.display[/code]、[code]App.haptic[/code]、[code]App.input[/code] 与 [code]App.locale[/code]；[br]
## 3. [b]画质档位与单项微调联动[/b]：切换预设档位时自动展开渲染管线参数；单独微调任一渲染参数时自动切入 [constant GameEnums.QualityPreset.CUSTOM]；[br]
## 4. [b]后台静音焦点联动[/b]：监听 [signal Bus.app_paused] 与 [signal Bus.app_resumed]，按 [member GameSettingsModel.mute_in_background] 裁决后台音频策略。

#region Constants & Static State
const _ERR_STORAGE_UNAVAILABLE: String = "Settings.StorageUnavailable"

static var _current: GameSettingsModel = null
static var _focus_listener_connected: bool = false
#endregion


#region 1. Lifecycle & Persistence
## 获取当前运行时生效的全局设置模型（若尚未初始化则惰性构建默认模型）。
static func get_current() -> GameSettingsModel:
	if _current == null:
		_current = GameSettingsModel.new().sanitize()
	return _current


## 从本地存储加载偏好设置并立即同步至全部底层硬件子系统（由 [BootstrapScene] 在启动首帧前调用）。
static func load_and_apply() -> Result:
	_ensure_focus_listener()

	var raw_settings: Dictionary = {}
	if App != null and App.storage != null:
		var item := GameSettingsModel.storage_item()
		App.storage.bind(item)
		var read_res: Result = await App.storage.read_async(item, StorageReadMode.LOCAL_ONLY)
		if read_res.is_ok() and read_res.value is Dictionary:
			raw_settings = read_res.value as Dictionary

	_current = GameSettingsModel.new(raw_settings).sanitize()
	apply_all(_current)
	_notify_settings_changed()
	return Result.ok(_current)


## 将当前设置模型持久化落盘至本地存储。
static func save_async() -> Result:
	if App == null or App.storage == null:
		return Result.err_code(_ERR_STORAGE_UNAVAILABLE, "Storage service is not available.")
	var model := get_current().sanitize()
	var item := GameSettingsModel.storage_item()
	App.storage.bind(item)
	return await App.storage.write_async(item, model.to_dict(), StorageWriteMode.LOCAL_ONLY)


## 恢复全部设置为出厂默认值，立即生效并按需落盘。
static func reset_to_defaults(auto_save: bool = true) -> GameSettingsModel:
	_current = GameSettingsModel.new().sanitize()
	apply_all(_current)
	_notify_settings_changed()
	if auto_save:
		save_async()
	return _current
#endregion


#region 2. Domain Hardware Synchronization
## 将指定设置模型（默认当前模型）全量同步至音频、显示、画质、输入、震动与多语言子系统。
static func apply_all(model: GameSettingsModel = null) -> void:
	var m := (model if model != null else get_current()).sanitize()
	apply_audio(m)
	apply_display(m)
	apply_graphics(m)
	apply_input_and_haptic(m)
	apply_locale(m)


## 同步音频设置至 App.audio（音量滑块与静音开关正交隔离，静音不丢失原滑块数值）。
static func apply_audio(model: GameSettingsModel = null) -> void:
	if App == null or App.audio == null:
		return
	var m := model if model != null else get_current()
	App.audio.set_bus_volume(BaseAudioSystem.BUS_MASTER, clampf(m.master_volume, 0.0, 1.0))
	App.audio.set_bus_volume(BaseAudioSystem.BUS_BGM, clampf(m.bgm_volume, 0.0, 1.0))
	App.audio.set_bus_volume(BaseAudioSystem.BUS_SFX, clampf(m.sfx_volume, 0.0, 1.0))
	App.audio.set_bus_mute(BaseAudioSystem.BUS_MASTER, m.master_muted)
	App.audio.set_music_enabled(m.music_enabled)
	App.audio.set_sfx_enabled(m.sfx_enabled)


## 同步窗口模式、分辨率、垂直同步与帧率上限至 App.display（底层内置状态幂等短路）。
static func apply_display(model: GameSettingsModel = null) -> void:
	if App == null or App.display == null:
		return
	var m := model if model != null else get_current()
	App.display.set_window_mode(m.window_mode as BaseDisplaySystem.WindowMode)
	if m.resolution_width > 0 and m.resolution_height > 0:
		App.display.set_resolution(Vector2i(m.resolution_width, m.resolution_height), true)
	var vsync := DisplayServer.VSYNC_ENABLED if m.vsync_enabled else DisplayServer.VSYNC_DISABLED
	App.display.set_vsync_mode(vsync)
	App.display.set_max_fps(maxi(0, m.max_fps))


## 同步视口渲染管线原语至 App.display 并广播画质变更事件。
static func apply_graphics(model: GameSettingsModel = null) -> void:
	var m := model if model != null else get_current()
	if App != null and App.display != null:
		App.display.set_msaa_2d(m.msaa_2d as Viewport.MSAA)
		App.display.set_msaa_3d(m.msaa_3d as Viewport.MSAA)
		App.display.set_screen_space_aa(m.screen_space_aa as Viewport.ScreenSpaceAA)
		App.display.set_scaling_3d_scale(m.render_scale)
		App.display.set_canvas_texture_filter(
			m.canvas_texture_filter as Viewport.DefaultCanvasItemTextureFilter
		)
	if Bus != null:
		Bus.emit(GameEvents.QUALITY_PRESET_CHANGED, {
			"preset": m.quality_preset,
			"render_scale": m.render_scale,
			"msaa_2d": m.msaa_2d,
			"msaa_3d": m.msaa_3d,
			"screen_space_aa": m.screen_space_aa,
		})


## 同步触感震动与手柄死区/自定义键位映射至 App.haptic 与 App.input。
static func apply_input_and_haptic(model: GameSettingsModel = null) -> void:
	var m := model if model != null else get_current()
	if App != null and App.haptic != null:
		App.haptic.set_enabled(m.haptic_enabled)
	if App != null and App.input != null:
		App.input.set_joy_deadzone(clampf(m.joy_deadzone, 0.05, 0.90))
		if not m.input_bindings.is_empty():
			App.input.import_bindings(m.input_bindings)


## 同步多语言区域配置至 App.locale。
static func apply_locale(model: GameSettingsModel = null) -> void:
	if App == null or App.locale == null:
		return
	var m := model if model != null else get_current()
	var normalized_tag := m.locale.replace("_", "-")
	var lang_idx := LocaleConfig.language_from_tag(normalized_tag)
	if lang_idx >= 0:
		App.locale.set_language(lang_idx as LocaleConfig.Language)
#endregion


#region 3. High-Level Mutators (Preset & Granular Controls)
## 切换全局画质预设档位（LOW / MEDIUM / HIGH / ULTRA），自动展开对应渲染参数并立即生效。
static func set_quality_preset(preset: int, auto_save: bool = true) -> void:
	var m := get_current()
	m.apply_quality_preset_values(preset)
	m.sanitize()
	apply_graphics(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 单独微调高级视口渲染参数（任意传入非负参数即更新，并自动将档位切换为 CUSTOM）。
static func set_custom_graphics(
	msaa_2d: int = -1,
	msaa_3d: int = -1,
	screen_space_aa: int = -1,
	render_scale: float = -1.0,
	canvas_texture_filter: int = -1,
	auto_save: bool = true
) -> void:
	var m := get_current()
	if msaa_2d >= 0:
		m.msaa_2d = msaa_2d
	if msaa_3d >= 0:
		m.msaa_3d = msaa_3d
	if screen_space_aa >= 0:
		m.screen_space_aa = screen_space_aa
	if render_scale > 0.0:
		m.render_scale = render_scale
	if canvas_texture_filter >= 0:
		m.canvas_texture_filter = canvas_texture_filter

	m.quality_preset = GameEnums.QualityPreset.CUSTOM
	m.sanitize()
	apply_graphics(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 更新音量滑块（拖动过程中可传 auto_save = false 实时听音，松手时再调用 save_async() 落盘）。
static func set_volumes(
	master: float = -1.0,
	bgm: float = -1.0,
	sfx: float = -1.0,
	auto_save: bool = false
) -> void:
	var m := get_current()
	if master >= 0.0:
		m.master_volume = clampf(master, 0.0, 1.0)
	if bgm >= 0.0:
		m.bgm_volume = clampf(bgm, 0.0, 1.0)
	if sfx >= 0.0:
		m.sfx_volume = clampf(sfx, 0.0, 1.0)
	apply_audio(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 更新窗口显示模式、分辨率、垂直同步与帧率上限。
static func set_window_and_resolution(
	window_mode: int,
	resolution: Vector2i = Vector2i.ZERO,
	vsync_enabled: bool = true,
	max_fps: int = 0,
	auto_save: bool = true
) -> void:
	var m := get_current()
	m.window_mode = window_mode
	if resolution.x > 0 and resolution.y > 0:
		m.resolution_width = resolution.x
		m.resolution_height = resolution.y
	m.vsync_enabled = vsync_enabled
	m.max_fps = maxi(0, max_fps)
	m.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()
#endregion


#region Internal Focus & Notification Helpers
static func _ensure_focus_listener() -> void:
	if _focus_listener_connected or Bus == null:
		return
	_focus_listener_connected = true
	if not Bus.app_paused.is_connected(_on_app_paused):
		Bus.app_paused.connect(_on_app_paused)
	if not Bus.app_resumed.is_connected(_on_app_resumed):
		Bus.app_resumed.connect(_on_app_resumed)


static func _on_app_paused() -> void:
	if App != null and App.audio != null:
		App.audio.set_paused(get_current().mute_in_background)


static func _on_app_resumed() -> void:
	if App != null and App.audio != null:
		App.audio.set_paused(false)


static func _notify_settings_changed() -> void:
	var m := get_current()
	m.notify_changed()
	if Bus != null:
		Bus.emit(GameEvents.SETTINGS_CHANGED, {"settings": m})
#endregion
