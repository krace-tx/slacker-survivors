class_name AuthProviderAdapter
extends RefCounted

## 多平台身份凭证供给适配器抽象基类（Authentication Provider Adapter Contract）。[br]
##
## 负责隔离底层第三方平台 SDK（如 GodotSteam、iOS Apple/GameCenter、Android Google Play Games、自建 Token 或本机指纹）的 API 差异，[br]
## 统一通过动态反射探测与异步回调转化为标准化的 [AuthCredential] 契约实体。


## 初始化装配钩子
func setup() -> void:
	pass


## 释放销毁钩子（如取消悬挂的平台 Ticket 句柄）
func dispose() -> void:
	cancel_pending()


## 获取当前适配器对应的渠道标识（见 [AuthProviderType]）
func get_provider_id() -> StringName:
	return AuthProviderType.GUEST


## 获取当前适配器的可读显示名称（供日志与诊断使用）
func get_provider_name() -> String:
	return "BaseAuthProvider"


## 探测当前运行宿主与环境中该平台 SDK 是否可用并处于就绪态
func is_available() -> bool:
	return false


## 异步向平台 SDK 采集身份凭证。[br]
## @return 成功时 [member Result.value] 为 [AuthCredential]；失败时携带 [AuthError] 标准错误码。
func acquire_credential_async(_options: AuthOptions) -> Result:
	return Result.err_code(AuthError.PROVIDER_UNAVAILABLE, "Base auth provider cannot acquire credentials.")


## 取消正在等待中的平台异步取证请求或释放已签发的平台票据
func cancel_pending() -> void:
	pass
