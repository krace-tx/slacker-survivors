class_name GameSettingsService
extends RefCounted

## 全局游戏设置业务服务内核（位于 src/game/shared/service/settings/）。[br]
##
## [b]跨项目通用设计（UI 无关内核）：[/b][br]
## 1. [b]五大领域分组协调[/b]：统一持有 [GameSettingsModel]（内含 `display / graphics / audio / control / general` 五大子组），支持全量或按分组独立重置；[br]
## 2. [b]切屏事务快照与 15 秒回滚内核[/b]：通过 `display.clone()` 一键快照窗口模式、显示器与分辨率，超时或取消时无损回滚；[br]
## 3. [b]画质预设与单项微调双向联动[/b]：切换预设档位自动展开渲染参数，微调任一细分项自动切入 [constant GraphicsSettingsData.QualityPreset.CUSTOM]；[br]
## 4. [b]后台失焦省电与静音联动[/b]：监听 [signal Bus.app_paused] 与 [signal Bus.app_resumed]，自动执行后台静音与后台降帧（`background_max_fps`）。


#region 1. 跨项目通用预设梯度常量与静态状态

const _ERR_STORAGE_UNAVAILABLE: String = "Settings.StorageUnavailable"

## 全局偏好设置已变更事件: {"settings": GameSettingsModel}
const EVENT_SETTINGS_CHANGED: StringName = &"game:settings_changed"

## 全局画质预设档位或视口渲染管线已变更事件: {"preset": int, "render_scale": float, "msaa_2d": int, "msaa_3d": int, "screen_space_aa": int, "effect_quality": float, "shadow_quality": int}
const EVENT_QUALITY_PRESET_CHANGED: StringName = &"game:quality_preset_changed"

## 标准帧率上限梯度（0 表示无限制）
const FPS_PRESETS: Array[int] = [30, 60, 120, 144, 0]

## 标准 3D 渲染分辨率倍率梯度
const RENDER_SCALE_PRESETS: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5]

## 标准 HUD 边界安全区缩放梯度
const SAFE_AREA_SCALE_PRESETS: Array[float] = [1.0, 0.95, 0.90, 0.85]

static var _current: GameSettingsModel = null
static var _focus_listener_connected: bool = false
static var _display_snapshot: DisplaySettingsData = null

#endregion


#region 2. 生命周期、持久化与分组重置 (Lifecycle, Persistence & Category Reset)

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


## 将当前设置模型持久化落盘至本地存储（供滑块松手 drag_ended 或设置项变更时调用）。
static func save_async() -> Result:
	if App == null or App.storage == null:
		return Result.err_code(_ERR_STORAGE_UNAVAILABLE, "Storage service is not available.")
	var model := get_current().sanitize()
	var item := GameSettingsModel.storage_item()
	App.storage.bind(item)
	return await App.storage.write_async(item, model.to_dict(), StorageWriteMode.LOCAL_ONLY)


## 恢复全部五大分组设置为出厂默认值，立即生效并按需落盘。
static func reset_to_defaults(auto_save: bool = true) -> GameSettingsModel:
	_display_snapshot = null
	_current = GameSettingsModel.new().sanitize()
	apply_all(_current)
	_notify_settings_changed()
	if auto_save:
		save_async()
	return _current


## 仅重置【显示与窗口分组】为默认值。
static func reset_display_to_defaults(auto_save: bool = true) -> void:
	_display_snapshot = null
	var m := get_current()
	m.display.reset()
	m.display.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 仅重置【画质与渲染分组】为默认值。
