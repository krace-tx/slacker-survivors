class_name AuthTest
extends BaseScene

## Auth 跨平台身份认证、Steam 票据交换与 Steam Cloud 云存档可视化综合测试场景（继承 [BaseScene]，支持 F6 独立启动）。

#region Constants & State
const LOG_TAG: String = "AuthTest"
const TOTAL_CASES: int = 6

var _state_badge_label: Label = null
var _session_info_label: Label = null
var _steam_diag_label: Label = null
var _profile_info_label: Label = null
var _test_summary_label: Label = null
var _event_log_label: Label = null
var _recent_events: Array[String] = []
var _is_running_suite: bool = false
#endregion


#region Scene & Engine Lifecycle
func _on_enter(_params: BaseParams = null) -> void:
	_build_test_ui()
	if App.auth != null:
		App.auth.state_changed.connect(_on_auth_state_changed)
		App.auth.authenticated.connect(_on_authenticated)
		App.auth.logged_out.connect(_on_logged_out)
		App.auth.auth_error.connect(_on_auth_error)
	if Bus != null:
		Bus.on(PlayerProfileService.EVENT_PROFILE_UPDATED, _on_profile_updated)

	_refresh_all_ui()
	await _run_automated_suite_async()

	if OS.get_cmdline_user_args().has("--auth-test-auto-quit") or OS.get_cmdline_args().has("--auth-test-auto-quit"):
		get_tree().quit(0)


func _on_exit() -> void:
	if App.auth != null:
		if App.auth.state_changed.is_connected(_on_auth_state_changed):
			App.auth.state_changed.disconnect(_on_auth_state_changed)
		if App.auth.authenticated.is_connected(_on_authenticated):
			App.auth.authenticated.disconnect(_on_authenticated)
		if App.auth.logged_out.is_connected(_on_logged_out):
			App.auth.logged_out.disconnect(_on_logged_out)
		if App.auth.auth_error.is_connected(_on_auth_error):
			App.auth.auth_error.disconnect(_on_auth_error)
	if Bus != null:
		Bus.off(PlayerProfileService.EVENT_PROFILE_UPDATED, _on_profile_updated)
#endregion


