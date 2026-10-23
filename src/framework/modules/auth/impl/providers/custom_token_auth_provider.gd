class_name CustomTokenAuthProvider
extends AuthProviderAdapter

## 自定义令牌与第三方 OAuth 渠道认证适配器（TapTap / WeGame / 自建账号系统）。[br]
##
## 将业务层通过外部 OAuth 弹窗、短信验证码或账号密码获取的 [code]custom_user_id[/code] 与 [code]custom_token[/code]
## 封装为标准化 [AuthCredential]，无缝接入统一的会话签发与网关换票管线。


func get_provider_id() -> StringName:
	return AuthProviderType.CUSTOM


func get_provider_name() -> String:
	return "Custom Token / OAuth Provider"


func is_available() -> bool:
	return true


func acquire_credential_async(options: AuthOptions) -> Result:
	if options == null or options.custom_user_id.strip_edges().is_empty():
		return Result.err_code(
			AuthError.CREDENTIAL_FAILED,
			"Custom auth provider requires non-empty 'custom_user_id' in AuthOptions."
		)

	var display_name := options.custom_display_name.strip_edges()
	if display_name.is_empty():
		display_name = "User_%s" % options.custom_user_id.substr(0, mini(6, options.custom_user_id.length()))

	var credential := AuthCredential.new({
		"provider": AuthProviderType.CUSTOM,
		"platform_user_id": options.custom_user_id.strip_edges(),
		"display_name": display_name,
		"raw_ticket": options.custom_token.strip_edges(),
		"is_platform_offline": options.custom_token.strip_edges().is_empty(),
	})
	return Result.ok(credential)
