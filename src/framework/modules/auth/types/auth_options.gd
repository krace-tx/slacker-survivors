class_name AuthOptions
extends BaseParams

## 认证登录配置参数契约实体（Authentication Options Entity）。[br]
##
## 继承自 [BaseParams]，支持 Fluent Builder 链式调用与 Dictionary 双向序列化，
## 用于向 [method BaseAuthSystem.login_auto_async] 或 [method BaseAuthSystem.login_with_provider_async] 传递单次认证策略。
##
## [b]链式构造示例：[/b]
## [codeblock]
## var opts := AuthOptions.create() \
##     .with_provider(AuthProviderType.STEAM) \
##     .with_require_ticket(true, "game_backend") \
##     .with_remote_gateway(true, "/v1/auth/exchange") \
##     .with_offline_fallback(true)
## [/codeblock]

#region Options Properties
## 首选登录渠道标识（见 [AuthProviderType]，默认 [constant AuthProviderType.AUTO] 自动按宿主平台择优）。
var preferred_provider: StringName = AuthProviderType.AUTO

## 当首选在线平台或远端网关不可达时，是否允许优雅降级为平台离线态或本机设备游客（Guest）。默认为 [code]true[/code]。
var allow_offline_fallback: bool = true

## 是否需要向平台 SDK 申请在线验证票据（如 Steam WebAPI Ticket、Google ServerAuthCode）。[br]
## 纯单机模式下可设为 [code]false[/code] 以跳过异步票据握手实现 0ms 瞬时登录。默认为 [code]true[/code]。
var require_ticket: bool = true

## Steam [code]getAuthTicketForWebApi[/code] 使用的服务端身份标识（通用默认值 [code]"game_backend"[/code]，可由各项目按需覆盖）。
var steam_service_identity: String = "game_backend"

## 是否启用自建后端网关换票验证：[br]
## - [code]false[/code]：使用客户端本地直通签发器（[LocalPassthroughVerifier]）；[br]
## - [code]true[/code]：使用远端网关换票验证器（[RemoteGatewayVerifier]）。默认为 [code]false[/code]。
var use_remote_gateway: bool = false

## 自建后端登录换票 API 相对路径或完整 URL。默认为 [code]"/v1/auth/exchange"[/code]。
var exchange_endpoint: String = "/v1/auth/exchange"

## 自建后端刷新 Token API 相对路径或完整 URL。默认为 [code]"/v1/auth/refresh"[/code]。
var refresh_endpoint: String = "/v1/auth/refresh"

## 平台 SDK 取证或网关请求的最大等待超时秒数（下限保护 `0.5s`）。默认为 [code]8.0[/code] 秒。
var timeout_seconds: float = 8.0

## 自定义令牌或第三方渠道授权码（供 [constant AuthProviderType.CUSTOM] 渠道使用）。
var custom_token: String = ""

## 自定义渠道的用户唯一标识（供 [constant AuthProviderType.CUSTOM] 渠道使用）。
var custom_user_id: String = ""

## 自定义渠道的显示昵称（供 [constant AuthProviderType.CUSTOM] 渠道使用）。
var custom_display_name: String = ""
#endregion


func _init(dict: Dictionary = {}) -> void:
	super(dict)


#region Fluent Builder API
## 静态语义工厂：创建并返回一个新的 [AuthOptions] 实例。
static func create(dict: Dictionary = {}) -> AuthOptions:
	return AuthOptions.new(dict)


## 链式设置首选登录平台渠道（见 [AuthProviderType]）。
func with_provider(p_provider: StringName) -> AuthOptions:
	preferred_provider = p_provider
	return self


## 链式设置当在线渠道或网关不可达时是否允许降级为离线会话或本机游客。
func with_offline_fallback(p_allow: bool) -> AuthOptions:
	allow_offline_fallback = p_allow
	return self


## 链式设置是否向平台 SDK 申请在线验证票据，以及可选的 Steam WebAPI 服务身份标识。
func with_require_ticket(p_require: bool, p_steam_identity: String = "game_backend") -> AuthOptions:
	require_ticket = p_require
	if not p_steam_identity.strip_edges().is_empty():
		steam_service_identity = p_steam_identity.strip_edges()
	return self


## 链式开启或关闭自建后端网关换票验证，并可指定自定义换票与续期接口路径。
func with_remote_gateway(
	p_enabled: bool,
	p_exchange_endpoint: String = "/v1/auth/exchange",
	p_refresh_endpoint: String = "/v1/auth/refresh"
) -> AuthOptions:
	use_remote_gateway = p_enabled
	if not p_exchange_endpoint.strip_edges().is_empty():
		exchange_endpoint = p_exchange_endpoint.strip_edges()
	if not p_refresh_endpoint.strip_edges().is_empty():
		refresh_endpoint = p_refresh_endpoint.strip_edges()
	return self


## 链式设置平台 SDK 异步取证的最大超时时间（秒）。
func with_timeout(p_timeout_seconds: float) -> AuthOptions:
	timeout_seconds = maxf(0.5, p_timeout_seconds)
	return self


## 链式注入自定义渠道（[constant AuthProviderType.CUSTOM]）的用户 ID、令牌与展示昵称。
func with_custom_credentials(
	p_user_id: String,
	p_token: String,
	p_display_name: String = ""
) -> AuthOptions:
	preferred_provider = AuthProviderType.CUSTOM
	custom_user_id = p_user_id.strip_edges()
	custom_token = p_token.strip_edges()
	custom_display_name = p_display_name.strip_edges()
	return self
#endregion
