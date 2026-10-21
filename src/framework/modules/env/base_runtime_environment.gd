@abstract
class_name BaseRuntimeEnvironment
extends RefCounted

## 运行环境与诊断能力门面契约（Runtime Environment Contract）。[br]
##
## 本抽象基类作为业务层与环境探测子系统交互的唯一规范入口，统一负责：[br]
## - 区分 LOCAL（本地单机）、DEV（开发调试）、TEST（测试服）、STAGING（预发布）、PROD（正式生产）等运行态；[br]
## - 提供统一的只读诊断查询接口，屏蔽平台特征探测细节；[br]
##
## 业务代码应统一通过 [code]App.env[/code] 访问本契约提供的方法。


#region Public Queries
## 当前是否为正式发布生产环境 (PROD)。[br]
##
## @return 返回布尔值：正式发布服时为 true，开发/测试服为 false。
@abstract
func is_prod() -> bool


## 当前是否为内网自动化测试或 QA 验证环境 (TEST)。[br]
##
## @return 返回布尔值。
@abstract
func is_test() -> bool


## 当前是否为灰度预发布环境 (STAGING)。[br]
##
## @return 返回布尔值。
@abstract
func is_staging() -> bool


## 当前是否为开发调试环境 (DEV)。[br]
##
## @return 返回布尔值：连接开发网关或勾选开发标记时为 true。
@abstract
func is_dev() -> bool


## 当前是否运行在 PC 虚拟机 / 编辑器调试模拟器中 (EMULATOR)。[br]
##
## @return 返回布尔值。
@abstract
func is_emulator() -> bool


## 当前是否为完全离线的纯本地环境 (LOCAL)。[br]
##
## @return 返回布尔值。
@abstract
func is_local() -> bool


## 获取当前运行环境的标准化英文标识名称（如 "prod"、"dev"、"local" 等）。[br]
##
## @return 返回全小写环境名称字符串。
@abstract
func get_name() -> String
#endregion
