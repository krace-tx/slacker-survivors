class_name DisplayTestService
extends RefCounted

## 显示与画质测试领域服务
##
## 直接调用跨项目通用的 GameSettingsService 内核 API，不再重复维护回滚快照与底层同步细节。


#region 常量定义

const LOG_TAG: String = "DisplayTestService"

const FPS_OPTIONS: Array[int] = GameSettingsService.FPS_PRESETS
const SCALE_3D_OPTIONS: Array[float] = GameSettingsService.RENDER_SCALE_PRESETS
const SAFE_AREA_SCALE_OPTIONS: Array[float] = GameSettingsService.SAFE_AREA_SCALE_PRESETS

#endregion


#region 私有变量

var _state: DisplayTestState = null

#endregion


#region 生命周期

func _init(state: DisplayTestState) -> void:
	_state = state
	refresh_state()

#endregion


#region 状态同步与查询

## 刷新当前显示与设置状态快照
func refresh_state() -> void:
	if _state == null or App == null or App.display == null:
		return
	var model: GameSettingsModel = GameSettingsService.get_current()
	_state.sync_from(App.display, model)


## 获取安全分辨率在列表中的索引
func find_resolution_index(target: Vector2i) -> int:
	for i: int in _state.available_resolutions.size():
		if _state.available_resolutions[i] == target:
			return i
	return -1


## 获取目标帧率在列表中的索引
func find_fps_index(fps: int) -> int:
	var idx: int = FPS_OPTIONS.find(fps)
	return idx if idx >= 0 else (FPS_OPTIONS.size() - 1)


## 获取渲染倍率在列表中的索引
func find_scale_3d_index(scale_val: float) -> int:
	var best_idx: int = 2
	var min_diff: float = 999.0
	for i: int in SCALE_3D_OPTIONS.size():
		var diff: float = absf(SCALE_3D_OPTIONS[i] - scale_val)
		if diff < min_diff:
			min_diff = diff
			best_idx = i
	return best_idx


## 获取安全区比例在列表中的索引
func find_safe_area_scale_index(scale_val: float) -> int:
	var best_idx: int = 0
	var min_diff: float = 999.0
	for i: int in SAFE_AREA_SCALE_OPTIONS.size():
		var diff: float = absf(SAFE_AREA_SCALE_OPTIONS[i] - scale_val)
		if diff < min_diff:
			min_diff = diff
			best_idx = i
	return best_idx

#endregion


#region 窗口模式与分辨率控制（委托 GameSettingsService 事务内核）

## 开启切屏事务快照
func capture_revert_snapshot() -> void:
	GameSettingsService.begin_display_transaction()


## 应用窗口模式
func apply_window_mode(mode: int) -> void:
	GameSettingsService.set_window_mode(mode, true)
	_state.last_change_text = "窗口模式 -> %s" % DisplayEnterParams.format_window_mode(mode)
	App.logger.info(LOG_TAG, _state.last_change_text)
	refresh_state()


## 应用分辨率
func apply_resolution(res: Vector2i) -> void:
	GameSettingsService.set_resolution(res, true)
	_state.last_change_text = "分辨率 -> %d × %d" % [res.x, res.y]
	App.logger.info(LOG_TAG, _state.last_change_text)
	refresh_state()


## 快捷切换全屏/窗口模式 (F11)
func toggle_fullscreen() -> void:
	var new_mode: int = GameSettingsService.toggle_fullscreen(false, true)
	_state.last_change_text = "切换全屏 -> %s" % DisplayEnterParams.format_window_mode(new_mode)
	refresh_state()


## 回滚至切屏前的窗口模式与分辨率快照
func rollback_display_change() -> void:
	GameSettingsService.rollback_display_transaction(true)
	var m: GameSettingsModel = GameSettingsService.get_current()
	_state.last_change_text = "已还原显示设置 (%s)" % DisplayEnterParams.format_window_mode(m.display.window_mode)
	App.logger.info(LOG_TAG, _state.last_change_text)
	refresh_state()


## 确认保留当前显示变更
func confirm_display_change() -> void:
	GameSettingsService.commit_display_transaction(true)
	_state.last_change_text = "已确认保留当前显示设置"
	refresh_state()

#endregion


#region 帧率、安全区与画质控制（委托 GameSettingsService 原子 API）

## 设置垂直同步开关
func apply_vsync(vsync_enabled: bool) -> void:
	GameSettingsService.set_vsync(vsync_enabled, true)
	_state.last_change_text = "垂直同步 -> %s" % DisplayEnterParams.format_vsync(vsync_enabled)
	refresh_state()


## 设置目标帧率上限
func apply_target_fps(fps: int) -> void:
	GameSettingsService.set_max_fps(fps, true)
	_state.last_change_text = "帧率上限 -> %s" % DisplayEnterParams.format_fps(fps)
	refresh_state()


## 设置全局安全区缩放比例
func apply_safe_area_scale(scale_val: float) -> void:
	GameSettingsService.set_safe_area_scale(scale_val, true)
	_state.last_change_text = "HUD 安全区比例 -> %d%%" % roundi(scale_val * 100.0)
	refresh_state()


## 设置是否在安全区内锁定项目基准设计宽高比
func apply_lock_design_aspect(locked: bool) -> void:
	GameSettingsService.set_lock_design_aspect(locked, true)
	var mode_str: String = "锁定设计宽高比居中" if locked else "自适应全屏宽高比"
	_state.last_change_text = "安全区宽高比 -> %s" % mode_str
	refresh_state()


## 应用整体画质预设档位
func apply_quality_preset(preset: int) -> void:
	GameSettingsService.set_quality_preset(preset, true)
	_state.last_change_text = "画质档位 -> %s" % DisplayEnterParams.format_quality_preset(preset)
	refresh_state()


## 单独调节 MSAA 抗锯齿（自动切为自定义画质）
func apply_custom_msaa(msaa_level: int) -> void:
	GameSettingsService.set_msaa(msaa_level, true)
	_state.last_change_text = "MSAA 调节 -> 自动切换为自定义画质"
	refresh_state()


## 单独调节屏幕空间抗锯齿（自动切为自定义画质）
func apply_custom_ssaa(ssaa_mode: int) -> void:
	GameSettingsService.set_screen_space_aa(ssaa_mode, true)
	_state.last_change_text = "后处理抗锯齿 -> 自动切换为自定义画质"
	refresh_state()


## 单独调节渲染倍率（自动切为自定义画质）
func apply_custom_scale_3d(scale_val: float) -> void:
	GameSettingsService.set_render_scale(scale_val, true)
	_state.last_change_text = "渲染倍率 %.0f%% -> 自动切换为自定义画质" % (scale_val * 100.0)
	refresh_state()


## 恢复所有设置为出厂默认值
func reset_all_to_defaults() -> void:
	GameSettingsService.reset_to_defaults(true)
	_state.last_change_text = "已恢复默认显示与画质设置"
	refresh_state()

#endregion