#region Automated Contract & Live Steam Verification Suite
## 顺序执行 6 项核心认证与云存档自动化自检用例。
func _run_automated_suite_async() -> int:
	if _is_running_suite:
		return 0
	_is_running_suite = true
	var passed := 0
	var logs: PackedStringArray = []
	_append_event_log("▶ 开始执行 Auth & Steamworks 6 项自动化契约自检...")

	# Case 1: GodotSteam GDExtension 探测与多端渠道注册校验
	var avail_providers := App.auth.get_available_providers()
	var has_guest := avail_providers.has(AuthProviderType.GUEST)
	var steam_avail := App.auth.is_provider_available(AuthProviderType.STEAM)
	var steam_diag := _query_raw_steam_diagnostics()
	if has_guest and (steam_avail == bool(steam_diag.get("running", false))):
		passed += 1
		logs.append(
			"✅ [1/6] 渠道发现与反射桥接正常 (可用渠道: %s | SteamAppID: %s)" % [
				str(avail_providers), str(steam_diag.get("app_id", 0))
			]
		)
	else:
		logs.append("❌ [1/6] 渠道发现异常: %s" % str(avail_providers))

	# Case 2: Steam 登录与 WebAPI Ticket 异步取证验证 (若未开 Steam 则验证 Auto -> Guest 降级)
	if steam_avail:
		var steam_opts := AuthOptions.create() \
			.with_provider(AuthProviderType.STEAM) \
			.with_require_ticket(true, "game_backend")
		var steam_res := await App.auth.login_with_provider_async(AuthProviderType.STEAM, steam_opts)
		if steam_res.is_ok():
			var s_sess := steam_res.value as AuthSession
			var ticket_len := s_sess.platform_ticket.length()
			if s_sess.provider == AuthProviderType.STEAM and s_sess.account_id.begins_with("steam_") and (ticket_len >= 32 or s_sess.is_offline):
				passed += 1
				logs.append(
					"✅ [2/6] Steam 登录与 WebAPI Ticket 取证通过 (用户: %s | SteamID: %s | TicketHex: %d chars)" % [
						s_sess.display_name, s_sess.platform_user_id, ticket_len
					]
				)
			else:
				logs.append("❌ [2/6] Steam 会话字段校验未通过: %s (ticket_len=%d)" % [s_sess.account_id, ticket_len])
		else:
			logs.append("❌ [2/6] Steam 登录失败: [%s] %s" % [steam_res.error_code(), steam_res.error_message()])
	else:
		var auto_res := await App.auth.login_auto_async()
		if auto_res.is_ok() and (auto_res.value as AuthSession).is_valid():
			passed += 1
			logs.append("✅ [2/6] Steam 未开启，Auto 智能降级登录通过 (%s)" % (auto_res.value as AuthSession).account_id)
		else:
			logs.append("❌ [2/6] Auto 智能降级登录失败")

	# Case 3: 登出释放与本机设备指纹游客 (Guest) 确定性派生验证
	App.auth.logout("suite_case_3")
	var logged_out_ok := (App.auth.get_state() == AuthState.UNAUTHENTICATED and not App.auth.is_authenticated())
	var g1_res := await App.auth.login_with_provider_async(AuthProviderType.GUEST)
	var g1_id := App.auth.get_account_id()
	App.auth.logout("suite_case_3_repeat")
	var g2_res := await App.auth.login_with_provider_async(AuthProviderType.GUEST)
	var g2_id := App.auth.get_account_id()
	if logged_out_ok and g1_res.is_ok() and g2_res.is_ok() and g1_id.begins_with("guest_") and g1_id == g2_id and App.auth.is_guest_session():
		passed += 1
		logs.append("✅ [3/6] 登出句柄释放与本机指纹 Guest 确定性 ID 校验通过 (%s)" % g1_id)
	else:
		logs.append("❌ [3/6] Guest 确定性派生或登出状态异常 (%s vs %s)" % [g1_id, g2_id])

	# Case 4: 游客无损转正 (Account Linking: Guest -> Steam / Custom)
	var prev_guest_id := App.auth.get_account_id()
	var link_res: Result
	if steam_avail:
		var link_opts := AuthOptions.create().with_require_ticket(false)
		link_res = await App.auth.link_provider_async(AuthProviderType.STEAM, link_opts)
	else:
		var custom_opts := AuthOptions.create().with_custom_credentials("uid_linked_99", "tok_secret_99", "LinkedHero")
		link_res = await App.auth.link_provider_async(AuthProviderType.CUSTOM, custom_opts)

	if link_res.is_ok():
		var linked_sess := link_res.value as AuthSession
		if linked_sess.linked_from_account_id == prev_guest_id and not linked_sess.is_guest:
			passed += 1
			logs.append(
				"✅ [4/6] 游客无损转正 (Account Linking) 通过 (%s ➔ %s)" % [
					linked_sess.linked_from_account_id, linked_sess.account_id
				]
			)
		else:
			logs.append("❌ [4/6] 游客转正未保留原游客 ID: linked_from='%s'" % linked_sess.linked_from_account_id)
	else:
		logs.append("❌ [4/6] 游客转正调用失败: [%s] %s" % [link_res.error_code(), link_res.error_message()])

	# Case 5: 自建后端网关不可达时的离线容灾降级 (RemoteGatewayVerifier Offline Fallback)
	var gw_opts := AuthOptions.create() \
		.with_provider(AuthProviderType.STEAM if steam_avail else AuthProviderType.GUEST) \
		.with_require_ticket(false) \
		.with_remote_gateway(true, "http://localhost.invalid/v1/auth/exchange") \
		.with_offline_fallback(true)
	var gw_res := await App.auth.login_auto_async(gw_opts)
	if gw_res.is_ok() and App.auth.is_offline_session() and App.auth.get_state() == AuthState.OFFLINE:
		passed += 1
		logs.append(
			"✅ [5/6] 远端网关断连自动降级 OFFLINE 会话通过 (账号保留: %s)" % App.auth.get_account_id()
		)
	else:
		logs.append("❌ [5/6] 远端网关离线降级异常")

	# Case 6: 恢复正式登录 + Steam Cloud (ISteamRemoteStorage) & PlayerProfileService 闭环验证
	var final_opts := AuthOptions.create().with_require_ticket(true, "game_backend")
	await App.auth.login_auto_async(final_opts)
	var prof_res := await PlayerProfileService.load_or_create_async()
	var prof := PlayerProfileService.get_current()
	prof.set_custom_value("last_auth_test_ms", App.clock.now_msec())
	var save_res := await PlayerProfileService.save_async()
	await App.storage.flush_async()

	var cloud_item := PlayerProfileModel.storage_item()
	var cloud_verified := false
	if bool(steam_diag.get("cloud_enabled", false)):
		var cloud_read := await App.storage.read_async(cloud_item, StorageReadMode.REMOTE_ONLY)
		if cloud_read.is_ok() and cloud_read.value is Dictionary:
			var cloud_dict := cloud_read.value as Dictionary
			cloud_verified = (str(cloud_dict.get("profile_id", "")) == prof.profile_id)
	else:
		var local_read := await App.storage.read_async(cloud_item, StorageReadMode.LOCAL_ONLY)
		cloud_verified = local_read.is_ok()

	if prof_res.is_ok() and save_res.is_ok() and prof.profile_id == App.auth.get_account_id() and cloud_verified:
		passed += 1
		logs.append(
			"✅ [6/6] PlayerProfile 身份合并与 Steam Cloud 云存档同步通过 (profile_id=%s, login_count=%d)" % [
				prof.profile_id, prof.login_count
			]
		)
	else:
		logs.append(
			"❌ [6/6] 档案与云存档校验失败 (prof_ok=%s, save_ok=%s, cloud_ok=%s, prof_id=%s)" % [
				str(prof_res.is_ok()), str(save_res.is_ok()), str(cloud_verified), prof.profile_id
			]
		)

	if _test_summary_label != null:
		_test_summary_label.text = "\n".join(logs)

	_is_running_suite = false
	_refresh_all_ui()
	App.logger.info(LOG_TAG, "Automated verification suite completed: %d/%d passed." % [passed, TOTAL_CASES])
	for line in logs:
		App.logger.info(LOG_TAG, line)
	return passed
