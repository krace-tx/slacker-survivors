class_name GameEnvProfile
extends BaseEnvProfile

## 游戏多环境配置策略适配器（位于 `src/game/shared/service/env/`）。[br]
##
## 负责按当前激活的 [EnvType] 装载对应的 [GameEnvConfig]（`.tres`）静态资源，
## 并在启动阶段一次性将全局存档加密策略、网关地址与请求签名注入 `App.storage` 与 `App.net`。

#region Constants & Fields
const _LOG_TAG: String = "Env"

## 当前环境绑定的 `.tres` 静态配置资源路径
var config_path: String = ""
## 当前已装载生效的强类型环境配置实例（只读）
var config: GameEnvConfig = null
#endregion


#region Lifecycle & Polymorphic Hook
func _init(p_config_path: String = "") -> void:
	super._init()
	config_path = p_config_path.strip_edges()


func _on_configure(env: BaseRuntimeEnvironment) -> void:
	config = _load_env_config(config_path)

	# 1. 注册全局核心存档（saves/）加密与压缩策略（config/ 设备偏好自动豁免）
	if App != null and App.storage != null:
		var clean_save_secret: String = config.save_encryption_secret.strip_edges()
		if config.enable_save_encryption and not clean_save_secret.is_empty():
			App.storage.set_save_encryption(
				clean_save_secret,
				config.bind_save_to_device,
				config.compress_saves,
				config.allow_plaintext_save_fallback
			)
		else:
			App.storage.clear_save_encryption()

	# 2. 同步远端 API 网关地址与 HTTP 请求防篡改签名
	if App != null and App.net != null:
		App.net.set_base_url(config.api_base_url.strip_edges())
		var clean_net_secret: String = config.request_signing_secret.strip_edges()
		if not clean_net_secret.is_empty():
			if App.clock != null:
				App.net.set_request_signing(clean_net_secret, App.clock.now_msec)
			else:
				App.net.set_request_signing(clean_net_secret)
		else:
			App.net.clear_request_signing()

	if App != null and App.logger != null:
		App.logger.info(
			_LOG_TAG,
			"Activated '%s' env profile (%s) -> save_encryption=%s, bind_device=%s, compress=%s, plain_fallback=%s" % [
				env.get_name(),
				config_path if not config_path.is_empty() else "default",
				str(App.storage.is_save_encryption_enabled() if App.storage != null else false),
				str(config.bind_save_to_device),
				str(config.compress_saves),
				str(config.allow_plaintext_save_fallback),
			]
		)


static func _load_env_config(path: String) -> GameEnvConfig:
	if not path.is_empty() and ResourceLoader.exists(path):
		var loaded: Resource = ResourceLoader.load(path)
		if loaded is GameEnvConfig:
			return loaded as GameEnvConfig
	return GameEnvConfig.new()
#endregion
