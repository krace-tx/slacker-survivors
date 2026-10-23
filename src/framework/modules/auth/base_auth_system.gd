@abstract
class_name BaseAuthSystem
extends RefCounted

## 跨平台身份认证与会话系统公开门面契约（Authentication & Session System Facade Contract）。[br]
##
## 统一封装全平台登录与会话管理（对外入口为 [code]App.auth[/code]）：[br]
## - [b]多端凭证适配器解耦[/b]：透明桥接 Steam（GodotSteam WebAPI Ticket / 离线模式）、Apple（iOS/macOS）、Google Play（Android）、自定义 Token 与设备指纹游客（Guest）；[br]
## - [b]单机与自建后端双模切换[/b]：支持零网络依赖的本地直通签发（[LocalPassthroughVerifier]）与自建网关换票验签（[RemoteGatewayVerifier]）；[br]
## - [b]全框架自动协同[/b]：登录成功后自动将 Bearer Token 与 401 Single-Flight 静默续期钩子注入 `App.net`，并将服务端权威时间戳同步至 `App.clock`；[br]
## - [b]游客转正（Account Linking）[/b]：支持将本地设备游客平滑绑定升级为正式平台账号并保留原游客 ID 以供存档迁移。

#region Signals
## 当认证状态机发生迁移时触发（见 [AuthState]）。
signal state_changed(new_state: int, old_state: int)

## 当登录或账号绑定成功并签发有效 [AuthSession] 时触发。
signal authenticated(session: AuthSession)

## 当主动登出或会话失效被清除时触发。
signal logged_out(reason: String)

## 当登录或刷新过程中发生错误时触发（见 [AuthError]）。
signal auth_error(error_code: String, message: String)
#endregion


#region Authentication & Session Control
## 智能择优自动登录（启动期推荐调用）。[br]
## 自动按当前宿主环境探测最优渠道：[br]
## - 桌面端（Windows / macOS / Linux）：优先探测 Steam（含离线模式），未运行时回退至 Apple（macOS）或设备游客（Guest）；[br]
## - iOS：优先探测 Apple / GameCenter，不可用时回退至 Guest；[br]
## - Android：优先探测 Google Play Games，不可用时回退至 Guest。[br]
##
## [param options] 登录配置项，为 null 时采用默认配置。[br]
## @return 成功时 [member Result.value] 为 [AuthSession]；失败时携带 [AuthError]。
@abstract
func login_auto_async(options: AuthOptions = null) -> Result


## 指定具体平台渠道发起异步登录。[br]
##
## [param provider_id] 渠道标识（如 [constant AuthProviderType.STEAM]、[constant AuthProviderType.APPLE]、[constant AuthProviderType.GOOGLE]、[constant AuthProviderType.GUEST]）。[br]
## [param options] 登录配置项。[br]
## @return 成功时 [member Result.value] 为 [AuthSession]；失败时携带 [AuthError]。
@abstract
func login_with_provider_async(provider_id: StringName, options: AuthOptions = null) -> Result


## 使用外部已构造的 [AuthCredential] 直接执行会话验签与签发。[br]
##
## [param credential] 平台原始身份凭证。[br]
## [param options] 登录配置项。[br]
## @return 成功时 [member Result.value] 为 [AuthSession]。
@abstract
func login_with_credential_async(credential: AuthCredential, options: AuthOptions = null) -> Result


## 游客转正（Account Linking）：将当前设备游客会话绑定升级至指定的正式平台渠道（如 Steam / Apple / Google）。[br]
## 成功后新 [member AuthSession.linked_from_account_id] 会记录原游客账号 ID，便于业务层无缝迁移本地存档。[br]
##
## [param target_provider_id] 目标正式平台渠道标识。[br]
## [param options] 登录配置项。[br]
## @return 成功时 [member Result.value] 为升级后的 [AuthSession]。
@abstract
func link_provider_async(target_provider_id: StringName, options: AuthOptions = null) -> Result


## 使用当前会话的 RefreshToken 异步刷新访问令牌（同时被 `App.net` 的 401 Single-Flight 处理器自动调用）。
@abstract
func refresh_session_async() -> Result


## 登出当前会话，释放底层平台票据句柄（如 Steam `cancelAuthTicket`）并清空 `App.net` 鉴权令牌。
@abstract
func logout(reason: String = "user_logout") -> void
#endregion


#region Configuration & Provider Registry
## 配置默认是否启用自建后端网关换票验证及接口路径（可在 `BaseEnvProfile._on_configure` 中按环境激活）。
@abstract
func set_remote_gateway_enabled(
	enabled: bool,
	exchange_endpoint: String = "/v1/auth/exchange",
	refresh_endpoint: String = "/v1/auth/refresh"
) -> void


## 注册或覆盖自定义平台凭证适配器（支持扩展 TapTap / WeGame / Epic 等第三方 SDK）。
@abstract
func register_provider(provider: AuthProviderAdapter) -> void


## 查询指定平台渠道在当前运行宿主下是否可用就绪。
@abstract
func is_provider_available(provider_id: StringName) -> bool


## 获取当前运行宿主下所有可用就绪的平台渠道标识列表。
@abstract
func get_available_providers() -> Array[StringName]
#endregion


#region State & Session Queries
## 获取当前认证状态机枚举值（见 [AuthState]）。
@abstract
func get_state() -> int


## 查询当前是否已登录（含在线认证与离线会话模式）。
@abstract
func is_authenticated() -> bool


## 查询当前会话是否处于离线模式（如 Steam 离线模式或本机设备游客）。
@abstract
func is_offline_session() -> bool


## 查询当前会话是否为未绑定正式平台的设备游客账号。
@abstract
func is_guest_session() -> bool


## 获取当前生效的 [AuthSession] 实例（未登录时返回 null）。
@abstract
func get_session() -> AuthSession


## 获取当前登录玩家的游戏内唯一账号 ID（未登录时返回空字符串）。
@abstract
func get_account_id() -> String


## 获取当前生效会话所属的平台渠道标识（未登录时返回空 `StringName`）。
@abstract
func get_active_provider() -> StringName


## 获取认证子系统的运行时诊断指标快照。
@abstract
func get_diagnostics() -> Dictionary
#endregion