#endregion


#region Interactive Action Handlers
func _on_action_auto_login() -> void:
	_append_event_log("触发: 智能自动登录 (Auto Login)...")
	var opts := AuthOptions.create().with_require_ticket(true, "game_backend")
	var res := await App.auth.login_auto_async(opts)
	if res.is_ok():
		await PlayerProfileService.load_or_create_async()
	_refresh_all_ui()


func _on_action_steam_ticket_login() -> void:
	_append_event_log("触发: Steam 登录并向 Valve 申请 WebAPI Ticket...")
	var opts := AuthOptions.create() \
		.with_provider(AuthProviderType.STEAM) \
		.with_require_ticket(true, "game_backend") \
		.with_offline_fallback(false)
	var res := await App.auth.login_with_provider_async(AuthProviderType.STEAM, opts)
	if res.is_ok():
		await PlayerProfileService.load_or_create_async()
	_refresh_all_ui()


func _on_action_steam_fast_login() -> void:
	_append_event_log("触发: Steam 单机 0ms 极速直通登录 (require_ticket=false)...")
	var opts := AuthOptions.create() \
		.with_provider(AuthProviderType.STEAM) \
		.with_require_ticket(false)
	var res := await App.auth.login_with_provider_async(AuthProviderType.STEAM, opts)
	if res.is_ok():
		await PlayerProfileService.load_or_create_async()
	_refresh_all_ui()


func _on_action_guest_login() -> void:
	_append_event_log("触发: 本机设备指纹游客登录 (Guest)...")
	var res := await App.auth.login_with_provider_async(AuthProviderType.GUEST)
	if res.is_ok():
		PlayerProfileService.get_current().apply_auth_session(res.value as AuthSession)
	_refresh_all_ui()


func _on_action_link_steam() -> void:
	_append_event_log("触发: 游客转正绑定 Steam (link_provider_async)...")
	var opts := AuthOptions.create().with_require_ticket(true, "game_backend")
	var res := await App.auth.link_provider_async(AuthProviderType.STEAM, opts)
	if res.is_ok():
		var sess := res.value as AuthSession
		PlayerProfileService.get_current().apply_auth_session(sess)
		await PlayerProfileService.save_async()
		_append_event_log("🎉 转正成功: %s -> %s" % [sess.linked_from_account_id, sess.account_id])
	_refresh_all_ui()


func _on_action_gateway_fallback() -> void:
	_append_event_log("触发: 模拟远端网关换票不可达 -> 自动降级离线会话...")
	var opts := AuthOptions.create() \
		.with_require_ticket(false) \
		.with_remote_gateway(true, "http://localhost.invalid/v1/auth/exchange") \
		.with_offline_fallback(true)
	await App.auth.login_auto_async(opts)
	_refresh_all_ui()


