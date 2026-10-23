class_name GuestAuthProvider
extends AuthProviderAdapter

## 本机硬件设备指纹游客认证适配器（Device Fingerprint Guest Provider）。[br]
##
## 通过 [method CryptoUtils.derive_passphrase] 基于硬件设备指纹确定性派生唯一的 16 位十六进制游客 ID，[br]
## 100% 离线可用，作为无第三方平台环境或网络不可达时的零阻塞保底身份源。

const _GUEST_KEY_DOMAIN: String = "framework:auth:guest_identity:v1"


func get_provider_id() -> StringName:
	return AuthProviderType.GUEST


func get_provider_name() -> String:
	return "Device Guest Identity"


func is_available() -> bool:
	return true


func acquire_credential_async(_options: AuthOptions) -> Result:
	var derived_hex := CryptoUtils.derive_passphrase(_GUEST_KEY_DOMAIN, "guest_identity", true)
	var short_uid := derived_hex.substr(0, 16) if derived_hex.length() >= 16 else "local_default"
	var credential := AuthCredential.new({
		"provider": AuthProviderType.GUEST,
		"platform_user_id": short_uid,
		"display_name": "Player_%s" % short_uid.substr(0, 6).to_upper(),
		"raw_ticket": derived_hex,
		"is_platform_offline": true,
		"metadata": {
			"os": OS.get_name(),
		}
	})
	return Result.ok(credential)
