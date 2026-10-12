@abstract
class_name BaseUISystem
extends NodeSubsystem

## 全局 UI 画布分层与安全区系统门面契约（UI System Facade Contract）。[br]
##
## 本抽象基类作为引擎 UI 画布分层（CanvasLayer）与屏幕安全区（Safe Area）适配的基础设施，核心职责：[br]
## - 五大多层级管理：BACKGROUND(10) / MAIN(20) / POPUP(30) / TOAST(40) / TOP(50)；[br]
## - 屏幕安全区（Safe Area）计算与刘海屏/灵动岛边距适配；[br]
## - 统一画布挂载与清理。[br]
##
## 业务代码通过 [code]App.ui[/code] 获取对应的 CanvasLayer 容器。

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


#region Safe Area Adaptation
## 获取当前屏幕安全区四周内边距（针对异形屏/刘海/灵动岛/Home指示条）。[br]
## @return 返回包含 left, top, right, bottom 的边距字典。
@abstract
func get_safe_area_margins() -> Dictionary


## 为指定 Control 控件应用安全区外边距。[br]
## [param control] 需要应用安全区适配的根控件。
@abstract
func apply_safe_area(control: Control) -> void
#endregion
