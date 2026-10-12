# Scene (场景流转)

## 核心

统一管理顶层页面的路由、压栈（Push）与替换（Replace）生命周期。
遵循 **Apple / 字节跳动** 产品级交互设计哲学，摒弃任何形式的黑屏/遮罩掩耳盗铃，实现新旧场景在同一个连续物理空间内的纯净淡变与景深弹性交融。

---

## 细节

- **栈机制**：内部维护 `_stack`。同路径场景防重入，切入已在底部的场景时会自动“收环”弹出中间层，防止无限压栈。
- **基类约束**：所有的场景根节点必须继承 `BaseScene`，分离了门面控制与具体的 UI 逻辑树（在 `$UI` 下）。
- **参数书写约束**：凡调用 `replace` / `push` / `pop` 传递带有非空参数的 Dictionary 时，**必须采用多行展开风格（Multiline Expanded Format）**，严禁将键值对挤在单行内，以保证代码的高可读性与精准的 git diff 追踪。
- **生命周期挂钩**：
  - `_on_enter`：新场景进场时触发（可 await 异步拉取数据）。
  - `_on_exit`：场景离开前台且将要被销毁时触发。
  - `_on_pause`：被新场景 Push 压住时触发。逻辑与画面暂停，但节点依然存活不销毁。
  - `_on_resume`：上方场景 Pop 走后，本场景重回前台时触发。
- **成对流式动效体系 (SceneTransition)**：
  - **连续视觉流（Visual Continuity）**：新旧场景在树上并行共存，由 Tween 驱动自然平滑的物理曲线变换。
  - **成对转场动效**：
    - `CROSS_PUSH`（Push 默认）：新场景在顶层优雅淡入覆盖（`0.0 -> 1.0`），底层场景平滑淡化，实现纯净进场。
    - `CROSS_POP`（Pop 默认）：底层场景保持 100% 纯实体静止，顶层场景溶解淡出（`1.0 -> 0.0`），如薄雾散去般优雅揭开下层，彻底杜绝双重曝光重叠感。
    - `DEPTH_ZOOM`（Replace 默认）：Apple 景深微缩放，新场景 `0.96x -> 1.0x` 弹性聚焦推近，旧场景 `1.0x -> 1.03x` 柔和散出。
    - `AUTO`（默认智能推导：Push 走淡入进场，Pop 走溶解揭开，Replace 走景深缩放）。
  - **无形触控防护（Invisible Shield）**：动画期间在 Layer=100 挂载全透明控件拦截点击，动画完成毫秒级撤去，彻底杜绝快速连点导致状态撕裂。
- **安全并发**：内建串行请求队列（`_enqueue`）。切换中传入的路由命令按提交顺序执行，每个调用都等待并收到自己的 `Result`，不会把栈打乱。

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
# 1. 默认智能流式切场（Replace 自动触发 Apple 景深弹性缩放）
var replace_res := await App.scene.replace("res://src/game/scenes/gallery/gallery.tscn")
if replace_res.is_err():
    App.log.error("Scene", replace_res.error_message())

# 2. 压入新场景并带参（必须采用多行展开字典书写风格）
var push_res := await App.scene.push(SceneCatalog.LEVEL, {
    "level_id": 2,
})

# 3. 弹出场景并回传结果（必须采用多行展开字典书写风格）
var pop_res := await App.scene.pop({
    "is_level_solved": true,
    "solved_level_id": 2,
})

# 4. 无参出栈
var pop_res := await App.scene.pop()
```
