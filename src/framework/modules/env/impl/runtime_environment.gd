class_name RuntimeEnvironment
extends BaseRuntimeEnvironment

## 运行环境只读边界快照与多环境配置策略调度实现。
##
## 1. 启动（[method _init]）时一次性探测并固化三大正交维度的客观事实：
##    - 部署目标域（[EnvType]）：优先级为 构造注入 > 命令行参数(--env=xxx) > 环境变量(APP_ENV) > Feature Tag > 默认 LOCAL；
##    - 宿主与构建形态：Editor / DebugBuild / Feature Tag；
##    - 操作系统与硬件平台：Desktop / Mobile / Web / 具体 OS。
## 2. 采用 **策略模式 + 模板方法模式** 管理多环境配置（[BaseEnvProfile]）：
##    - 支持按 [EnvType] 注册策略类（[Script]）或实例，按当前环境自动解析（支持回退 [constant EnvType.DEFAULT]）并执行 [method BaseEnvProfile.configure]。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"env"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = []
#endregion

#region Constants
const _ENV_VAR_KEY: String = "APP_ENV"
const _CMDLINE_PREFIX: String = "--env="
const _CMDLINE_FLAG: String = "--env"
#endregion

#region Immutable Snapshot State
## 当前部署环境档位（只读，取值为 [EnvType] 枚举常量）。
var current: int:
	get:
		return _current

var _current: int = EnvType.LOCAL
var _platform_name: String = ""
var _is_editor: bool = false
var _is_debug_build: bool = false
var _is_android: bool = false
var _is_ios: bool = false
var _is_web: bool = false
var _is_windows: bool = false
var _is_macos: bool = false
var _is_linux: bool = false
var _is_mobile: bool = false
var _is_desktop: bool = false

## 已注册的环境配置策略映射表：int (EnvType) -> Variant (Script | BaseEnvProfile)
var _registered_profiles: Dictionary = {}
## 当前已激活的环境配置策略实例缓存
var _active_profile: BaseEnvProfile = null
#endregion

#region Lifecycle
## [param override_env] 可选的构造覆盖环境（传入 [EnvType] 枚举值，供单元测试使用；默认 -1 表示自动探测）。[br]
## [param override_platform] 可选的操作系统名称覆盖（供单元测试模拟目标平台；默认空字符串表示读取 OS.get_name()）。
func _init(override_env: int = EnvType.DEFAULT, override_platform: String = "") -> void:
	_capture_snapshot(override_env, override_platform)


func initialize() -> Result:
	return Result.ok()


func dispose() -> void:
	_registered_profiles.clear()
	_active_profile = null
#endregion

#region 1. Deployment Tier Queries
func get_env_type() -> int:
	return _current


func is_local() -> bool:
	return _current == EnvType.LOCAL


func is_emulator() -> bool:
	return _current == EnvType.EMULATOR


func is_dev() -> bool:
	return _current == EnvType.DEV


func is_test() -> bool:
	return _current == EnvType.TEST


func is_staging() -> bool:
	return _current == EnvType.STAGING


func is_prod() -> bool:
	return _current == EnvType.PROD


func get_name() -> String:
	return EnvType.to_name(_current)
#endregion

#region 2. Host & Build Mode Queries
func is_editor() -> bool:
	return _is_editor


func is_debug_build() -> bool:
	return _is_debug_build


func has_feature(tag: String) -> bool:
	if tag.is_empty():
		return false
	return OS.has_feature(tag)
#endregion

#region 3. OS & Hardware Platform Queries
func get_platform_name() -> String:
	return _platform_name


func is_desktop() -> bool:
	return _is_desktop


func is_mobile() -> bool:
	return _is_mobile


func is_android() -> bool:
	return _is_android


func is_ios() -> bool:
	return _is_ios


func is_web() -> bool:
	return _is_web


func is_windows() -> bool:
	return _is_windows


func is_macos() -> bool:
	return _is_macos


func is_linux() -> bool:
	return _is_linux


func _to_string() -> String:
	return "%s (%s%s)" % [
		get_name(),
		_platform_name,
		", Editor" if _is_editor else (", Debug" if _is_debug_build else "")
	]
#endregion

#region 4. Environment Profile Strategy & Dispatch
func register_profile(env_type: int, profile_or_script: Variant) -> BaseRuntimeEnvironment:
	if not EnvType.is_valid_slot(env_type):
		push_error("RuntimeEnvironment.register_profile: Invalid env_type '%d'." % env_type)
		return self
	if profile_or_script == null or not (profile_or_script is BaseEnvProfile or profile_or_script is Script):
		push_error("RuntimeEnvironment.register_profile: Expected BaseEnvProfile instance or Script.")
		return self

	_registered_profiles[env_type] = profile_or_script
	# 若注册的是当前所处环境（或当前尚无特定环境绑定时更新了 DEFAULT），重置激活缓存以便重新解析
	if env_type == _current or (env_type == EnvType.DEFAULT and not _registered_profiles.has(_current)):
		_active_profile = null
	return self


