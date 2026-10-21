# Scene (场景流转)

## 核心

统一管理顶层页面的路由、压栈（Push）与替换（Replace）生命周期。
遵循 **Apple / 字节跳动** 产品级交互设计哲学，摒弃任何形式的黑屏/遮罩掩耳盗铃，实现新旧场景在同一个连续物理空间内的纯净淡变与景深弹性交融。

---

## 细节

- **栈机制与快照隔离**：内部维护 `_stack`。同路径场景防重入，切入已在底部的场景时会自动“收环”（`pop_to`）弹出中间层并执行平滑转场，防止无限压栈。场景休眠（`_sleep_entry`）时仅快照记录当前处于 `visible == true` 的顶层可视节点并将其隐藏；唤醒（`_wake_entry`）时严格按快照还原，绝不粗暴覆盖业务默认隐藏的子节点。
- **基类约束与任务作用域**：所有的场景根节点必须继承 `BaseScene`（继承自 `Node`），分离了门面控制与具体的可视子树（`CanvasItem` / `CanvasLayer` / `Node3D`）。内置 `task_scope: TaskScope`，在场景被替换、出栈或销毁时自动取消所有未完成的悬挂异步任务。
- **强类型参数契约 (`BaseParams`)**：凡调用 `replace` / `push` / `pop` / `bind` 跨场景传递参数时，统一使用继承自 `BaseParams` 的强类型数据契约实例（无参时默认为 `null`），彻底杜绝松散易错的裸 `Dictionary` 魔法字符串传参。
- **生命周期挂钩与焦点隔离**：
  - `_on_enter(params: BaseParams = null)`：新场景进场时触发（支持 `await` 异步拉取数据，且支持在钩子内部安全重入调用 `await App.scene.replace(...)` 进行路由守卫重定向，零死锁）。
  - `_on_exit()`：场景先冻结帧逻辑（`PROCESS_MODE_DISABLED`）并完成转场退场动画后、即将从场景树销毁前触发。
  - `_on_pause()`：被新场景 Push 压入栈底，或**处于栈顶激活态时**应用切后台（`Bus.app_paused`）时触发。栈底已休眠场景绝不会被后台事件重复打扰。
  - `_on_resume(params: BaseParams = null)`：上方场景 Pop 离开重回栈顶，或**处于栈顶激活态时**应用切回前台（`Bus.app_resumed`）时触发。
- **成对流式动效体系 (SceneTransition)**：
  - **可视根节点自动采集（Visual Root Harvesting）**：由于 `BaseScene` 继承自 `Node`，`SceneTransition` 会自动递归穿透 `Node` / `CanvasLayer` 容器，收集场景下所有顶层可见的 `CanvasItem` 进行并行属性快照、Tween 插值与结束后无损还原（Modulate / Scale / Pivot）。
  - **成对转场动效**：
    - `CROSS_PUSH`（Push 默认）：新场景在顶层优雅淡入覆盖（`0.0 -> 1.0`），底层场景平滑淡化（`1.0 -> 0.92`），实现纯净进场。
    - `CROSS_POP`（Pop 默认）：底层场景保持 100% 纯实体静止，顶层场景溶解淡出（`1.0 -> 0.0`），彻底杜绝双重曝光重叠感。
    - `DEPTH_ZOOM`（Replace 默认）：Apple 景深微缩放，新场景 `0.96x -> 1.0x` 弹性聚焦推近，旧场景 `1.0x -> 1.03x` 柔和散出。
    - `AUTO`（默认智能推导：Push 走淡入进场，Pop 走溶解揭开，Replace 走景深缩放）。
  - **无形触控防护（Invisible Shield）**：动画期间在 Layer=100 挂载全透明控件拦截点击，动画完成毫秒级撤去，彻底杜绝快速连点导致状态撕裂。
- **信号驱动串行队列与可重入安全**：内建信号驱动请求票据队列（`_NavTicket` + `_enqueue`），零轮询开销。涵盖 `bind` / `replace` / `push` / `pop` 全操作并统一广播 `Bus.scene_changed`；当在生命周期钩子（如 `_on_enter`）内发起嵌套路由跳转时，自动识别重入深度并派生消费协程，彻底消除自等待死锁与重复事件广播。

```text
src/framework/modules/scene/
├── _doc_scene.md              # 本文档
├── base_scene_router.gd       # 公开路由门面契约 BaseSceneRouter (App.scene，详尽注释)
├── base_scene.gd              # [业务基类] 场景扩展基类，暴露 enter/exit/pause/resume 生命周期
│
├── types/                     # [公开契约]
│   └── scene_transition_type.gd # 转场动效类型定义 (SceneTransitionType)
│
└── impl/                      # [私有收敛]
    ├── scene_router.gd        # 顶层场景路由门面实现，对外暴露极简 API 与请求队列调度
    ├── scene_stack.gd         # 场景栈状态机与生命周期驱动内核 (入栈/出栈/收环/休眠/唤醒)
    └── scene_transition.gd    # 极简流式视觉转场内核 (成对淡入进场/溶解退场/景深缩放)
```

---

## 样例

```gdscript
# 1. 在目标场景内声明强类型入参与出参契约
class LevelEnterParams extends BaseParams:
	var level_id: int = 1

class LevelResultParams extends BaseParams:
	var is_level_solved: bool = false
	var solved_level_id: int = 0

# 2. 默认智能流式切场（无参时 params 默认为 null）
var replace_res := await App.scene.replace(GameScenes.Scene.SPLASH)
if replace_res.is_err():
	App.logger.error("Scene", replace_res.error_message())

# 3. 压入新场景并传递强类型 BaseParams 实例
var enter_params := LevelEnterParams.new()
enter_params.level_id = 2
var push_res := await App.scene.push(SceneCatalog.LEVEL, enter_params)

# 4. 弹出场景并回传强类型结果
var result_params := LevelResultParams.new()
result_params.is_level_solved = true
result_params.solved_level_id = 2
var pop_res := await App.scene.pop(result_params)

# 5. 无参出栈
var pop_empty_res := await App.scene.pop()
```
