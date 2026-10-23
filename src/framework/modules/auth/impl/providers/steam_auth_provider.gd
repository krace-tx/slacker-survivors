class_name SteamAuthProvider
extends AuthProviderAdapter

## Valve Steam 平台认证适配器（GodotSteam Dynamic Reflection Bridge）。[br]
##
## 核心特性：[br]
## 1. [b]外部插件零硬耦合[/b]：采用 [method Engine.has_singleton] 动态探测 [code]Steam[/code] 单例，未安装 GodotSteam 插件时零编译报错；[br]
## 2. [b]新版 WebAPI Ticket 优先[/b]：优先调用 Steamworks 推荐的 [code]getAuthTicketForWebApi(identity)[/code]，自动向下兼容 [code]getAuthSessionTicket()[/code]；[br]
## 3. [b]Steam Deck / 离线模式无缝保底[/b]：当 Steam 客户端处于离线模式（[code]loggedOn() == false[/code] 但 [code]getSteamID() > 0[/code]）时，
##    直接签发携带 [code]is_platform_offline = true[/code] 的真实 SteamID64 凭证，确保单机游玩与存档槽归属不断链；[br]
## 4. [b]票据句柄生命周期闭环[/b]：登出或销毁时自动调用 [code]cancelAuthTicket[/code] 释放底层票据句柄。

#region Constants & State
## GodotSteam 引擎单例注册名称
const SINGLETON_STEAM: StringName = &"Steam"

## 是否已完成进程级 Steamworks API 初始化（steamInitEx / steamInit）
static var _steam_initialized: bool = false

## 当前持有的 Steam 认证票据句柄（HAuthTicket，>0 时需在登出或销毁时调用 cancelAuthTicket）
var _active_ticket_handle: int = 0
## 是否已收到外部取消取证指令
var _cancel_requested: bool = false
#endregion


#region AuthProviderAdapter Implementation
func setup() -> void:
	_ensure_steam_initialized()


func get_provider_id() -> StringName:
	return AuthProviderType.STEAM


func get_provider_name() -> String:
	return "Steamworks (GodotSteam)"


## 检测当前环境中 GodotSteam 单例是否已挂载、Steam 客户端是否正在运行且已分配有效 SteamID64。
func is_available() -> bool:
	var steam := _get_steam_singleton()
	if steam == null:
		return false
	if not _ensure_steam_initialized():
		return false
	if steam.has_method("isSteamRunning") and not bool(steam.call("isSteamRunning")):
		return false
	if steam.has_method("getSteamID"):
		return int(steam.call("getSteamID")) > 0
	return false


## 取消正在等待中的票据请求并释放已持有的 Steam HAuthTicket 句柄。
func cancel_pending() -> void:
	_cancel_requested = true
	_release_active_ticket()


## 采集 Steam 平台身份凭证（包含 SteamID64、昵称、离线状态判定及可选的 WebAPI Ticket 异步握手）。
func acquire_credential_async(options: AuthOptions) -> Result:
	_cancel_requested = false
	var steam := _get_steam_singleton()
	if steam == null or not is_available():
		return Result.err_code(
			AuthError.PROVIDER_UNAVAILABLE,
			"Steam client is not running or GodotSteam singleton is unavailable."
		)

	var steam_id: int = int(steam.call("getSteamID")) if steam.has_method("getSteamID") else 0
	if steam_id <= 0:
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "Invalid SteamID64 (0) returned by Steamworks.")

	var persona_name: String = "SteamPlayer"
	if steam.has_method("getPersonaName"):
		var raw_name := str(steam.call("getPersonaName")).strip_edges()
		if not raw_name.is_empty():
			persona_name = raw_name

	var is_logged_on: bool = bool(steam.call("loggedOn")) if steam.has_method("loggedOn") else true
	var app_id: int = int(steam.call("getAppID")) if steam.has_method("getAppID") else 0
	var ui_lang: String = str(steam.call("getSteamUILanguage")) if steam.has_method("getSteamUILanguage") else ""

	var credential := AuthCredential.new({
		"provider": AuthProviderType.STEAM,
		"platform_user_id": str(steam_id),
		"display_name": persona_name,
		"is_platform_offline": not is_logged_on,
		"metadata": {
			"app_id": app_id,
			"steam_ui_language": ui_lang,
		}
	})

	var opts := options if options != null else AuthOptions.new()
	# 若处于 Steam 离线模式或业务配置无需在线 Ticket（纯本地直通），0ms 立即返回 Steam 身份凭证
	if not is_logged_on or not opts.require_ticket:
		return Result.ok(credential)

	_release_active_ticket()
	var ticket_res := await _request_web_api_ticket_async(steam, opts)
	if ticket_res.is_err():
		if opts.allow_offline_fallback:
			credential.is_platform_offline = true
			return Result.ok(credential)
		return ticket_res

	var ticket_info: Dictionary = ticket_res.value
	credential.raw_ticket = str(ticket_info.get("ticket_hex", ""))
	credential.ticket_handle = int(ticket_info.get("ticket_handle", 0))
	_active_ticket_handle = credential.ticket_handle
	return Result.ok(credential)
#endregion


