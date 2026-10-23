class_name AuthSessionVerifier
extends RefCounted

## 第二阶段：会话校验与签发器抽象基类（Session Verifier & Issuer Strategy）。[br]
##
## 负责消费第一阶段 [AuthProviderAdapter] 产出的 [AuthCredential]，
## 校验其合法性并签发游戏内权威的 [AuthSession]（含本地直通模式与远端网关换票模式）。


## 校验平台凭证并签发 [AuthSession]。[br]
## @return 成功时 [member Result.value] 为 [Dictionary]：
##   [code]{"session": AuthSession, "server_time_ms": int}[/code]。
func verify_and_issue_async(_credential: AuthCredential, _options: AuthOptions, _now_ms: int) -> Result:
	return Result.err_code(AuthError.VERIFICATION_REJECTED, "Base session verifier cannot issue sessions.")


## 使用当前会话的 [member AuthSession.refresh_token] 异步续期会话（供 401 Single-Flight 回调调用）。
func refresh_session_async(_session: AuthSession, _options: AuthOptions, _now_ms: int) -> Result:
	return Result.err_code(AuthError.REFRESH_FAILED, "Session refresh is not supported by this verifier.")
