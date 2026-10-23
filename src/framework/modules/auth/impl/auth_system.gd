class_name AuthSystem
extends BaseAuthSystem

## 跨平台身份认证与会话系统核心实现（Authentication & Session System Orchestrator）。[br]
##
## 遵循单一职责与显式依赖注入原则，统筹调度：[br]
## 1. [b]第一阶段（平台取证）[/b]：管理 [SteamAuthProvider]、[AppleAuthProvider]、[GooglePlayAuthProvider]、[CustomTokenAuthProvider] 与 [GuestAuthProvider]；[br]
## 2. [b]第二阶段（会话签发）[/b]：根据配置在 [LocalPassthroughVerifier]（单机直通）与 [RemoteGatewayVerifier]（后端网关换票）间路由；[br]
## 3. [b]第三阶段（框架协同）[/b]：向 [BaseNetworkClient] 注入 Bearer Token 与 401 静默续期钩子，向 [BaseClockSystem] 同步服务端权威时间戳。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"auth"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"env", &"logger", &"clock", &"net"]
#endregion

#region Injected Dependencies
var _env_service: BaseRuntimeEnvironment
var _log_service: BaseFrameworkLogger
var _clock_service: BaseClockSystem
var _network_service: BaseNetworkClient
#endregion

#region Internal Collaborators & State
var _providers: Dictionary = {} ## StringName -> AuthProviderAdapter
var _local_verifier: LocalPassthroughVerifier
var _remote_verifier: RemoteGatewayVerifier

var _state: int = AuthState.UNAUTHENTICATED
var _session: AuthSession = null
var _last_options: AuthOptions = null

var _default_use_remote_gateway: bool = false
var _default_exchange_endpoint: String = "/v1/auth/exchange"
var _default_refresh_endpoint: String = "/v1/auth/refresh"
#endregion


#region Lifecycle
func _init(
	env_service: BaseRuntimeEnvironment = null,
	log_service: BaseFrameworkLogger = null,
	clock_service: BaseClockSystem = null,
	network_service: BaseNetworkClient = null
) -> void:
	_env_service = env_service
	_log_service = log_service
	_clock_service = clock_service
	_network_service = network_service

	_local_verifier = LocalPassthroughVerifier.new()
	_remote_verifier = RemoteGatewayVerifier.new(_network_service, _local_verifier)

	register_provider(SteamAuthProvider.new())
	register_provider(AppleAuthProvider.new())
	register_provider(GooglePlayAuthProvider.new())
	register_provider(CustomTokenAuthProvider.new())
	register_provider(GuestAuthProvider.new())


func initialize() -> Result:
	for provider_key in _providers.keys():
		var provider: AuthProviderAdapter = _providers[provider_key]
		provider.setup()

	if _network_service != null:
		_network_service.set_unauthorized_handler(_on_network_unauthorized_async)

	_set_state(AuthState.UNAUTHENTICATED)
	_log_info("AuthSystem initialized. Available providers: %s" % [str(get_available_providers())])
	return Result.ok()


func dispose() -> void:
	logout("system_dispose")
	for provider_key in _providers.keys():
		var provider: AuthProviderAdapter = _providers[provider_key]
		provider.dispose()
	_providers.clear()
#endregion


#region BaseAuthSystem Public Facade
func login_auto_async(options: AuthOptions = null) -> Result:
	var opts := _prepare_options(options)
	var preferred := opts.preferred_provider
	if preferred != AuthProviderType.AUTO and not preferred.is_empty():
		var res := await login_with_provider_async(preferred, opts)
		if res.is_ok() or not opts.allow_offline_fallback or preferred == AuthProviderType.GUEST:
			return res
		_log_warn("Preferred provider '%s' failed (%s); falling back to Guest." % [
			String(preferred), res.error_message()
		])
		return await login_with_provider_async(AuthProviderType.GUEST, opts)

	var candidate_chain := _resolve_auto_provider_chain()
	var last_err: Result = null
	for provider_id: StringName in candidate_chain:
		if not is_provider_available(provider_id):
			continue
		var res := await login_with_provider_async(provider_id, opts)
		if res.is_ok():
			return res
		last_err = res
		if not opts.allow_offline_fallback:
			return res

	if last_err != null:
		return last_err
	return Result.err_code(AuthError.PROVIDER_UNAVAILABLE, "No available authentication provider succeeded.")