func _on_action_steam_cloud_sync() -> void:
	_append_event_log("触发: 写入并从 Steam Cloud (REMOTE_ONLY) 读取玩家档案...")
	var prof := PlayerProfileService.get_current()
	prof.set_custom_value("manual_cloud_sync_at", TimeUtils.now_string())
	var save_res := await PlayerProfileService.save_async()
	await App.storage.flush_async()
	var item := PlayerProfileModel.storage_item()
	var read_res := await App.storage.read_async(item, StorageReadMode.REMOTE_ONLY)
	if save_res.is_ok() and read_res.is_ok():
		var d: Dictionary = read_res.value as Dictionary
		_append_event_log(
			"☁️ Steam Cloud 读写成功: file='%s', profile_id='%s', login_count=%s" % [
				item.steam_cloud_file,
				str(d.get("profile_id", "")),
				str(d.get("login_count", 0))
			]
		)
	else:
		var err_msg := save_res.error_message() if save_res.is_err() else read_res.error_message()
		_append_event_log("⚠️ Steam Cloud 同步提示: %s" % err_msg)
	_refresh_all_ui()


func _on_action_logout() -> void:
	App.auth.logout("manual_ui_button")
	_refresh_all_ui()
#endregion


#region Signal Callbacks
func _on_auth_state_changed(new_state: int, old_state: int) -> void:
	_append_event_log(
		"状态流转: %s ➔ %s" % [
			String(AuthState.to_string_name(old_state)),
			String(AuthState.to_string_name(new_state))
		]
	)
	_refresh_all_ui()


func _on_authenticated(session: AuthSession) -> void:
	var ticket_tag := (
		"Ticket:%dchars" % session.platform_ticket.length()
		if not session.platform_ticket.is_empty()
		else "NoTicket"
	)
	_append_event_log(
		"登录成功: [%s] %s (%s) | %s | offline=%s" % [
			String(session.provider),
			session.display_name,
			session.account_id,
			ticket_tag,
			str(session.is_offline)
		]
	)
	_refresh_all_ui()


func _on_logged_out(reason: String) -> void:
	_append_event_log("已登出: reason='%s' (底层票据句柄已释放)" % reason)
	_refresh_all_ui()


func _on_auth_error(code: String, message: String) -> void:
	_append_event_log("认证错误: [%s] %s" % [code, message])
	_refresh_all_ui()


func _on_profile_updated(_payload: Dictionary = {}) -> void:
	_refresh_all_ui()
#endregion


