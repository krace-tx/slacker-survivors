@abstract
class_name BaseFrameworkLogger
extends Subsystem

## 日志分级与诊断输出门面契约（Framework Logger Contract）。[br]
##
## 本抽象基类作为业务层与日志子系统交互的唯一规范入口，统一负责：[br]
## - 分级过滤输出：DEBUG / INFO / WARN / ERROR 结构化格式化；[br]
## - Tag 分类追踪与控制台 ANSI 颜色染色；[br]
## - 内存回溯缓冲区（Dump）记录，供崩溃报错或用户反馈上报提取。[br]
##
## 业务代码应统一通过 [code]App.logger[/code] 访问本契约提供的方法。


## 当前最低输出级别过滤阈值（参见 [LogLevel] 枚举常量，低于此级别的日志将被静默丢弃）。
var min_level: int = LogLevel.DEBUG


## 返回该子系统的全局唯一注册标识符。
func get_id() -> String:
	return "logger"


#region Public Logging APIs
## 输出调试级日志（DEBUG）。[br]
##
## 用于开发调试期间的高频临时信息，生产环境通常被过滤。[br]
##
## [param tag] 来源模块/业务标签（如 "Battle"、"Network"、"UI"）。[br]
## [param msg] 日志文本内容。
@abstract
func debug(tag: String, msg: String) -> void


## 输出常规运行信息日志（INFO）。[br]
##
## 记录关键生命周期事件、系统状态切换、主流程节点。[br]
##
## [param tag] 来源模块/业务标签。[br]
## [param msg] 日志文本内容。
@abstract
func info(tag: String, msg: String) -> void


## 输出警告信息日志（WARN）。[br]
##
## 记录非预期但未造成程序中断的潜在异常状态（如网络重试、资源回退保底）。[br]
##
## [param tag] 来源模块/业务标签。[br]
## [param msg] 日志文本内容。
@abstract
func warn(tag: String, msg: String) -> void


## 输出错误信息日志（ERROR）。[br]
##
## 记录严重阻断性故障，附带上下文堆栈并在终端进行高亮着色。[br]
##
## [param tag] 来源模块/业务标签。[br]
## [param msg] 日志文本内容。
@abstract
func error(tag: String, msg: String) -> void


## 导出当前内存缓冲区中记录的全部历史日志条目（Dump）。[br]
##
## 供崩溃诊断、异常弹窗或网络错误上报采集。[br]
## @return 返回换行拼接好的完整诊断日志纯文本。
@abstract
func dump() -> String


## 清空当前内存缓冲区中记录的全部历史日志。
@abstract
func clear() -> void
#endregion