func login_with_provider_async(provider_id: StringName, options: AuthOptions = null) -> Result:
	if _state == AuthState.AUTHENTICATING:
		return Result.err_code(AuthError.ALREADY_AUTHENTICATING, "An authentication request is already in progress.")

	var clean_id := provider_id if not provider_id.is_empty() else AuthProviderType.GUEST
	if not _providers.has(clean_id):
		var msg := "Unregistered auth provider: '%s'." % String(clean_id)
		_emit_auth_error(AuthError.INVALID_PROVIDER, msg)
		return Result.err_code(AuthError.INVALID_PROVIDER, msg)

	var provider: AuthProviderAdapter = _providers[clean_id]
	var opts := _prepare_options(options)

	if not provider.is_available():
		if opts.allow_offline_fallback and clean_id != AuthProviderType.GUEST and is_provider_available(AuthProviderType.GUEST):
			_log_warn("Provider '%s' is unavailable; degrading to '%s'." % [
				String(clean_id), String(AuthProviderType.GUEST)
			])
			provider = _providers[AuthProviderType.GUEST]
		else:
			var unavail_msg := "Auth provider '%s' (%s) is not available." % [
				String(clean_id), provider.get_provider_name()
			]
			_emit_auth_error(AuthError.PROVIDER_UNAVAILABLE, unavail_msg)
			_set_state(AuthState.ERROR)
			return Result.err_code(AuthError.PROVIDER_UNAVAILABLE, unavail_msg)

	_set_state(AuthState.AUTHENTICATING)
	var cred_res := await provider.acquire_credential_async(opts)
	if cred_res.is_err():
		if opts.allow_offline_fallback and provider.get_provider_id() != AuthProviderType.GUEST and is_provider_available(AuthProviderType.GUEST):
			_log_warn("Credential acquisition on '%s' failed (%s); falling back to Guest." % [
				String(provider.get_provider_id()), cred_res.error_message()
			])
			var guest_provider: AuthProviderAdapter = _providers[AuthProviderType.GUEST]
			cred_res = await guest_provider.acquire_credential_async(opts)

		if cred_res.is_err():
			_emit_auth_error(cred_res.error_code(), cred_res.error_message())
			_set_state(AuthState.ERROR)
			return cred_res

	var credential := cred_res.value as AuthCredential
	return await _verify_and_activate_credential_async(credential, opts, "")


func login_with_credential_async(credential: AuthCredential, options: AuthOptions = null) -> Result:
	if _state == AuthState.AUTHENTICATING:
		return Result.err_code(AuthError.ALREADY_AUTHENTICATING, "An authentication request is already in progress.")
	if credential == null or not credential.is_valid():
		var msg := "Provided AuthCredential is null or invalid."
		_emit_auth_error(AuthError.CREDENTIAL_FAILED, msg)
		return Result.err_code(AuthError.CREDENTIAL_FAILED, msg)

	var opts := _prepare_options(options)
	_set_state(AuthState.AUTHENTICATING)
	return await _verify_and_activate_credential_async(credential, opts, "")


func link_provider_async(target_provider_id: StringName, options: AuthOptions = null) -> Result:
	if _state == AuthState.AUTHENTICATING:
		return Result.err_code(AuthError.ALREADY_AUTHENTICATING, "An authentication request is already in progress.")
	if target_provider_id.is_empty() or target_provider_id == AuthProviderType.GUEST:
		return Result.err_code(AuthError.LINK_FAILED, "Cannot link account to empty or guest provider.")
	if not _providers.has(target_provider_id):
		return Result.err_code(AuthError.INVALID_PROVIDER, "Unknown target provider '%s'." % String(target_provider_id))

	var provider: AuthProviderAdapter = _providers[target_provider_id]
	if not provider.is_available():
		return Result.err_code(
			AuthError.PROVIDER_UNAVAILABLE,
			"Target provider '%s' is not available for account linking." % String(target_provider_id)
		)

	var prev_account_id := _session.account_id if (_session != null and _session.is_guest) else ""
	var opts := _prepare_options(options)
	opts.allow_offline_fallback = false

	_set_state(AuthState.AUTHENTICATING)
	var cred_res := await provider.acquire_credential_async(opts)
	if cred_res.is_err():
		_restore_state_from_session()
		return cred_res

	var credential := cred_res.value as AuthCredential
	if not prev_account_id.is_empty():
		credential.metadata["linked_from_account_id"] = prev_account_id

	var verify_res := await _verify_and_activate_credential_async(credential, opts, prev_account_id)
	if verify_res.is_err():
		_restore_state_from_session()
	return verify_res


