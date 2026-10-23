class_name LocalPassthroughVerifier
extends AuthSessionVerifier

## 纯客户端/单机直通会话签发器（Local Passthrough Session Verifier）。[br]
##
## 适用于 Steam 单机/买断制阶段、无自建后端环境或网络离线降级场景：[br]
## 直接基于平台 [AuthCredential] 签发确定性 [AuthSession]（[code]account_id = "<provider>_<platform_user_id>"[/code]），零网络延迟。


func verify_and_issue_async(credential: AuthCredential, _options: AuthOptions, now_ms: int) -> Result:
	if credential == null or not credential.is_valid():
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "Cannot issue local session from invalid credential.")

	var prov_str := String(credential.provider).strip_edges().to_lower()
	var uid_str := credential.platform_user_id.strip_edges()
	var account_id := "%s_%s" % [prov_str, uid_str]
	var is_guest := credential.provider == AuthProviderType.GUEST

	var session := AuthSession.new({
		"account_id": account_id,
		"provider": credential.provider,
		"platform_user_id": uid_str,
		"platform_ticket": credential.raw_ticket,
		"display_name": credential.display_name,
		"avatar_url": credential.avatar_url,
		"access_token": "",
		"refresh_token": "",
		"expires_at_ms": 0,
		"issued_at_ms": maxi(0, now_ms),
		"is_offline": credential.is_platform_offline or is_guest,
		"is_guest": is_guest,
	})

	return Result.ok({
		"session": session,
		"server_time_ms": 0,
	})
