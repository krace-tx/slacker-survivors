@abstract
class_name BaseUISystem
extends NodeSubsystem

## 全局 UI 系统门面契约（UI System Facade Contract）。[br]
##
## 本抽象基类作为业务层展示模态弹窗、管理 CanvasLayer 层级与提示信息的唯一规范入口，核心职责：[br]
## - 五大多层级管理：BACKGROUND(10) / MAIN(20) / POPUP(30) / TOAST(40) / TOP(50)；[br]
## - 模态弹窗历史栈（Modal Stack）：自动调度背景半透明全屏暗色遮罩（Dimmer），拦截下层点击穿透；[br]
## - 硬件返回键拦截中继：按下 ESC 或安卓返回键时，优先关闭顶层活动弹窗；[br]
## - 全局轻量 Toast 提示调度。[br]
##
## 业务代码应统一通过 [code]App.ui[/code] 访问本契约提供的方法。


#region Enums & Constants
## UI 视图树核心层级常量定义
enum Layer {
	BACKGROUND = 10,  ## 背景层（全屏动态背景、视差贴图）
	MAIN = 20,        ## 场景主界面层（HUD、操作栏、血条）
	POPUP = 30,       ## 模态弹窗层（结算页、选卡升级、设置菜单）
	TOAST = 40,       ## 飘字提示层（轻量系统通知、获得道具浮窗）
	TOP = 50,         ## 系统顶层（全屏 Loading 遮罩、Debug 控制台）
}
#endregion


## 返回该子系统的全局唯一注册标识符。
func get_id() -> String:
	return "ui"


#region Layer Management
## 获取指定层级类型的 [CanvasLayer] 节点。[br]
##
## [param layer_type] 画布层级枚举（参见 [enum Layer]）。[br]
## @return 返回对应的 [CanvasLayer] 容器节点。
@abstract
func get_layer(layer_type: int) -> CanvasLayer
#endregion


#region Modal Dialog Management
## 异步打开一个模态弹窗（Popup 语义）。[br]
##
## 自动实例化指定路径的弹窗预制体，将其挂载到 POPUP 层，并压入内部模态弹窗栈；[br]
## 首次压栈时自动唤起暗色全屏遮罩并开启防穿透拦截。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param path] 弹窗 [code].tscn[/code] 资源路径。[br]
## [param params] 传递给弹窗的入参字典（在弹窗的 [_on_show] 中接收）。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 为实例化的 [BaseDialog] 控件。
@abstract
func open_popup(path: String, params: Dictionary = {}) -> Result


## 关闭指定的模态弹窗实例。[br]
##
## 若未传参则默认关闭当前栈顶弹窗。当栈内所有弹窗均被关闭时，系统自动淡出并隐藏全屏暗色遮罩。[br]
##
## [param dialog] 需要关闭的弹窗控件；若为 null 则关闭栈顶弹窗。
@abstract
func close_popup(dialog: Control = null) -> void


## 快速关闭当前栈顶的活动模态弹窗（常由 Android 返回键或 ESC 快捷键驱动）。[br]
##
## @return 返回布尔值：若成功关闭了一个弹窗返回 true；若当前没有任何弹窗展示返回 false。
@abstract
func close_top_popup() -> bool


## 查询当前屏幕上是否正展示有任何激活的模态弹窗。[br]
##
## @return 返回布尔值。
@abstract
func has_modal() -> bool
#endregion


#region Toast & Tips
## 弹出轻量级全屏居中或底部浮动提示信息（Toast）。[br]
##
## 提示框展示指定秒数后自动渐隐销毁，不阻断玩家任何点击交互操作。[br]
##
## [param message] 提示文本内容。[br]
## [param duration] 屏幕驻留时长（秒，默认 2.0）。
@abstract
func show_toast(message: String, duration: float = 2.0) -> void
#endregion
