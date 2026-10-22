class_name DisplayLobbyView
extends BaseView

## 显示测试大厅页被动视图
##
## 负责渲染顶部状态胶囊与左下角简约信息卡，向上转发按钮交互信号。


#region 信号定义

signal open_settings_requested()
signal toggle_fullscreen_requested()

#endregion


#region 节点引用

@onready var _status_summary_label: Label = $SafeMargin/MainLayout/TopBar/StatusPill/StatusSummaryLabel as Label
@onready var _fullscreen_btn: Button = $SafeMargin/MainLayout/TopBar/FullscreenBtn as Button
@onready var _settings_btn: Button = $SafeMargin/MainLayout/TopBar/SettingsBtn as Button
@onready var _notice_label: Label = $SafeMargin/MainLayout/BottomRow/InfoCard/CardVBox/NoticeLabel as Label
@onready var _embed_hint_label: Label = $SafeMargin/MainLayout/BottomRow/InfoCard/CardVBox/EmbedHintLabel as Label
@onready var _spec_line_label: Label = $SafeMargin/MainLayout/BottomRow/InfoCard/CardVBox/SpecLineLabel as Label
@onready var _open_settings_primary_btn: Button = $SafeMargin/MainLayout/BottomRow/InfoCard/CardVBox/ActionRow/OpenSettingsPrimaryBtn as Button

#endregion


#region 生命周期

func _ready() -> void:
	super._ready()
	_settings_btn.pressed.connect(func() -> void: open_settings_requested.emit())
	_open_settings_primary_btn.pressed.connect(func() -> void: open_settings_requested.emit())
	_fullscreen_btn.pressed.connect(func() -> void: toggle_fullscreen_requested.emit())

#endregion


#region 渲染接口

## 根据当前状态模型刷新大厅极简视图
func render_state(state: DisplayTestState) -> void:
	_status_summary_label.text = state.get_summary_line()
	_embed_hint_label.visible = state.is_embedded_in_editor

	var vsync_str: String = DisplayEnterParams.format_vsync(state.vsync_enabled)
	var scale_str: String = "%d%%" % roundi(state.render_scale * 100.0)
	var safe_str: String = "%d%%%s" % [
		roundi(state.safe_area_scale * 100.0),
		" (锁定设计比例)" if state.lock_design_aspect else ""
	]
	_spec_line_label.text = "显示器: %d × %d (%dHz)   ·   垂直同步: %s   ·   安全区: %s   ·   渲染倍率: %s" % [
		state.screen_size.x,
		state.screen_size.y,
		roundi(state.screen_refresh_rate),
		vsync_str,
		safe_str,
		scale_str
	]


## 更新提示文案
func set_notice_text(text: String) -> void:
	if not text.is_empty():
		_notice_label.text = text

#endregion
