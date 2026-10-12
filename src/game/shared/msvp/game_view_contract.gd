class_name GameViewContract
extends RefCounted

## MSVP 架构 · 视图层契约规范说明 (View Contract)。[br]
##
## 视图层（View）在 Godot 中的最佳实现原则：[br]
## 1. 继承选择：[br]
##    - 顶层场景全屏视图：继承 [BaseUIView]（自动处理屏幕安全区）；[br]
##    - 模态弹窗/选卡升级/结算窗口：继承 [BaseDialog]（自动处理暗色遮罩与层级）；[br]
##    - 局部复用组件/单条列表卡片：直接继承 [Control] 或 [Node2D]；[br]
## 2. 职责边界：[br]
##    - 只做视觉表达：节点寻址、播放动画、声音触发、排版布局；[br]
##    - 纯输入感知：收集按钮点击、拖拽手势，并以自定义 signal 向上抛给 Presenter；[br]
##    - 严禁业务计算：严禁在 View 中计算伤害、加减金币或调用服务端接口。
