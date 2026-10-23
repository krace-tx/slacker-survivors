class_name AuthCredential
extends BaseParams

## 第一阶段产物：平台原始身份凭证实体（Platform Authentication Credential）。[br]
##
## 由各平台 [AuthProviderAdapter]（Steam / Apple / Google / Guest / Custom）采集产出，
## 作为第二阶段 [AuthSessionVerifier]（本地直通或远端网关验签）的标准化输入。

## 签发该凭证的平台渠道标识（见 [AuthProviderType]）。
var provider: StringName = AuthProviderType.GUEST

## 平台侧唯一用户 ID（如 SteamID64 `"76561198000000000"`、Apple `sub`、Google PlayerID 或设备指纹摘要）。
var platform_user_id: String = ""

## 平台侧玩家展示昵称（如 Steam PersonaName、GameCenter 昵称）。
var display_name: String = "Player"

## 平台侧头像标识或 URL（可选）。
var avatar_url: String = ""

## 平台 SDK 签发的原始认证票据（如 Hex 编码的 Steam WebAPI Ticket、Apple IdentityToken、Google ServerAuthCode）。
var raw_ticket: String = ""

## 底层平台票据句柄（如 Steam `HAuthTicket`，用于在登出或销毁时调用 `cancelAuthTicket`）。
var ticket_handle: int = 0

## 签发时平台客户端是否处于离线模式（如 Steam Deck 离线模式 `loggedOn() == false`）。
var is_platform_offline: bool = false

## 平台附加元数据（如 AppID、语言偏好、设备平台等）。
var metadata: Dictionary = {}


func _init(dict: Dictionary = {}) -> void:
	super(dict)


## 判断当前凭证是否携带有效的平台用户标识
func is_valid() -> bool:
	return not String(provider).is_empty() and not platform_user_id.strip_edges().is_empty()
