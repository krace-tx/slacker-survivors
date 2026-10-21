@abstract
class_name BaseSceneRouter
extends Node

## 顶层场景路由与转场调度门面契约（Scene Router Facade Contract）。[br]
##
## 本抽象基类作为业务层触发场景加载、压栈、出栈与转场流水线的唯一规范入口，核心职责：[br]
## - 场景历史栈管理：支持深度回退栈（Stack Navigation），精准维护场景历史层级；[br]
## - 流式视觉转场调度：内置平滑淡入淡出、溶解揭开与 Apple 级景深弹性缩放；[br]
## - 声明式生命周期驱动：场景切换时严格按顺序分发 [method BaseScene._on_enter]、[method BaseScene._on_exit]、[method BaseScene._on_pause]、[method BaseScene._on_resume] 钩子；[br]
## - 转场防误触中继：转场动画执行期间自动挂起全局防点击穿透护盾。[br]
##
## 业务代码应统一通过 [code]App.scene[/code] 访问本契约提供的方法。


#region Public Queries
## 获取当前栈顶处于激活展示态的场景实例。[br]
##
## @return 返回栈顶的 [BaseScene] 实例；若当前无激活场景则返回 null。
@abstract
func current() -> BaseScene


## 获取当前场景历史栈的深度深度（层数）。[br]
##
## @return 返回大于等于 0 的整数。
@abstract
func depth() -> int


## 查询当前场景栈是否为空（尚未挂载任何有效场景）。[br]
##
## @return 返回布尔值。
@abstract
func is_empty() -> bool
#endregion


#region Public Scene Navigation APIs
## 替换当前场景（Replace 语义）。[br]
##
## 清空当前场景并将新场景置于栈顶。旧场景触发 [_on_exit] 并销毁，新场景触发 [_on_enter]。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param path] 新场景的 [code].tscn[/code] 资源绝对路径（[code]res://[/code] 开头）。[br]
## [param params] 跨场景传递的动态参数字典（在新场景的 [_on_enter] 中接收）。[br]
## [param transition] 转场动画类型（见 [SceneTransitionType] 常量，默认 [code]SceneTransitionType.AUTO[/code]）。[br]
## @return 返回 [Result] 对象，表示切换是否成功完成。
@abstract
func replace(
	path: String,
	params: Dictionary = {},
	transition: int = SceneTransitionType.AUTO
) -> Result


## 压入新场景（Push 语义）。[br]
##
## 当前场景保留在栈内并触发 [_on_pause]，新场景压入栈顶并触发 [_on_enter]。[br]
## 常用于在战斗或关卡中临时打开二级全屏页面。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param path] 新场景的 [code].tscn[/code] 路径。[br]
## [param params] 传递给新场景的参数字典。[br]
## [param transition] 转场动画类型。[br]
## @return 返回 [Result] 对象。
@abstract
func push(
	path: String,
	params: Dictionary = {},
	transition: int = SceneTransitionType.AUTO
) -> Result


## 弹出当前栈顶场景（Pop 语义）。[br]
##
## 当前场景触发 [_on_exit] 并销毁出栈，下层被压住的旧场景重见天日并触发 [_on_resume]。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param params] 回传给被恢复场景的参数字典（在下层场景的 [_on_resume] 中接收）。[br]
## [param transition] 转场动画类型。[br]
## @return 返回 [Result] 对象（若当前栈深度为 1 则禁止出栈并返回错误）。
@abstract
func pop(
	params: Dictionary = {},
	transition: int = SceneTransitionType.AUTO
) -> Result


## 将已预先实例化的场景对象作为当前根节点绑定入栈（主要供启动器或首屏初始化使用）。[br]
##
## [param path] 场景对应的源路径标识。[br]
## [param scene] 已实例化并就绪的 [BaseScene] 节点。[br]
## [param params] 初始入参字典。[br]
## @return 返回 [Result] 对象。
@abstract
func bind(path: String, scene: BaseScene, params: Dictionary = {}) -> Result
#endregion
