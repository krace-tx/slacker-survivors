class_name FrameworkLogger
extends BaseFrameworkLogger

## 全项目统一日志记录器。
##
## 提供 tag 分类 + 级别过滤 + 环形缓冲(崩溃/上报时可导出最近若干条)。
## Boot 在 [RuntimeEnvironment] 之后创建；[method _init] 按环境设 [member min_level]。
##
## 控制台走 [method @GlobalScope.print_rich]（编辑器 BBCode，终端 ANSI）。
## WARN / ERROR 另外 [code]push_warning[/code] / [code]push_error[/code]，进调试器面板。
## 缓冲 [method dump] 仍是纯文本。级别、标签与颜色定义见 [LogLevel]。

const _MAX_ENTRIES: int = 1000   ## 环形缓冲容量,超出丢弃最旧一条

var _entries: PackedStringArray = PackedStringArray()


## [param env] 非空时按环境设 [member min_level]：PROD→WARN，LOCAL/DEV→DEBUG。
func _init(env: BaseRuntimeEnvironment = null) -> void:
	if env == null:
		return
	min_level = LogLevel.WARN if env.is_prod() else LogLevel.DEBUG


func initialize() -> Result:
	return Result.ok()


func dispose() -> void:
	clear()


#region Public API
func debug(tag: String, msg: String) -> void:
	_log(LogLevel.DEBUG, tag, msg)


func info(tag: String, msg: String) -> void:
	_log(LogLevel.INFO, tag, msg)


func warn(tag: String, msg: String) -> void:
	_log(LogLevel.WARN, tag, msg)


func error(tag: String, msg: String) -> void:
	_log(LogLevel.ERROR, tag, msg)


## 导出全部缓冲日志为纯文本(供崩溃上报 / 调试面板 / 用户反馈附带)。
func dump() -> String:
	return "\n".join(_entries)


## 清空缓冲。
func clear() -> void:
	_entries.clear()


## 静态格式化与控制台富文本打印（供启动初期或无实例快速打印复用）。[param level] 取 [LogLevel] 常量。
static func print_raw(level: int, tag: String, msg: String) -> void:
	_print_line(level, _format(level, tag, msg))
#endregion


#region Internal
func _log(level: int, tag: String, msg: String) -> void:
	if level < min_level:
		return

	# 时间戳走 TimeUtils(系统墙钟),同时进缓冲,dump() 导出也带时间。
	var line := _format(level, tag, msg)
	_entries.append(line)
	if _entries.size() > _MAX_ENTRIES:
		_entries.remove_at(0)
	_print_line(level, line)


static func _format(level: int, tag: String, msg: String) -> String:
	return "[%s] [%s] [%s] %s" % [TimeUtils.now_string(), LogLevel.TAGS[level], tag, msg]


static func _print_line(level: int, line: String) -> void:
	print_rich("[color=%s]%s[/color]" % [LogLevel.COLORS[level], line.replace("[", "[lb]")])
	match level:
		LogLevel.WARN:
			push_warning(line)
		LogLevel.ERROR:
			push_error(line)
#endregion
