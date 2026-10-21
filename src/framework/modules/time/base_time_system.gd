@abstract
class_name BaseTimeSystem
extends RefCounted

## 权威时间系统门面契约（Time System Facade Contract）。[br]
##
## 本抽象基类作为业务层获取游戏世界时间的唯一规范入口，核心职责：[br]
## - 防设备改时作弊：基于服务器下发的权威 Unix 毫秒校准本地单调运行 tick（Time.get_ticks_msec）；[br]
## - 业务逻辑（每日重置、体力恢复、限时活动、冷却时间戳等）严禁直接读取客户端 OS 墙钟，统一使用 [method now]；[br]
## - 状态透明：提供 [method is_trusted] 指示当前时间是否已同服务端同步校准。
##
## 业务代码应统一通过 [code]App.time[/code] 访问本契约提供的方法。


#region Public Time APIs
## 获取当前游戏权威 Unix 时间戳（单位：秒）。[br]
##
## 若已与服务器校准，返回由服务器时间结合单调时钟计算的不可作弊时间；[br]
## 若未校准，安全降级为本地系统时钟（此时 [method is_trusted] 返回 false）。[br]
## @return 返回 Unix 秒级时间戳整数。
@abstract
func now() -> int


## 获取当前游戏权威 Unix 时间戳（单位：毫秒）。[br]
##
## @return 返回 Unix 毫秒级时间戳整数。
@abstract
func now_msec() -> int


## 接收服务端返回的权威 Unix 毫秒时间戳，执行本地单调基准时钟校准。[br]
##
## 校准成功后，时间流逝将完全解绑操作系统日期设置，杜绝修改手机时间作弊。[br]
##
## [param server_unix_msec] 服务端下发的当前 Unix 毫秒时间戳。[br]
## @return 返回 [Result] 结果对象（时间戳小于等于 0 时返回失败）。
@abstract
func sync(server_unix_msec: int) -> Result


## 查询当前时间是否已经成功与服务器完成对齐校准。[br]
##
## @return 返回布尔值：true 表示当前时间绝对可信；false 表示仍处在未校准的本地降级状态。
@abstract
func is_trusted() -> bool
#endregion
