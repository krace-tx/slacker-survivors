class_name GameEnvService
extends RefCounted

## 游戏全局多环境策略注册与查询服务（位于 `src/game/shared/service/env/`）。[br]
##
## [b]核心职责：[/b][br]
## 1. 统一维护 [EnvType] 到 `res://src/resources/envs/env_*.tres`（[GameEnvConfig]）的映射关系；[br]
## 2. 提供幂等的 [method setup_and_activate] 启动入口（供 [BootstrapScene]、[SyncSessionTask] 及 F6 独立调试兜底调用），
##    确保全局核心存档加密策略在任何存档读写前已完成一次性注入。

#region Constants
const _ERR_ENV_MISSING: String = "Env.ServiceMissing"

const ENV_LOCAL_PATH: String = "res://src/resources/envs/env_local.tres"
const ENV_DEV_PATH: String = "res://src/resources/envs/env_dev.tres"
const ENV_STAGING_PATH: String = "res://src/resources/envs/env_staging.tres"
const ENV_PROD_PATH: String = "res://src/resources/envs/env_prod.tres"
#endregion


#region Public API
## 幂等注册所有环境档位的 [GameEnvProfile] 并立即激活当前运行环境策略。
static func setup_and_activate() -> Result:
	if App == null or App.env == null:
		return Result.err_code(_ERR_ENV_MISSING, "App.env service is not available.")

	if not App.env.has_profile():
		App.env.register_profile(EnvType.DEFAULT, GameEnvProfile.new(ENV_LOCAL_PATH)) \
			.register_profile(EnvType.LOCAL, GameEnvProfile.new(ENV_LOCAL_PATH)) \
			.register_profile(EnvType.EMULATOR, GameEnvProfile.new(ENV_DEV_PATH)) \
			.register_profile(EnvType.DEV, GameEnvProfile.new(ENV_DEV_PATH)) \
			.register_profile(EnvType.TEST, GameEnvProfile.new(ENV_STAGING_PATH)) \
			.register_profile(EnvType.STAGING, GameEnvProfile.new(ENV_STAGING_PATH)) \
			.register_profile(EnvType.PROD, GameEnvProfile.new(ENV_PROD_PATH))

	return App.env.activate_profile()


## 获取当前生效的 [GameEnvConfig] 实例（若尚未激活则自动触发惰性激活）。
static func get_current_config() -> GameEnvConfig:
	if App != null and App.env != null:
		setup_and_activate()
		var profile: GameEnvProfile = App.env.get_profile() as GameEnvProfile
		if profile != null and profile.config != null:
			return profile.config
	return GameEnvConfig.new()


## 当前运行环境是否已开启全局核心存档加密保护。
static func is_save_encryption_enabled() -> bool:
	setup_and_activate()
	if App != null and App.storage != null:
		return App.storage.is_save_encryption_enabled()
	return false


## 获取当前运行环境配置的远端业务网关基础地址（为空表示单机离线模式）。
static func get_api_base_url() -> String:
	return get_current_config().api_base_url.strip_edges()
#endregion
