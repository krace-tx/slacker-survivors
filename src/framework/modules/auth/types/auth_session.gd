class_name AuthSession
extends BaseParams

## 第二阶段产物：游戏生效认证会话实体（Authenticated Game Session）。[br]
##
## 统一表达玩家在当前游戏运行期的权威身份、网络访问令牌（JWT）与存档槽归属标识。

## 游戏内全局唯一账号标识（如 `"steam_76561198000000000"`、`"guest_a1b2c3d4"` 或后端下发的 UUID）。
var account_id: String = ""

## 当前登录的平台渠道标识（见 [AuthProviderType]）。
var provider: StringName = AuthProviderType.GUEST

## 平台侧原始用户 ID（如 SteamID64）。
var platform_user_id: String = ""

## 平台 SDK 颁发的原始验证票据或授权码（如 Steam WebAPI Ticket 十六进制串，未请求时为空字符串）。
var platform_ticket: String = ""

## 玩家展示昵称。
var display_name: String = "Player"

## 玩家头像 URL 或标识。
var avatar_url: String = ""

## 后端签发的访问令牌（自动同步注入至 `App.net.set_auth_token`；单机/离线模式下为空字符串）。
var access_token: String = ""

## 后端签发的刷新令牌（供 `App.net` 401 Single-Flight 自动续期使用）。
var refresh_token: String = ""

## 访问令牌过期时间戳（Unix 毫秒；0 表示永不过期或单机直通会话）。
var expires_at_ms: int = 0

## 会话签发时间戳（Unix 毫秒）。
var issued_at_ms: int = 0

## 当前会话是否处于离线模式（Steam 离线模式、断网降级或纯本地游客）。
var is_offline: bool = false

## 当前会话是否为未绑定正式平台的设备游客账号。
var is_guest: bool = false

## 若本次会话刚完成“游客转正（Account Linking）”，记录原游客账号 ID 以便业务层迁移存档。
var linked_from_account_id: String = ""


func _init(dict: Dictionary = {}) -> void:
	super(dict)


## 判断当前会话是否有效
func is_valid() -> bool:
	return not account_id.strip_edges().is_empty()


## 判断当前会话是否持有在线后端签发的 Bearer Token
func has_access_token() -> bool:
	return not access_token.strip_edges().is_empty()


## 判断当前在线 Token 是否已过期
func is_token_expired(now_ms: int) -> bool:
	if expires_at_ms <= 0 or now_ms <= 0:
		return false
	return now_ms >= expires_at_ms
