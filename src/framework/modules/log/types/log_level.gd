class_name LogLevel
extends RefCounted

## 日志级别（枚举命名空间）。调用形如 [code]LogLevel.WARN[/code]。[br]
## 同时给出每个级别的控制台标签与颜色，供 [FrameworkLogger] 与启动早期的 [method FrameworkLogger.print_raw] 共用。

enum {
	DEBUG,  ## 调试细节，PROD 环境默认屏蔽
	INFO,   ## 常规流程
	WARN,   ## 可恢复异常，额外进调试器面板
	ERROR,  ## 失败，额外进调试器面板
}

## 级别 → 输出标签
const TAGS: Array[String] = ["DEBUG", "INFO", "WARN", "ERR"]

## 级别 → 控制台颜色
const COLORS: Array[String] = [
	"#3B82F6",  # DEBUG 亮蓝 (Tailwind blue-500)
	"#D1D5DB",  # INFO 灰白 (Tailwind gray-300)
	"#F59E0B",  # WARN 橙黄 (Tailwind amber-500)
	"#EF4444",  # ERROR 亮红 (Tailwind red-500)
]
