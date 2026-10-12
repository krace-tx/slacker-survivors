class_name EnvDetector
extends RefCounted

## 运行环境判定器（私有实现，仅供 [RuntimeEnvironment] 使用）。[br]
## 只读取导出 Feature Tag，不缓存状态。

## 判定优先级：prod > test/staging > dev > emulator > 默认 LOCAL（编辑器/开发默认直连本地）。[br]
## 返回 [enum RuntimeEnvironment.Env] 值。
static func detect() -> int:
	if OS.has_feature("prod") or OS.has_feature("production"):
		return RuntimeEnvironment.Env.PROD
	if OS.has_feature("test") or OS.has_feature("staging"):
		return RuntimeEnvironment.Env.TEST
	if OS.has_feature("dev") or OS.has_feature("development"):
		return RuntimeEnvironment.Env.DEV
	if OS.has_feature("emulator"):
		return RuntimeEnvironment.Env.EMULATOR
	return RuntimeEnvironment.Env.LOCAL
