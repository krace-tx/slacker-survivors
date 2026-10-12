class_name RuntimeEnvironment
extends BaseRuntimeEnvironment

## 运行环境只读查询上下文。
##
## 启动时根据导出 Feature Tag 判定 5 档运行环境：
## LOCAL (本机) / EMULATOR (Android 模拟器 10.0.2.2) / DEV (开发服) / TEST (内测测试服) / PROD (线上生产服)。
## API 域名、日志级别等具体策略由各下游模块（如 [ApiCatalog]）自行读取状态分支处理。

#region Enums
enum Env {
	LOCAL,     ## 本地开发环境（PC/Mac 宿主机直连 127.0.0.1）
	EMULATOR,  ## Android 模拟器环境（通过 10.0.2.2 转发访问宿主机）
	DEV,       ## 开发联调服环境
	TEST,      ## 测试/内测/预发布服环境 (Staging/QA)
	PROD,      ## 线上生产正式服环境
}
#endregion

#region State
## 当前运行环境（只读）。
var current: Env:
	get:
		return _current

var _current: Env = Env.LOCAL
#endregion

#region Lifecycle
func _init() -> void:
	_detect()


func initialize() -> Result:
	return Result.ok()
#endregion

#region Public API
## 是否为线上生产环境
func is_prod() -> bool:
	return _current == Env.PROD


## 是否为测试/内测/预发布环境
func is_test() -> bool:
	return _current == Env.TEST


## 预发布环境别名（对齐 staging 命名习惯）
func is_staging() -> bool:
	return _current == Env.TEST


## 是否为开发联调环境
func is_dev() -> bool:
	return _current == Env.DEV


## 是否为 Android 模拟器调试环境
func is_emulator() -> bool:
	return _current == Env.EMULATOR


## 是否为本地电脑开发环境
func is_local() -> bool:
	return _current == Env.LOCAL


## 获取当前环境名称字符串（如 "PROD"、"TEST"、"DEV"、"EMULATOR"、"LOCAL"）。
func get_name() -> String:
	return Env.keys()[_current]


## 是否为编辑器运行环境。
func is_editor() -> bool:
	return OS.has_feature("editor")


## 是否运行在 Android 平台。
func is_android() -> bool:
	return OS.get_name() == "Android"


## 是否运行在 iOS 平台。
func is_ios() -> bool:
	return OS.get_name() == "iOS"


## 是否为移动端原生真机环境（非编辑器且为 Android 或 iOS）。
func is_mobile() -> bool:
	return not is_editor() and (is_android() or is_ios())


func _to_string() -> String:
	return get_name()
#endregion

#region Internal
## 判定逻辑见 [EnvDetector]。
func _detect() -> void:
	_current = EnvDetector.detect() as Env
#endregion