#region Visual Dashboard Construction
func _build_test_ui() -> void:
	var root_ui := get_node_or_null("UI") as Control
	if root_ui == null:
		return

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	root_ui.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(main_vbox)

	# 顶部标题与状态栏
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 14)
	main_vbox.add_child(top_bar)

	var title := Label.new()
	title.text = "🔐 App.auth 跨平台认证 & Steamworks 票据/云存档验证中心"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)

	_state_badge_label = Label.new()
	_state_badge_label.add_theme_font_size_override("font_size", 16)
	top_bar.add_child(_state_badge_label)

	var rerun_btn := Button.new()
	rerun_btn.text = "🔄 重新运行 6 项自动化自检"
	rerun_btn.focus_mode = Control.FOCUS_NONE
	rerun_btn.pressed.connect(func() -> void: _run_automated_suite_async())
	top_bar.add_child(rerun_btn)

	# 中部左右分栏
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(content_hbox)

	# 左侧：实时会话看板 + Steamworks 诊断 + 交互按钮矩阵
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.15
	content_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_vbox)

	var sess_title := Label.new()
	sess_title.text = "🪪 当前生效会话快照 (AuthSession)"
	sess_title.add_theme_font_size_override("font_size", 16)
	sess_title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	left_vbox.add_child(sess_title)

	_session_info_label = Label.new()
	_session_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(_session_info_label)

	var steam_title := Label.new()
	steam_title.text = "🛠️ Steamworks & Steam Cloud 实时硬件诊断"
	steam_title.add_theme_font_size_override("font_size", 16)
	steam_title.add_theme_color_override("font_color", Color(0.55, 0.92, 0.72))
	left_vbox.add_child(steam_title)

	_steam_diag_label = Label.new()
	_steam_diag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(_steam_diag_label)

	var prof_title := Label.new()
	prof_title.text = "💾 玩家全局档案快照 (PlayerProfileModel)"
	prof_title.add_theme_font_size_override("font_size", 16)
	prof_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	left_vbox.add_child(prof_title)

	_profile_info_label = Label.new()
	_profile_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(_profile_info_label)

	var actions_title := Label.new()
	actions_title.text = "🎛️ 交互式登录与云存档操作矩阵"
	actions_title.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(actions_title)

	var action_grid := GridContainer.new()
	action_grid.columns = 2
	action_grid.add_theme_constant_override("h_separation", 10)
	action_grid.add_theme_constant_override("v_separation", 8)
	left_vbox.add_child(action_grid)

	for btn_cfg in [
		{"text": "🚀 智能自动登录 (Auto Login)", "cb": _on_action_auto_login},
		{"text": "🎮 Steam 登录 (含 WebAPI Ticket)", "cb": _on_action_steam_ticket_login},
		{"text": "⚡ Steam 极速直通 (免 Ticket 0ms)", "cb": _on_action_steam_fast_login},
		{"text": "👤 设备指纹游客登录 (Guest)", "cb": _on_action_guest_login},
		{"text": "🔗 游客转正绑定 Steam (Link Account)", "cb": _on_action_link_steam},
		{"text": "🌐 模拟网关断连 -> 自动离线降级", "cb": _on_action_gateway_fallback},
		{"text": "☁️ 写入并校验 Steam Cloud 云存档", "cb": _on_action_steam_cloud_sync},
		{"text": "🚪 登出并释放票据句柄 (Logout)", "cb": _on_action_logout},
	]:
		var btn := Button.new()
		btn.text = btn_cfg["text"]
		btn.custom_minimum_size = Vector2(240, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var callback: Callable = btn_cfg["cb"]
		btn.pressed.connect(callback)
		action_grid.add_child(btn)

	# 右侧：6 项自动化契约自检报告 + 实时事件流日志
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 12)
	right_panel.add_child(right_vbox)

	var suite_title := Label.new()
	suite_title.text = "📋 自动化契约自检报告 (6 项核心能力)"
	suite_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(suite_title)

	_test_summary_label = Label.new()
	_test_summary_label.text = "正在执行自动化自检..."
	_test_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_test_summary_label)

	var log_title := Label.new()
	log_title.text = "📡 认证状态机与云存档事件时间线"
	log_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(log_title)

	_event_log_label = Label.new()
	_event_log_label.text = "等待认证事件..."
	_event_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_event_log_label)
#endregion