static func reset_graphics_to_defaults(auto_save: bool = true) -> void:
	var m := get_current()
	m.graphics.reset()
	m.graphics.sanitize()
	apply_graphics(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 仅重置【音频与静音分组】为默认值。
static func reset_audio_to_defaults(auto_save: bool = true) -> void:
	var m := get_current()
	m.audio.reset()
	m.audio.sanitize()
	apply_audio(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 仅重置【操作与震动分组】为默认值。
static func reset_control_to_defaults(auto_save: bool = true) -> void:
	var m := get_current()
	m.control.reset()
	m.control.sanitize()
	apply_input_and_haptic(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 仅重置【语言与通用分组】为默认值。
static func reset_general_to_defaults(auto_save: bool = true) -> void:
	var m := get_current()
	m.general.reset()
	m.general.sanitize()
	apply_locale(m)
	_notify_settings_changed()
	if auto_save:
		save_async()

#endregion


#region 3. 硬件子系统全量与分域同步 (Hardware Synchronization)

## 将指定设置模型（默认当前模型）全量同步至音频、显示、画质、输入、震动与多语言子系统。
static func apply_all(model: GameSettingsModel = null) -> void:
	var m := (model if model != null else get_current()).sanitize()
	apply_audio(m)
	apply_display(m)
	apply_graphics(m)
	apply_input_and_haptic(m)
	apply_locale(m)


## 同步音频分组至 App.audio（音量滑块与静音开关正交隔离）。
static func apply_audio(model: GameSettingsModel = null) -> void:
	if App == null or App.audio == null:
		return
	var a: AudioSettingsData = (model if model != null else get_current()).audio
	App.audio.set_bus_volume(BaseAudioSystem.BUS_MASTER, clampf(a.master_volume, 0.0, 1.0))
	App.audio.set_bus_volume(BaseAudioSystem.BUS_BGM, clampf(a.bgm_volume, 0.0, 1.0))
	App.audio.set_bus_volume(BaseAudioSystem.BUS_SFX, clampf(a.sfx_volume, 0.0, 1.0))
	App.audio.set_bus_mute(BaseAudioSystem.BUS_MASTER, a.master_muted)
	App.audio.set_music_enabled(a.music_enabled)
	App.audio.set_sfx_enabled(a.sfx_enabled)


## 同步显示与窗口分组至 App.display。
static func apply_display(model: GameSettingsModel = null) -> void:
	if App == null or App.display == null:
		return
	var d: DisplaySettingsData = (model if model != null else get_current()).display
	App.display.set_window_mode(d.window_mode as BaseDisplaySystem.WindowMode, d.screen_index)
	if d.resolution_width > 0 and d.resolution_height > 0:
		App.display.set_resolution(Vector2i(d.resolution_width, d.resolution_height), true)
	var vsync := DisplayServer.VSYNC_ENABLED if d.vsync_enabled else DisplayServer.VSYNC_DISABLED
	App.display.set_vsync_mode(vsync)
	App.display.set_max_fps(maxi(0, d.max_fps))
	App.display.set_safe_area_scale(d.safe_area_scale)
	App.display.set_lock_design_aspect(d.lock_design_aspect)


## 同步画质与视口渲染分组至 App.display 并广播画质变更事件。
static func apply_graphics(model: GameSettingsModel = null) -> void:
	var g: GraphicsSettingsData = (model if model != null else get_current()).graphics
	if App != null and App.display != null:
		App.display.set_msaa_2d(g.msaa_2d as Viewport.MSAA)
		App.display.set_msaa_3d(g.msaa_3d as Viewport.MSAA)
		App.display.set_screen_space_aa(g.screen_space_aa as Viewport.ScreenSpaceAA)
		App.display.set_scaling_3d_scale(g.render_scale)
		App.display.set_canvas_texture_filter(
			g.canvas_texture_filter as Viewport.DefaultCanvasItemTextureFilter
		)
	if Bus != null:
		Bus.emit(EVENT_QUALITY_PRESET_CHANGED, {
			"preset": g.quality_preset,
			"render_scale": g.render_scale,
			"msaa_2d": g.msaa_2d,
			"msaa_3d": g.msaa_3d,
			"screen_space_aa": g.screen_space_aa,
			"effect_quality": g.effect_quality,
			"shadow_quality": g.shadow_quality,
		})


## 同步操作与震动分组至 App.haptic 与 App.input。
static func apply_input_and_haptic(model: GameSettingsModel = null) -> void:
	var c: ControlSettingsData = (model if model != null else get_current()).control
	if App != null and App.haptic != null:
		App.haptic.set_enabled(c.haptic_enabled and c.haptic_strength > 0.0)
	if App != null and App.input != null:
		App.input.set_joy_deadzone(clampf(c.joy_deadzone, 0.05, 0.90))
		if not c.input_bindings.is_empty():
			App.input.import_bindings(c.input_bindings)


## 同步多语言分组至 App.locale。
static func apply_locale(model: GameSettingsModel = null) -> void:
	if App == null or App.locale == null:
		return
	var gen: GeneralSettingsData = (model if model != null else get_current()).general
	var normalized_tag := gen.locale.replace("_", "-")
	var lang_idx := LocaleConfig.language_from_tag(normalized_tag)
	if lang_idx >= 0:
		App.locale.set_language(lang_idx as LocaleConfig.Language)

#endregion


#region 4. 显示分组 API + 15秒切屏事务回滚内核 (Display & Transaction Kernel)

## 开启显示参数变更事务（利用 DisplaySettingsData.clone() 一键快照窗口模式、显示器与分辨率）。
static func begin_display_transaction() -> void:
	var d: DisplaySettingsData = get_current().display
	_display_snapshot = d.clone() as DisplaySettingsData
	if _display_snapshot.resolution_width <= 0 or _display_snapshot.resolution_height <= 0:
		if App != null and App.display != null:
			var cur_res: Vector2i = App.display.get_resolution()
			_display_snapshot.resolution_width = cur_res.x
			_display_snapshot.resolution_height = cur_res.y


## 确认保留当前显示变更事务并按需持久化。
static func commit_display_transaction(auto_save: bool = true) -> void:
	_display_snapshot = null
	if auto_save:
		save_async()


## 回滚显示变更事务（15秒倒计时超时或用户取消时调用，无损恢复至事务前 DisplaySettingsData 快照）。
static func rollback_display_transaction(auto_save: bool = true) -> void:
	if _display_snapshot == null:
		return
	var m := get_current()
	m.display = _display_snapshot.clone() as DisplaySettingsData
	_display_snapshot = null
	m.display.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 当前是否存在待确认的显示变更事务。
static func has_pending_display_transaction() -> bool:
	return _display_snapshot != null


## 设置目标显示器索引。
static func set_screen_index(screen_idx: int, auto_save: bool = true) -> void:
	var m := get_current()
	m.display.screen_index = maxi(0, screen_idx)
	m.display.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置窗口显示模式（WINDOWED / BORDERLESS_WINDOWED / FULLSCREEN / EXCLUSIVE_FULLSCREEN）。
static func set_window_mode(window_mode: int, auto_save: bool = true) -> void:
	var m := get_current()
	m.display.window_mode = window_mode
	m.display.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置窗口物理分辨率。
static func set_resolution(resolution: Vector2i, auto_save: bool = true) -> void:
	if resolution.x <= 0 or resolution.y <= 0:
		return
	var m := get_current()
	m.display.resolution_width = resolution.x
	m.display.resolution_height = resolution.y
	m.display.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 快捷切换全屏 / 窗口模式（如 F11 快捷键），返回切换后的 WindowMode。
static func toggle_fullscreen(use_exclusive: bool = false, auto_save: bool = true) -> int:
	if App != null and App.display != null:
		App.display.toggle_fullscreen(use_exclusive)
		var new_mode: int = int(App.display.get_window_mode())
		var m := get_current()
		m.display.window_mode = new_mode
		m.display.sanitize()
		_notify_settings_changed()
		if auto_save:
			save_async()
		return new_mode
	return get_current().display.window_mode


## 设置垂直同步开关。
static func set_vsync(vsync_enabled: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.display.vsync_enabled = vsync_enabled
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置前台最大帧率上限（0 表示无限制）。
static func set_max_fps(max_fps: int, auto_save: bool = true) -> void:
	var m := get_current()
	m.display.max_fps = maxi(0, max_fps)
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置窗口切后台/失焦时的省电帧率上限（0 表示不降帧）。
static func set_background_max_fps(bg_fps: int, auto_save: bool = true) -> void:
	var m := get_current()
	m.display.background_max_fps = maxi(0, bg_fps)
	m.display.sanitize()
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置全局 HUD 安全区缩放比例 `[0.80, 1.00]`。
static func set_safe_area_scale(scale_ratio: float, auto_save: bool = true) -> void:
	var m := get_current()
	m.display.safe_area_scale = scale_ratio
	m.display.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置是否在安全区内锁定项目基准设计宽高比。
static func set_lock_design_aspect(locked: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.display.lock_design_aspect = locked
	m.display.sanitize()
	apply_display(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置全局画面亮度系数 `[0.50, 1.50]`。
static func set_brightness(brightness: float, auto_save: bool = false) -> void:
	var m := get_current()
	m.display.brightness = brightness
	m.display.sanitize()
	_notify_settings_changed()
	if auto_save:
		save_async()

#endregion


#region 5. 画质分组 API 与预设/自定义双向联动 (Graphics Preset & Custom Linkage)

## 切换全局画质预设档位（LOW / MEDIUM / HIGH / ULTRA），自动展开对应渲染参数并立即生效。
static func set_quality_preset(preset: int, auto_save: bool = true) -> void:
	var m := get_current()
	m.graphics.apply_preset(preset)
	m.graphics.sanitize()
	apply_graphics(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 单独设置 2D/3D MSAA 抗锯齿等级（自动将画质档位切换为 CUSTOM）。
static func set_msaa(msaa_level: int, auto_save: bool = true) -> void:
	var clamped: int = clampi(msaa_level, Viewport.MSAA_DISABLED, Viewport.MSAA_8X)
	set_custom_graphics(clamped, clamped, -1, -1.0, -1, -1.0, -1, auto_save)


## 单独设置屏幕空间后处理抗锯齿模式（自动将画质档位切换为 CUSTOM）。
static func set_screen_space_aa(ssaa_mode: int, auto_save: bool = true) -> void:
	var clamped: int = clampi(ssaa_mode, Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_SMAA)
	set_custom_graphics(-1, -1, clamped, -1.0, -1, -1.0, -1, auto_save)


## 单独设置 3D 渲染分辨率缩放倍率（自动将画质档位切换为 CUSTOM）。
static func set_render_scale(scale_ratio: float, auto_save: bool = true) -> void:
	var clamped: float = clampf(scale_ratio, 0.50, 2.00)
	set_custom_graphics(-1, -1, -1, clamped, -1, -1.0, -1, auto_save)


## 单独设置特效与粒子密度比例（自动将画质档位切换为 CUSTOM）。
static func set_effect_quality(effect_ratio: float, auto_save: bool = true) -> void:
	var clamped: float = clampf(effect_ratio, 0.25, 1.00)
	set_custom_graphics(-1, -1, -1, -1.0, -1, clamped, -1, auto_save)


## 单独设置阴影质量档位（自动将画质档位切换为 CUSTOM）。
static func set_shadow_quality(shadow_mode: int, auto_save: bool = true) -> void:
	var clamped: int = clampi(
		shadow_mode,
		GraphicsSettingsData.ShadowQuality.DISABLED,
		GraphicsSettingsData.ShadowQuality.HIGH
	)
	set_custom_graphics(-1, -1, -1, -1.0, -1, -1.0, clamped, auto_save)


## 组合微调高级视口渲染参数（任意传入有效参数即更新，并自动将档位切换为 CUSTOM）。
static func set_custom_graphics(
	msaa_2d: int = -1,
	msaa_3d: int = -1,
	screen_space_aa: int = -1,
	render_scale: float = -1.0,
	canvas_texture_filter: int = -1,
	effect_quality: float = -1.0,
	shadow_quality: int = -1,
	auto_save: bool = true
) -> void:
	var m := get_current()
	var g: GraphicsSettingsData = m.graphics
	if msaa_2d >= 0:
		g.msaa_2d = msaa_2d
	if msaa_3d >= 0:
		g.msaa_3d = msaa_3d
	if screen_space_aa >= 0:
		g.screen_space_aa = screen_space_aa
	if render_scale > 0.0:
		g.render_scale = render_scale
	if canvas_texture_filter >= 0:
		g.canvas_texture_filter = canvas_texture_filter
	if effect_quality > 0.0:
		g.effect_quality = effect_quality
	if shadow_quality >= 0:
		g.shadow_quality = shadow_quality

	g.quality_preset = GraphicsSettingsData.QualityPreset.CUSTOM
	g.sanitize()
	apply_graphics(m)
	_notify_settings_changed()
	if auto_save:
		save_async()

#endregion


#region 6. 音频分组 API 与正交静音 (Audio & Orthogonal Mute)

## 更新音量滑块（拖动过程中传 auto_save = false 实时听音，松手时再调用 save_async() 落盘）。
static func set_volumes(
	master: float = -1.0,
	bgm: float = -1.0,
	sfx: float = -1.0,
	voice: float = -1.0,
	ambient: float = -1.0,
	auto_save: bool = false
) -> void:
	var m := get_current()
	var a: AudioSettingsData = m.audio
	if master >= 0.0:
		a.master_volume = master
	if bgm >= 0.0:
		a.bgm_volume = bgm
	if sfx >= 0.0:
		a.sfx_volume = sfx
	if voice >= 0.0:
		a.voice_volume = voice
	if ambient >= 0.0:
		a.ambient_volume = ambient
	a.sanitize()
	apply_audio(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置主音量静音开关（不破坏 master_volume 滑块记忆值）。
static func set_master_muted(muted: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.audio.master_muted = muted
	apply_audio(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置背景音乐总开关。
static func set_music_enabled(enabled: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.audio.music_enabled = enabled
	apply_audio(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置音效总开关。
static func set_sfx_enabled(enabled: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.audio.sfx_enabled = enabled
	apply_audio(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置语音总开关。
static func set_voice_enabled(enabled: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.audio.voice_enabled = enabled
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置环境音总开关。
static func set_ambient_enabled(enabled: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.audio.ambient_enabled = enabled
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置切后台/窗口失焦时是否自动静音。
static func set_mute_in_background(enabled: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.audio.mute_in_background = enabled
	_notify_settings_changed()
	if auto_save:
		save_async()

#endregion


#region 7. 操作与通用分组 API (Control, Haptic & General)

## 设置物理触感震动总开关。
static func set_haptic_enabled(enabled: bool, auto_save: bool = true) -> void:
	var m := get_current()
	m.control.haptic_enabled = enabled
	apply_input_and_haptic(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置物理震动强度系数 `[0.0, 1.0]`。
static func set_haptic_strength(strength: float, auto_save: bool = false) -> void:
	var m := get_current()
	m.control.haptic_strength = strength
	m.control.sanitize()
	apply_input_and_haptic(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置手柄摇杆死区 `[0.05, 0.90]`。
static func set_joy_deadzone(deadzone: float, auto_save: bool = false) -> void:
	var m := get_current()
	m.control.joy_deadzone = deadzone
	m.control.sanitize()
	apply_input_and_haptic(m)
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置鼠标/视角旋转灵敏度倍率 `[0.10, 3.00]`。
static func set_mouse_sensitivity(sensitivity: float, auto_save: bool = false) -> void:
	var m := get_current()
	m.control.mouse_sensitivity = sensitivity
	m.control.sanitize()
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置移动端虚拟摇杆模式。
static func set_virtual_joystick_mode(mode: int, auto_save: bool = true) -> void:
	var m := get_current()
	m.control.virtual_joystick_mode = mode
	m.control.sanitize()
	_notify_settings_changed()
	if auto_save:
		save_async()


## 从 App.input 导出当前自定义改键映射补丁并持久化到设置模型。
static func sync_input_bindings_from_system(auto_save: bool = true) -> void:
	if App == null or App.input == null:
		return
	var m := get_current()
	m.control.input_bindings = App.input.export_bindings()
	_notify_settings_changed()
	if auto_save:
		save_async()


## 设置游戏语言区域标识（如 "zh-CN" / "en-US"）。
static func set_locale(locale_tag: String, auto_save: bool = true) -> void:
	if locale_tag.is_empty():
		return
	var m := get_current()
	m.general.locale = locale_tag
	m.general.sanitize()
	apply_locale(m)
	_notify_settings_changed()
	if auto_save:
		save_async()

#endregion


#region 8. 内部后台焦点监听与事件广播 (Internal Focus & Bus Helpers)

static func _ensure_focus_listener() -> void:
	if _focus_listener_connected or Bus == null:
		return
	_focus_listener_connected = true
	if not Bus.app_paused.is_connected(_on_app_paused):
		Bus.app_paused.connect(_on_app_paused)
	if not Bus.app_resumed.is_connected(_on_app_resumed):
		Bus.app_resumed.connect(_on_app_resumed)


static func _on_app_paused() -> void:
	var m := get_current()
	if App != null and App.audio != null:
		App.audio.set_paused(m.audio.mute_in_background)
	if App != null and App.display != null and m.display.background_max_fps > 0:
		App.display.set_max_fps(m.display.background_max_fps)


static func _on_app_resumed() -> void:
	var m := get_current()
	if App != null and App.audio != null:
		App.audio.set_paused(false)
	if App != null and App.display != null:
		App.display.set_max_fps(maxi(0, m.display.max_fps))


static func _notify_settings_changed() -> void:
	var m := get_current()
	m.notify_changed()
	if Bus != null:
		Bus.emit(EVENT_SETTINGS_CHANGED, {"settings": m})

#endregion