#region Internal Steam Ticket Helpers
## 向 Steamworks 异步申请 WebAPI Ticket（优先使用 getAuthTicketForWebApi，向下兼容 getAuthSessionTicket）。
func _request_web_api_ticket_async(steam: Object, opts: AuthOptions) -> Result:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "SceneTree unavailable for async Steam ticket acquisition.")

	var state := {
		"done": false,
		"result": 0,
		"handle": 0,
		"ticket_hex": "",
	}

	var on_web_ticket := func(ticket_handle: int, result_code: int, _ticket_size: int, ticket_bytes: Variant) -> void:
		state["done"] = true
		state["handle"] = ticket_handle
		state["result"] = result_code
		state["ticket_hex"] = _encode_ticket_hex(ticket_bytes)

	var on_session_ticket := func(ticket_handle: int, result_code: int) -> void:
		state["done"] = true
		state["handle"] = ticket_handle
		state["result"] = result_code

	var use_web_api_signal := steam.has_method("getAuthTicketForWebApi") and steam.has_signal("get_ticket_for_web_api")
	var use_legacy_signal := not use_web_api_signal and steam.has_method("getAuthSessionTicket")

	if use_web_api_signal:
		if not steam.is_connected("get_ticket_for_web_api", on_web_ticket):
			steam.connect("get_ticket_for_web_api", on_web_ticket, CONNECT_ONE_SHOT)
		var identity := opts.steam_service_identity if not opts.steam_service_identity.is_empty() else "game_backend"
		_active_ticket_handle = int(steam.call("getAuthTicketForWebApi", identity))
	elif use_legacy_signal:
		if steam.has_signal("get_auth_session_ticket_response") and not steam.is_connected("get_auth_session_ticket_response", on_session_ticket):
			steam.connect("get_auth_session_ticket_response", on_session_ticket, CONNECT_ONE_SHOT)
		var ticket_dict: Variant = steam.call("getAuthSessionTicket")
		if ticket_dict is Dictionary:
			var d := ticket_dict as Dictionary
			_active_ticket_handle = int(d.get("id", d.get("ticket", 0)))
			state["ticket_hex"] = _encode_ticket_hex(d.get("buffer", PackedByteArray()))
			if not steam.has_signal("get_auth_session_ticket_response"):
				state["done"] = true
				state["result"] = 1
	else:
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "Steam singleton missing ticket acquisition methods.")

	var started_msec := Time.get_ticks_msec()
	var timeout_sec := maxf(0.5, opts.timeout_seconds)

	while not bool(state["done"]) and not _cancel_requested:
		if steam.has_method("run_callbacks"):
			steam.call("run_callbacks")
		await tree.process_frame
		if (Time.get_ticks_msec() - started_msec) / 1000.0 >= timeout_sec:
			break

	if use_web_api_signal and steam.is_connected("get_ticket_for_web_api", on_web_ticket):
		steam.disconnect("get_ticket_for_web_api", on_web_ticket)
	if use_legacy_signal and steam.has_signal("get_auth_session_ticket_response") and steam.is_connected("get_auth_session_ticket_response", on_session_ticket):
		steam.disconnect("get_auth_session_ticket_response", on_session_ticket)

	if _cancel_requested:
		_release_active_ticket()
		return Result.err_code(AuthError.USER_CANCELLED, "Steam ticket request was cancelled.")

	if not bool(state["done"]):
		_release_active_ticket()
		return Result.err_code(
			AuthError.TICKET_TIMEOUT,
			"Timed out waiting for Steam auth ticket after %.1f seconds." % timeout_sec
		)

	# Steam EResult k_EResultOK == 1
	if int(state["result"]) != 1 or str(state["ticket_hex"]).is_empty():
		_release_active_ticket()
		return Result.err_code(
			AuthError.CREDENTIAL_FAILED,
			"Steam auth ticket failed with EResult=%d." % int(state["result"])
		)

	return Result.ok({
		"ticket_handle": _active_ticket_handle if _active_ticket_handle > 0 else int(state["handle"]),
		"ticket_hex": str(state["ticket_hex"]),
	})


static func _encode_ticket_hex(raw: Variant) -> String:
	if raw is PackedByteArray:
		return (raw as PackedByteArray).hex_encode()
	if raw is Array:
		var bytes := PackedByteArray()
		for item in (raw as Array):
			bytes.append(int(item) & 0xFF)
		return bytes.hex_encode()
	if raw is String:
		return (raw as String).strip_edges()
	return ""


func _release_active_ticket() -> void:
	if _active_ticket_handle <= 0:
		return
	var steam := _get_steam_singleton()
	if steam != null and steam.has_method("cancelAuthTicket"):
		steam.call("cancelAuthTicket", _active_ticket_handle)
	_active_ticket_handle = 0


static func _get_steam_singleton() -> Object:
	if Engine.has_singleton(SINGLETON_STEAM):
		return Engine.get_singleton(SINGLETON_STEAM)
	return null


## 按需执行进程级 GodotSteam 单次初始化（调用 steamInitEx 或 steamInit），支持多实例重复安全调用。
static func _ensure_steam_initialized() -> bool:
	if _steam_initialized:
		return true
	var steam := _get_steam_singleton()
	if steam == null:
		return false
	if steam.has_method("isSteamRunning") and not bool(steam.call("isSteamRunning")):
		return false
	if steam.has_method("steamInitEx"):
		var init_res: Variant = steam.call("steamInitEx")
		if init_res is Dictionary:
			var status: int = int((init_res as Dictionary).get("status", -1))
			# STEAM_API_INIT_RESULT_OK == 0
			_steam_initialized = (status == 0)
			return _steam_initialized
	elif steam.has_method("steamInit"):
		var init_res: Variant = steam.call("steamInit")
		if init_res is Dictionary:
			_steam_initialized = bool((init_res as Dictionary).get("status", false)) or int((init_res as Dictionary).get("status", 0)) == 1
			return _steam_initialized
		elif init_res is bool:
			_steam_initialized = bool(init_res)
			return _steam_initialized
	return false
#endregion
