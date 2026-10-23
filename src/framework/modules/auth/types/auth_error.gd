class_name AuthError
extends RefCounted

## 认证与登录模块标准化错误码定义（Authentication Standard Error Codes）。[br]
##
## 严格遵循框架统一的 [code]{Module}.{Reason}[/code] 契约规范，配合 [FrameworkError] 与 [Result] 使用。

## 指定的登录渠道标识为空或非法
const INVALID_PROVIDER: String = "Auth.InvalidProvider"

## 目标登录渠道在当前平台或运行环境中不可用（如未启动 Steam 客户端或未挂载对应原生插件）
const PROVIDER_UNAVAILABLE: String = "Auth.ProviderUnavailable"

## 正在执行另一个登录或换票流程（防并发重入）
const ALREADY_AUTHENTICATING: String = "Auth.AlreadyAuthenticating"

## 向平台 SDK 请求认证票据（如 Steam WebAPI Ticket / Apple Token）超时
const TICKET_TIMEOUT: String = "Auth.TicketTimeout"

## 平台 SDK 拒绝签发票据或返回无效凭据
const CREDENTIAL_FAILED: String = "Auth.CredentialFailed"

## 玩家主动取消了平台登录授权弹窗（如 Apple / Google 登录取消）
const USER_CANCELLED: String = "Auth.UserCancelled"

## 远端认证网关不可达且当前禁用了离线降级策略
const GATEWAY_UNAVAILABLE: String = "Auth.GatewayUnavailable"

## 远端认证网关拒绝了平台票据（验签失败、票据过期或账号封禁）
const VERIFICATION_REJECTED: String = "Auth.VerificationRejected"

## 会话刷新失败（无有效 RefreshToken 或刷新令牌已过期）
const REFRESH_FAILED: String = "Auth.RefreshFailed"

## 账号升级绑定（Guest 转正）失败
const LINK_FAILED: String = "Auth.LinkFailed"
