class_name EnvType
extends RefCounted

## 运行环境部署档位枚举定义（Environment Deployment Tier Types）。[br]
##
## 调用形如 [code]EnvType.PROD[/code]、[code]EnvType.DEV[/code]、[code]EnvType.DEFAULT[/code]。[br]
## 作为跨层公开契约，供业务层与框架层在注册 [BaseEnvProfile] 或判断环境档位时使用。

enum {
	DEFAULT = -1, ## 默认兜底环境槽位（注册 Profile 时作为未命中特定环境的回退基底）
	LOCAL = 0,    ## 本地开发环境（PC/Mac 宿主机直连 127.0.0.1）
	EMULATOR = 1, ## 模拟器环境（如 Android 模拟器通过 10.0.2.2 转发访问宿主机）
	DEV = 2,      ## 开发联调服环境
	TEST = 3,     ## 内网 QA 测试服环境
	STAGING = 4,  ## 灰度预发布服环境
	PROD = 5,     ## 线上生产正式服环境
}

## 有效部署环境枚举值对应的标准大写名称表（下标与 LOCAL..PROD 一一对应）。
const NAMES: Array[String] = [
	"LOCAL",
	"EMULATOR",
	"DEV",
	"TEST",
	"STAGING",
	"PROD",
]


## 判断给定的整数是否为合法的具体部署环境档位（LOCAL..PROD）。
static func is_valid(env_type: int) -> bool:
	return env_type >= LOCAL and env_type <= PROD


## 判断给定的整数是否为合法的注册槽位（包含 DEFAULT 与 LOCAL..PROD）。
static func is_valid_slot(env_type: int) -> bool:
	return env_type == DEFAULT or is_valid(env_type)


## 将环境枚举值转换为标准大写名称（如 [code]"PROD"[/code]、[code]"LOCAL"[/code]）。
static func to_name(env_type: int) -> String:
	if is_valid(env_type):
		return NAMES[env_type]
	if env_type == DEFAULT:
		return "DEFAULT"
	return "UNKNOWN"


## 将环境名称字符串（大小写不敏感）解析为 [EnvType] 枚举值；无法识别时返回 [constant DEFAULT] (-1)。
static func from_name(raw_name: String) -> int:
	match raw_name.strip_edges().to_lower():
		"prod", "production":
			return PROD
		"staging", "pre", "preprod":
			return STAGING
		"test", "qa", "testing":
			return TEST
		"dev", "development":
			return DEV
		"emulator", "emu":
			return EMULATOR
		"local", "localhost":
			return LOCAL
		_:
			return DEFAULT
