class_name GooglePlayAuthProvider
extends AuthProviderAdapter

## Google Play Games Services 认证适配器（Android GPGS v2 反射桥接）。[br]
##
## 通过 [method Engine.has_singleton] 动态桥接 Android 原生插件单例（`GodotPlayGameServices` 或 `GooglePlayAuth`），
## 零硬编码依赖，支持跨项目在 Android Google Play 发行时直接启用。

#region Constants
## Godot Play Game Services (GPGS v2) 原生插件单例名
const SINGLETON_GPGS: StringName = &"GodotPlayGameServices"
## Google Play Auth 备用原生插件单例名
const SINGLETON_GOOGLE_AUTH: StringName = &"GooglePlayAuth"
#endregion


#region AuthProviderAdapter Implementation
func get_provider_id() -> StringName:
	return AuthProviderType.GOOGLE


func get_provider_name() -> String:
	return "Google Play Games Services"


## 仅在 Android 宿主平台且挂载了 GPGS 原生插件时返回 true。
func is_available() -> bool:
	if OS.get_name() != "Android":
		return false
	return _get_singleton() != null


## 异步调用 Google Play Games Services 登录并提取 PlayerID 与服务端授权码（ServerAuthCode）。
func acquire_credential_async(options: AuthOptions) -> Result:
	var singleton := _get_singleton()
	if singleton == null:
		return Result.err_code(
			AuthError.PROVIDER_UNAVAILABLE,
			"Google Play Games Services singleton is not available on %s." % OS.get_name()
		)

	if singleton.has_method("isSignedIn") and bool(singleton.call("isSignedIn")):
		return _build_credential_from_singleton(singleton)

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "SceneTree unavailable for Google Play auth.")

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

	var sig_ok := "sign_in_succeeded" if singleton.has_signal("sign_in_succeeded") else "authenticated"
	var sig_err := "sign_in_failed" if singleton.has_signal("sign_in_failed") else "authentication_error"

	if singleton.has_signal(sig_ok) and not singleton.is_connected(sig_ok, on_completed):
		singleton.connect(sig_ok, on_completed, CONNECT_ONE_SHOT)
	if singleton.has_signal(sig_err) and not singleton.is_connected(sig_err, on_error):
		singleton.connect(sig_err, on_error, CONNECT_ONE_SHOT)

	if singleton.has_method("signIn"):
		singleton.call("signIn")
	elif singleton.has_method("sign_in"):
		singleton.call("sign_in")
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
		return Result.err_code(AuthError.TICKET_TIMEOUT, "Google Play sign-in timed out.")
	if not bool(state["ok"]):
		var payload_dict: Dictionary = state["payload"]
		return Result.err_code(AuthError.CREDENTIAL_FAILED, str(payload_dict.get("error", "Google Play sign-in failed.")))

	return _build_credential_from_singleton(singleton, state["payload"] as Dictionary)


func _build_credential_from_singleton(singleton: Object, payload: Dictionary = {}) -> Result:
	var player_id := str(payload.get("player_id", "")).strip_edges()
	if player_id.is_empty() and singleton.has_method("getPlayerId"):
		player_id = str(singleton.call("getPlayerId")).strip_edges()
	if player_id.is_empty():
		return Result.err_code(AuthError.CREDENTIAL_FAILED, "Google Play auth returned empty player_id.")

	var display_name := str(payload.get("display_name", "")).strip_edges()
	if display_name.is_empty() and singleton.has_method("getDisplayName"):
		display_name = str(singleton.call("getDisplayName")).strip_edges()
	if display_name.is_empty():
		display_name = "GooglePlayer"

	var auth_code := str(payload.get("server_auth_code", payload.get("token", ""))).strip_edges()
	if auth_code.is_empty() and singleton.has_method("getServerAuthCode"):
		auth_code = str(singleton.call("getServerAuthCode")).strip_edges()

	return Result.ok(AuthCredential.new({
		"provider": AuthProviderType.GOOGLE,
		"platform_user_id": player_id,
		"display_name": display_name,
		"raw_ticket": auth_code,
		"metadata": {"os": OS.get_name()}
	}))


static func _get_singleton() -> Object:
	if Engine.has_singleton(SINGLETON_GPGS):
		return Engine.get_singleton(SINGLETON_GPGS)
	if Engine.has_singleton(SINGLETON_GOOGLE_AUTH):
		return Engine.get_singleton(SINGLETON_GOOGLE_AUTH)
	return null
