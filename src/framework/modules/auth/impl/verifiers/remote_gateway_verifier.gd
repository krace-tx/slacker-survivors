class_name RemoteGatewayVerifier
extends AuthSessionVerifier

## 远端自建后端网关换票验证器（Remote Gateway Ticket Exchange Verifier）。[br]
##
## 核心职责：[br]
## 1. 将平台 [AuthCredential]（如 Steam WebAPI Ticket、Apple IdentityToken、Google ServerAuthCode）POST 至自建后端网关；[br]
## 2. 解析后端颁发的 [code]account_id[/code]、[code]access_token[/code]、[code]refresh_token[/code] 与权威时间戳 [code]server_time_ms[/code]；[br]
## 3. 当后端网络不可达且启用了 [member AuthOptions.allow_offline_fallback] 时，自动无感降级为 [LocalPassthroughVerifier] 离线会话，绝不阻断单机进游；[br]
## 4. 提供 [method refresh_session_async] 对接 `App.net` 的 401 Single-Flight 令牌自动续期。

#region Dependencies
var _network_service: BaseNetworkClient
var _local_fallback: LocalPassthroughVerifier


func _init(network_service: BaseNetworkClient = null, local_fallback: LocalPassthroughVerifier = null) -> void:
	_network_service = network_service
	_local_fallback = local_fallback if local_fallback != null else LocalPassthroughVerifier.new()


func set_network_service(network_service: BaseNetworkClient) -> void:
	_network_service = network_service
#endregion


#region AuthSessionVerifier Implementation
## 向自建后端网关发送平台凭证换取业务会话与 JWT；若网络不可达且允许降级，自动回退至本地离线会话。
func verify_and_issue_async(credential: AuthCredential, options: AuthOptions, now_ms: int) -> Result:
	if credential == null or not credential.is_valid():
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "Cannot verify invalid credential.")

	var opts := options if options != null else AuthOptions.new()

	# 若平台本身已处于离线态（如 Steam 离线模式），或网络客户端不可用，按策略优雅降级为本地会话
	if credential.is_platform_offline or _network_service == null:
		if opts.allow_offline_fallback:
			return await _fallback_to_local_offline_async(credential, opts, now_ms)
		return Result.err_code(AuthError.GATEWAY_UNAVAILABLE, "Remote auth gateway is unavailable while offline.")

	var endpoint := opts.exchange_endpoint.strip_edges()
	if endpoint.is_empty():
		endpoint = "/v1/auth/exchange"

	var req_body := {
		"provider": String(credential.provider),
		"platform_user_id": credential.platform_user_id,
		"display_name": credential.display_name,
		"ticket": credential.raw_ticket,
		"metadata": credential.metadata,
	}

	var net_res := await _network_service.post_request(endpoint, req_body)
	if net_res.is_err():
		if net_res.is_retryable() and opts.allow_offline_fallback:
			return await _fallback_to_local_offline_async(credential, opts, now_ms)
		return Result.err_code(
			AuthError.VERIFICATION_REJECTED,
			"Remote gateway rejected credential [%s]: %s" % [net_res.error_code(), net_res.error_message()]
		)

	if not (net_res.value is Dictionary):
		return Result.err_code(AuthError.VERIFICATION_REJECTED, "Invalid response format from auth gateway.")

	var resp: Dictionary = net_res.value as Dictionary
	var payload: Dictionary = resp.get("data", resp) as Dictionary if resp.get("data") is Dictionary else resp

	var account_id := str(payload.get("account_id", "")).strip_edges()
	if account_id.is_empty():
		account_id = "%s_%s" % [String(credential.provider).to_lower(), credential.platform_user_id]

	var display_name := str(payload.get("display_name", credential.display_name)).strip_edges()
	var access_token := str(payload.get("access_token", "")).strip_edges()
	var refresh_token := str(payload.get("refresh_token", "")).strip_edges()
	var expires_at_ms := int(payload.get("expires_at_ms", 0))
	var server_time_ms := int(payload.get("server_time_ms", 0))
	var is_guest := credential.provider == AuthProviderType.GUEST

	var session := AuthSession.new({
		"account_id": account_id,
		"provider": credential.provider,
		"platform_user_id": credential.platform_user_id,
		"display_name": display_name,
		"avatar_url": str(payload.get("avatar_url", credential.avatar_url)),
		"access_token": access_token,
		"refresh_token": refresh_token,
		"expires_at_ms": expires_at_ms,
		"issued_at_ms": server_time_ms if server_time_ms > 0 else maxi(0, now_ms),
		"is_offline": false,
		"is_guest": is_guest,
	})

	return Result.ok({
		"session": session,
		"server_time_ms": server_time_ms,
	})


## 向自建后端刷新端点提交 RefreshToken 续期 AccessToken（供 App.net 401 Single-Flight 处理器自动调用）。
func refresh_session_async(session: AuthSession, options: AuthOptions, now_ms: int) -> Result:
	if session == null or session.refresh_token.strip_edges().is_empty():
		return Result.err_code(AuthError.REFRESH_FAILED, "No refresh_token available in current session.")
	if _network_service == null:
		return Result.err_code(AuthError.GATEWAY_UNAVAILABLE, "NetworkClient unavailable for token refresh.")

	var opts := options if options != null else AuthOptions.new()
	var endpoint := opts.refresh_endpoint.strip_edges()
	if endpoint.is_empty():
		endpoint = "/v1/auth/refresh"

	var net_res := await _network_service.post_request(endpoint, {
		"account_id": session.account_id,
		"refresh_token": session.refresh_token,
	})
	if net_res.is_err() or not (net_res.value is Dictionary):
		return Result.err_code(
			AuthError.REFRESH_FAILED,
			"Failed to refresh session token: %s" % (net_res.error_message() if net_res.is_err() else "invalid JSON")
		)

	var resp: Dictionary = net_res.value as Dictionary
	var payload: Dictionary = resp.get("data", resp) as Dictionary if resp.get("data") is Dictionary else resp
	var new_access := str(payload.get("access_token", "")).strip_edges()
	if new_access.is_empty():
		return Result.err_code(AuthError.REFRESH_FAILED, "Refresh response missing access_token.")

	session.access_token = new_access
	var new_refresh := str(payload.get("refresh_token", "")).strip_edges()
	if not new_refresh.is_empty():
		session.refresh_token = new_refresh
	session.expires_at_ms = int(payload.get("expires_at_ms", session.expires_at_ms))
	var server_time_ms := int(payload.get("server_time_ms", 0))
	session.issued_at_ms = server_time_ms if server_time_ms > 0 else maxi(0, now_ms)
	session.is_offline = false

	return Result.ok({
		"session": session,
		"server_time_ms": server_time_ms,
	})


func _fallback_to_local_offline_async(credential: AuthCredential, opts: AuthOptions, now_ms: int) -> Result:
	var res := await _local_fallback.verify_and_issue_async(credential, opts, now_ms)
	if res.is_ok():
		var info: Dictionary = res.value
		var sess: AuthSession = info["session"]
		sess.is_offline = true
	return res