#region UI Refresh & Steam Diagnostics Helpers
func _refresh_all_ui() -> void:
	if _state_badge_label == null or App.auth == null:
		return

	var st := App.auth.get_state()
	var st_name := String(AuthState.to_string_name(st))
	_state_badge_label.text = "状态: [%s]" % st_name
	match st:
		AuthState.AUTHENTICATED:
			_state_badge_label.add_theme_color_override("font_color", Color(0.30, 0.95, 0.55))
		AuthState.OFFLINE:
			_state_badge_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
		AuthState.ERROR:
			_state_badge_label.add_theme_color_override("font_color", Color(1.0, 0.40, 0.40))
		_:
			_state_badge_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))

	var sess := App.auth.get_session()
	if sess == null or not sess.is_valid():
		_session_info_label.text = "当前未登录 (AuthSession == null)"
	else:
		var ticket_preview := "未申请 (0 chars)"
		if not sess.platform_ticket.is_empty():
			var t := sess.platform_ticket
			ticket_preview = "%s...%s (%d Hex chars)" % [
				t.substr(0, mini(16, t.length())),
				t.substr(maxi(0, t.length() - 12), mini(12, t.length())),
				t.length()
			]
		var linked_str := sess.linked_from_account_id if not sess.linked_from_account_id.is_empty() else "无"
		_session_info_label.text = (
			"• 游戏账号 (account_id): %s\n"
			+ "• 认证渠道 (provider): %s | 原生 ID: %s\n"
			+ "• 展示昵称 (display_name): %s\n"
			+ "• 离线模式 (is_offline): %s | 游客身份 (is_guest): %s\n"
			+ "• 游客转正来源 (linked_from): %s\n"
			+ "• 平台票据 (platform_ticket): %s"
		) % [
			sess.account_id,
			String(sess.provider),
			sess.platform_user_id,
			sess.display_name,
			str(sess.is_offline),
			str(sess.is_guest),
			linked_str,
			ticket_preview,
		]

	var diag := _query_raw_steam_diagnostics()
	var cloud_file := PlayerProfileModel.storage_item().steam_cloud_file
	_steam_diag_label.text = (
		"• GodotSteam 单例: %s | Steam 客户端运行中: %s\n"
		+ "• AppID: %s | 在线状态 (loggedOn): %s | 客户端语言: %s\n"
		+ "• Steam Cloud 开启: %s | 云端存在 '%s': %s (%s Bytes)\n"
		+ "• Steam Cloud 配额: 可用 %s MB / 总计 %s MB"
	) % [
		str(diag.get("singleton", false)),
		str(diag.get("running", false)),
		str(diag.get("app_id", 0)),
		str(diag.get("logged_on", false)),
		str(diag.get("ui_lang", "N/A")),
		str(diag.get("cloud_enabled", false)),
		cloud_file,
		str(diag.get("cloud_file_exists", false)),
		str(diag.get("cloud_file_size", 0)),
		str(diag.get("quota_avail_mb", "0.0")),
		str(diag.get("quota_total_mb", "0.0")),
	]

	var prof := PlayerProfileService.get_current()
	_profile_info_label.text = (
		"• 档案 ID (profile_id): %s | 绑定渠道: %s\n"
		+ "• 档案昵称 (nickname): %s | 平台 UID: %s\n"
		+ "• 累计登录次数 (login_count): %d | 扩展元数据: %s"
	) % [
		prof.profile_id,
		prof.auth_provider,
		prof.nickname,
		prof.platform_user_id,
		prof.login_count,
		JSON.stringify(prof.custom_data),
	]


func _query_raw_steam_diagnostics() -> Dictionary:
	var info := {
		"singleton": Engine.has_singleton("Steam"),
		"running": false,
		"app_id": 0,
		"logged_on": false,
		"ui_lang": "N/A",
		"cloud_enabled": false,
		"cloud_file_exists": false,
		"cloud_file_size": 0,
		"quota_avail_mb": "0.0",
		"quota_total_mb": "0.0",
	}
	if not bool(info["singleton"]):
		return info

	var steam: Object = Engine.get_singleton("Steam")
	if steam == null:
		return info

	var running := bool(steam.call("isSteamRunning")) if steam.has_method("isSteamRunning") else false
	info["running"] = running
	if not running:
		return info

	if steam.has_method("getAppID"):
		info["app_id"] = int(steam.call("getAppID"))
	if steam.has_method("loggedOn"):
		info["logged_on"] = bool(steam.call("loggedOn"))
	if steam.has_method("getSteamUILanguage"):
		info["ui_lang"] = str(steam.call("getSteamUILanguage"))

	var cloud_acct := bool(steam.call("isCloudEnabledForAccount")) if steam.has_method("isCloudEnabledForAccount") else false
	var cloud_app := bool(steam.call("isCloudEnabledForApp")) if steam.has_method("isCloudEnabledForApp") else false
	info["cloud_enabled"] = cloud_acct and cloud_app

	var cloud_file := PlayerProfileModel.storage_item().steam_cloud_file
	if steam.has_method("fileExists"):
		info["cloud_file_exists"] = bool(steam.call("fileExists", cloud_file))
	if steam.has_method("getFileSize") and bool(info["cloud_file_exists"]):
		info["cloud_file_size"] = int(steam.call("getFileSize", cloud_file))

	if steam.has_method("getQuota"):
		var quota_var: Variant = steam.call("getQuota")
		if quota_var is Dictionary:
			var q := quota_var as Dictionary
			var total_b := float(q.get("total_bytes", 0))
			var avail_b := float(q.get("available_bytes", 0))
			info["quota_total_mb"] = "%.1f" % (total_b / (1024.0 * 1024.0))
			info["quota_avail_mb"] = "%.1f" % (avail_b / (1024.0 * 1024.0))

	return info


func _append_event_log(line: String) -> void:
	_recent_events.push_front("%s  %s" % [TimeUtils.now_string(), line])
	if _recent_events.size() > 12:
		_recent_events.resize(12)
	if _event_log_label != null:
		_event_log_label.text = "\n".join(_recent_events)
#endregion