func activate_profile() -> Result:
	if _active_profile != null and _active_profile.is_configured():
		return Result.ok(_active_profile)

	var candidate: Variant = _registered_profiles.get(_current, null)
	if candidate == null:
		candidate = _registered_profiles.get(EnvType.DEFAULT, null)
	if candidate == null:
		return Result.err_code(
			"Env.ProfileNotFound",
			"No BaseEnvProfile registered for environment '%s' or DEFAULT." % get_name()
		)

	var instance := _instantiate_profile(candidate)
	if instance == null:
		return Result.err_code(
			"Env.InvalidProfile",
			"Registered profile for environment '%s' does not inherit BaseEnvProfile." % get_name()
		)

	_active_profile = instance
	return _active_profile.configure(self)


func get_profile() -> BaseEnvProfile:
	if _active_profile == null and has_profile():
		var res := activate_profile()
		if res.is_err():
			return null
	return _active_profile


func has_profile() -> bool:
	return _active_profile != null or _registered_profiles.has(_current) or _registered_profiles.has(EnvType.DEFAULT)


static func _instantiate_profile(candidate: Variant) -> BaseEnvProfile:
	if candidate is BaseEnvProfile:
		return candidate as BaseEnvProfile
	if candidate is Script:
		var script := candidate as Script
		if script.can_instantiate():
			var obj: Variant = script.new()
			if obj is BaseEnvProfile:
				return obj as BaseEnvProfile
	return null
#endregion

#region Internal Snapshot Detection
func _capture_snapshot(override_env: int, override_platform: String) -> void:
	_current = _detect_deployment_tier(override_env)
	_is_editor = OS.has_feature("editor")
	_is_debug_build = OS.is_debug_build()
	_platform_name = override_platform if not override_platform.is_empty() else OS.get_name()

	_is_android = (_platform_name == "Android")
	_is_ios = (_platform_name == "iOS")
	_is_web = (_platform_name == "Web") or OS.has_feature("web")
	_is_windows = (_platform_name == "Windows")
	_is_macos = (_platform_name == "macOS")
	_is_linux = (
		_platform_name == "Linux"
		or _platform_name == "FreeBSD"
		or _platform_name == "NetBSD"
		or _platform_name == "OpenBSD"
		or _platform_name == "BSD"
	)
	_is_mobile = not _is_editor and (_is_android or _is_ios)
	_is_desktop = (_is_windows or _is_macos or _is_linux)


## 判定优先级：构造覆盖 > 命令行参数(--env=xxx) > 环境变量(APP_ENV) > 导出 Feature Tag > 默认 LOCAL。
static func _detect_deployment_tier(override_env: int) -> int:
	# 1. 构造显式注入（单元测试优先）
	if EnvType.is_valid(override_env):
		return override_env

	# 2. 启动命令行参数（支持编辑器或测试包通过 --env=dev / --env dev 快速切换）
	var cmd_env := _parse_cmdline_env()
	if EnvType.is_valid(cmd_env):
		return cmd_env

	# 3. 操作系统环境变量（APP_ENV=dev）
	var os_env_str := OS.get_environment(_ENV_VAR_KEY).strip_edges()
	if not os_env_str.is_empty():
		var parsed_os_env := EnvType.from_name(os_env_str)
		if EnvType.is_valid(parsed_os_env):
			return parsed_os_env

	# 4. 导出包 Feature Tag（优先级：prod > staging > test > dev > emulator）
	if OS.has_feature("prod") or OS.has_feature("production"):
		return EnvType.PROD
	if OS.has_feature("staging"):
		return EnvType.STAGING
	if OS.has_feature("test") or OS.has_feature("qa"):
		return EnvType.TEST
	if OS.has_feature("dev") or OS.has_feature("development"):
		return EnvType.DEV
	if OS.has_feature("emulator"):
		return EnvType.EMULATOR

	# 5. 默认兜底：本机开发环境
	return EnvType.LOCAL


static func _parse_cmdline_env() -> int:
	# 优先检查用户参数（-- 之后的参数），再检查引擎启动参数
	for args: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		var count := args.size()
		for i in count:
			var arg := args[i].strip_edges()
			if arg.begins_with(_CMDLINE_PREFIX):
				var val := arg.substr(_CMDLINE_PREFIX.length()).strip_edges()
				var parsed := EnvType.from_name(val)
				if EnvType.is_valid(parsed):
					return parsed
			elif arg == _CMDLINE_FLAG and i + 1 < count:
				var parsed := EnvType.from_name(args[i + 1].strip_edges())
				if EnvType.is_valid(parsed):
					return parsed
	return EnvType.DEFAULT
#endregion
