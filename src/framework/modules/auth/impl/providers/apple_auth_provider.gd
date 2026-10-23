class_name AppleAuthProvider
extends AuthProviderAdapter

## Apple 生态认证适配器（iOS / macOS Sign in with Apple & GameCenter 反射桥接）。[br]
##
## 通过 [method Engine.has_singleton] 动态桥接原生插件单例（`AppleAuth` 或 `GameCenter`），
## 零硬编码依赖，支持跨项目在 iOS / macOS 发行时直接启用。

#region Constants
## Sign in with Apple 原生插件单例名
const SINGLETON_APPLE_AUTH: StringName = &"AppleAuth"
## Apple GameCenter 原生插件单例名
const SINGLETON_GAME_CENTER: StringName = &"GameCenter"
#endregion


#region AuthProviderAdapter Implementation
func get_provider_id() -> StringName:
	return AuthProviderType.APPLE


func get_provider_name() -> String:
	return "Apple Auth / GameCenter"


## 仅在 iOS 或 macOS 宿主平台且挂载了 AppleAuth / GameCenter 原生插件时返回 true。
func is_available() -> bool:
	var os := OS.get_name()
	if os != "iOS" and os != "macOS":
		return false
	return _get_singleton() != null


## 异步调用 Apple / GameCenter 登录授权并提取 IdentityToken 与用户唯一标识（sub / player_id）。
func acquire_credential_async(options: AuthOptions) -> Result:
	var singleton := _get_singleton()
	if singleton == null:
		return Result.err_code(
			AuthError.PROVIDER_UNAVAILABLE,
			"Apple authentication plugin singleton is not available on %s." % OS.get_name()
		)

	# 若插件提供同步已认证查询（如 GameCenter is_authenticated）
	if singleton.has_method("is_authenticated") and bool(singleton.call("is_authenticated")):
		return _build_credential_from_singleton(singleton)

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "SceneTree unavailable for Apple auth.")

	var state := {"done": false, "ok": false, "payload": {}}
	var on_completed := func(payload: Variant = {}) -> void:
		state["done"] = true
		state["ok"] = true
		if payload is Dictionary:
			state["payload"] = payload

	var on_error := func(err_msg: Variant = "") -> void:
		state["done"] = true
		state["ok"] = false
		state["payload"] = {"error": str(err_msg)}

	var sig_ok := "sign_in_completed" if singleton.has_signal("sign_in_completed") else "authenticated"
	var sig_err := "sign_in_failed" if singleton.has_signal("sign_in_failed") else "authentication_error"

	if singleton.has_signal(sig_ok) and not singleton.is_connected(sig_ok, on_completed):
		singleton.connect(sig_ok, on_completed, CONNECT_ONE_SHOT)
	if singleton.has_signal(sig_err) and not singleton.is_connected(sig_err, on_error):
		singleton.connect(sig_err, on_error, CONNECT_ONE_SHOT)

	if singleton.has_method("sign_in"):
		singleton.call("sign_in")
	elif singleton.has_method("authenticate"):
		singleton.call("authenticate")
	else:
		return _build_credential_from_singleton(singleton)

	var opts := options if options != null else AuthOptions.new()
	var timeout_sec := maxf(0.5, opts.timeout_seconds)
	var started_msec := Time.get_ticks_msec()

	while not bool(state["done"]):
		await tree.process_frame
		if (Time.get_ticks_msec() - started_msec) / 1000.0 >= timeout_sec:
			break

	if singleton.has_signal(sig_ok) and singleton.is_connected(sig_ok, on_completed):
		singleton.disconnect(sig_ok, on_completed)
	if singleton.has_signal(sig_err) and singleton.is_connected(sig_err, on_error):
		singleton.disconnect(sig_err, on_error)

	if not bool(state["done"]):
		return Result.err_code(AuthError.TICKET_TIMEOUT, "Apple sign-in timed out.")
	if not bool(state["ok"]):
		var payload_dict: Dictionary = state["payload"]
		return Result.err_code(AuthError.CREDENTIAL_FAILED, str(payload_dict.get("error", "Apple sign-in failed.")))

	return _build_credential_from_singleton(singleton, state["payload"] as Dictionary)


func _build_credential_from_singleton(singleton: Object, payload: Dictionary = {}) -> Result:
	var user_id := str(payload.get("user_id", "")).strip_edges()
	if user_id.is_empty() and singleton.has_method("get_player_id"):
		user_id = str(singleton.call("get_player_id")).strip_edges()
	if user_id.is_empty():
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "Apple auth returned empty user_id.")

	var display_name := str(payload.get("display_name", "")).strip_edges()
	if display_name.is_empty() and singleton.has_method("get_display_name"):
		display_name = str(singleton.call("get_display_name")).strip_edges()
	if display_name.is_empty():
		display_name = "ApplePlayer"

	var token := str(payload.get("identity_token", payload.get("token", ""))).strip_edges()
	if token.is_empty() and singleton.has_method("get_identity_token"):
		token = str(singleton.call("get_identity_token")).strip_edges()

	return Result.ok(AuthCredential.new({
		"provider": AuthProviderType.APPLE,
		"platform_user_id": user_id,
		"display_name": display_name,
		"raw_ticket": token,
		"metadata": {"os": OS.get_name()}
	}))


static func _get_singleton() -> Object:
	if Engine.has_singleton(SINGLETON_APPLE_AUTH):
		return Engine.get_singleton(SINGLETON_APPLE_AUTH)
	if Engine.has_singleton(SINGLETON_GAME_CENTER):
		return Engine.get_singleton(SINGLETON_GAME_CENTER)
	return null