func refresh_session_async() -> Result:
	if _session == null or not _session.is_valid():
		return Result.err_code(AuthError.REFRESH_FAILED, "Cannot refresh: no active session.")
	if _session.refresh_token.strip_edges().is_empty():
		return Result.err_code(AuthError.REFRESH_FAILED, "Current session has no refresh_token.")

	var opts := _last_options if _last_options != null else _prepare_options(null)
	var now_ms := _get_now_ms()
	var refresh_res := await _remote_verifier.refresh_session_async(_session, opts, now_ms)
	if refresh_res.is_err():
		_emit_auth_error(refresh_res.error_code(), refresh_res.error_message())
		return refresh_res

	var info: Dictionary = refresh_res.value
	_session = info["session"] as AuthSession
	var server_time_ms: int = int(info.get("server_time_ms", 0))
	_sync_framework_services(_session, server_time_ms)
	_set_state(AuthState.OFFLINE if _session.is_offline else AuthState.AUTHENTICATED)
	return Result.ok(_session)


func logout(reason: String = "user_logout") -> void:
	for provider_key in _providers.keys():
		var provider: AuthProviderAdapter = _providers[provider_key]
		provider.cancel_pending()

	var had_session := _session != null
	_session = null
	if _network_service != null:
		_network_service.set_auth_token("")

	_set_state(AuthState.UNAUTHENTICATED)
	if had_session:
		logged_out.emit(reason)


func set_remote_gateway_enabled(
	enabled: bool,
	exchange_endpoint: String = "/v1/auth/exchange",
	refresh_endpoint: String = "/v1/auth/refresh"
) -> void:
	_default_use_remote_gateway = enabled
	if not exchange_endpoint.strip_edges().is_empty():
		_default_exchange_endpoint = exchange_endpoint.strip_edges()
	if not refresh_endpoint.strip_edges().is_empty():
		_default_refresh_endpoint = refresh_endpoint.strip_edges()


func register_provider(provider: AuthProviderAdapter) -> void:
	if provider == null or provider.get_provider_id().is_empty():
		return
	_providers[provider.get_provider_id()] = provider


func is_provider_available(provider_id: StringName) -> bool:
	if not _providers.has(provider_id):
		return false
	var provider: AuthProviderAdapter = _providers[provider_id]
	return provider.is_available()


func get_available_providers() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _providers.keys():
		var pid: StringName = key as StringName
		var provider: AuthProviderAdapter = _providers[pid]
		if provider.is_available():
			result.append(pid)
	return result


func get_state() -> int:
	return _state


func is_authenticated() -> bool:
	return AuthState.is_logged_in(_state) and _session != null and _session.is_valid()


func is_offline_session() -> bool:
	return _session == null or _session.is_offline or _state == AuthState.OFFLINE


func is_guest_session() -> bool:
	return _session != null and _session.is_guest


func get_session() -> AuthSession:
	return _session


func get_account_id() -> String:
	return _session.account_id if _session != null else ""


func get_active_provider() -> StringName:
	return _session.provider if _session != null else &""


func get_diagnostics() -> Dictionary:
	return {
		"state": String(AuthState.to_string_name(_state)),
		"account_id": get_account_id(),
		"provider": String(get_active_provider()),
		"is_offline": is_offline_session(),
		"is_guest": is_guest_session(),
		"remote_gateway_enabled": _default_use_remote_gateway,
		"available_providers": get_available_providers(),
	}
#endregion


#region Internal Verification & Framework Synergy
func _verify_and_activate_credential_async(
	credential: AuthCredential,
	opts: AuthOptions,
	linked_from_id: String
) -> Result:
	var verifier: AuthSessionVerifier = (
		(_remote_verifier as AuthSessionVerifier)
		if opts.use_remote_gateway
		else (_local_verifier as AuthSessionVerifier)
	)
	var now_ms := _get_now_ms()
	var verify_res := await verifier.verify_and_issue_async(credential, opts, now_ms)
	if verify_res.is_err():
		_emit_auth_error(verify_res.error_code(), verify_res.error_message())
		_set_state(AuthState.ERROR)
		return verify_res

	var info: Dictionary = verify_res.value
	var new_session: AuthSession = info["session"] as AuthSession
	var server_time_ms: int = int(info.get("server_time_ms", 0))
	if not linked_from_id.is_empty() and linked_from_id != new_session.account_id:
		new_session.linked_from_account_id = linked_from_id

	_session = new_session
	_last_options = opts
	_sync_framework_services(_session, server_time_ms)

	var target_state := AuthState.OFFLINE if _session.is_offline else AuthState.AUTHENTICATED
	_set_state(target_state)
	_log_info("Authenticated as '%s' (%s) via provider '%s' [offline=%s]" % [
		_session.display_name, _session.account_id, String(_session.provider), str(_session.is_offline)
	])
	authenticated.emit(_session)
	return Result.ok(_session)


func _sync_framework_services(session: AuthSession, server_time_ms: int) -> void:
	if _network_service != null:
		if session != null and session.has_access_token():
			_network_service.set_auth_token(session.access_token)
		else:
			_network_service.set_auth_token("")

	if _clock_service != null and server_time_ms > 0:
		_clock_service.sync(server_time_ms)


func _on_network_unauthorized_async() -> Result:
	return await refresh_session_async()


func _resolve_auto_provider_chain() -> Array[StringName]:
	var os_name := OS.get_name()
	if os_name == "iOS":
		return [AuthProviderType.APPLE, AuthProviderType.GUEST]
	if os_name == "Android":
		return [AuthProviderType.GOOGLE, AuthProviderType.GUEST]
	if os_name == "macOS":
		return [AuthProviderType.STEAM, AuthProviderType.APPLE, AuthProviderType.GUEST]
	return [AuthProviderType.STEAM, AuthProviderType.GUEST]


func _prepare_options(options: AuthOptions) -> AuthOptions:
	if options != null:
		return options
	var opts := AuthOptions.new()
	opts.use_remote_gateway = _default_use_remote_gateway
	opts.exchange_endpoint = _default_exchange_endpoint
	opts.refresh_endpoint = _default_refresh_endpoint
	opts.require_ticket = _default_use_remote_gateway
	return opts


func _restore_state_from_session() -> void:
	if _session == null or not _session.is_valid():
		_set_state(AuthState.UNAUTHENTICATED)
	else:
		_set_state(AuthState.OFFLINE if _session.is_offline else AuthState.AUTHENTICATED)


func _get_now_ms() -> int:
	if _clock_service != null:
		return _clock_service.now_msec()
	return int(Time.get_unix_time_from_system() * 1000.0)


func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	if not AuthState.can_transition(_state, new_state):
		return
	var old_state := _state
	_state = new_state
	state_changed.emit(new_state, old_state)


func _emit_auth_error(code: String, message: String) -> void:
	_log_error("[%s] %s" % [code, message])
	auth_error.emit(code, message)


func _log_info(message: String) -> void:
	if _log_service != null:
		_log_service.info("Auth", message)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, "Auth", message)


func _log_warn(message: String) -> void:
	if _log_service != null:
		_log_service.warn("Auth", message)
	else:
		FrameworkLogger.print_raw(LogLevel.WARN, "Auth", message)


func _log_error(message: String) -> void:
	if _log_service != null:
		_log_service.error("Auth", message)
	else:
		FrameworkLogger.print_raw(LogLevel.ERROR, "Auth", message)
#endregion
