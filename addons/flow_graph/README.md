# FlowGraph (`addons/flow_graph`)

Godot 4 **零外部依赖、开箱即用**的算法图运行时与可视化工作台插件：**内置纯内存有限/层次状态机（FSM / HFSM）+ 15 种节点的享元行为树（Flyweight BT）+ 轻量黑板布尔表达式引擎 + 通用算法图运行期调试桥接器（`runtime/`）**，搭配顶部主视口（Main Screen）**`FlowGraph`** 零语法可视化直编画布、五卡片原位检视器、64 步 Undo/Redo、静态拓扑 Linter、60 帧时间轴倒带回放、实时黑板热改、保存热重载与子图面包屑下钻工作台（`editor/`）。

> **零外部依赖与低认知负担契约**：
> 1. 整个 `addons/flow_graph/` 不引用任何宿主项目业务或框架脚本（统一使用自包含 `FlowGraphResult`），整包拷贝至任何空白 Godot 4 工程即可直接运行；
> 2. 全量 83 个 `.gd` 脚本严格按正交职责拆解（中位文件规模 ~115 行），零裸字符串 `preload("...")`（全部收敛至 `FlowGraphContracts` / `FlowGraphIcons`），并内置单语纯净的 `ZH / EN` 实时热切换与中性占位词体系。

---

## 一、 模块化目录拓扑（`runtime/` × `editor/` 双核物理隔离）

```text
addons/flow_graph/
├── plugin.cfg                                       # 插件元数据 (name="FlowGraph")
├── plugin.gd                                        # [主视口门面] 挂载顶部 FlowGraph 标签、_handles/_edit 蓝图接管与 Debugger 装配
├── README.md                                        # 本文档
│
├── runtime/                                         # [运行期内核层] 零编辑器依赖、零外部框架依赖，随正式包导出
│   ├── flow_graph_result.gd                         # 自包含强类型结果契约 (FlowGraphResult)
│   ├── shared/
│   │   ├── _doc_shared.md
│   │   └── flow_blackboard_expr.gd                  # 零分配黑板表达式与 !cond / && / || 求值器 (FlowBlackboardExpr)
│   ├── fsm/                                         # 有限/层次状态机内核 + AST 资源 (_doc_fsm.md)
│   │   ├── state_machine.gd                         # 状态机主控制器 (fire_event 脉冲事件 / 条件取反 / 内置黑板 / 热重载)
│   │   ├── base_fsm_state.gd                        # 强类型状态基类 (支持嵌套 sub_machine)
│   │   ├── fsm_lambda_state.gd                      # 轻量闭包状态
│   │   └── ast/                                     # FsmGraphDef / FsmStateDef / FsmTransitionDef / FsmCompiler (HFSM 子图编译)
│   ├── bt/                                          # 享元行为树内核 + 15 种标准节点 (_doc_bt.md)
│   │   ├── bt_builder.gd                            # 链式代码造树器 (BTBuilder)
│   │   ├── bt_tree.gd                               # 无状态享元行为树本体 (单树驱动百怪 + Schema 注入 + 热重载)
│   │   ├── bt_context.gd                            # 单实体运行上下文 (BTContext)
│   │   ├── bt_blackboard.gd                         # 单实体黑板与节点记忆槽 (BTBlackboard)
│   │   ├── bt_status.gd                             # 三态枚举 (SUCCESS / FAILURE / RUNNING)
│   │   ├── ast/                                     # BTGraphDef / BTNodeDef / BTCompiler (含 SubTree 命名空间偏移隔离)
│   │   └── nodes/                                   # 三大标准积木家族：
│   │       ├── composites/                          #   Selector(含 memory 防打断) / WeightedSelector / Sequence / Parallel
│   │       ├── decorators/                          #   Cooldown(含 jitter) / Repeater / TimeLimit / Inverter / ForceStatus / Service
│   │       └── leaves/                              #   Action / Condition(含表达式) / Wait(含 jitter) / SubTree
│   └── debug/                                       # 通用算法图 IPC 调试桥接基建 (_doc_debug.md)
│       ├── base_debuggable_graph.gd                 # 可选抽象基类：供任意自定义管线/DAG 算法继承接入
│       ├── graph_debug_serializer.gd                # FSM / BT 拓扑与帧遥测字典无状态归一化器
│       ├── graph_debug_command_executor.gd          # 下行命令执行器 (set_var 热改黑板 / 节点断点 / fire_event / 热重载)
│       ├── graph_debug_binding.gd                   # 弱引用 instance_id 绑定描述子与断点自动挂起拦截
│       └── graph_debug_bridge.gd                    # EngineDebugger ("flow_graph:*") 遥测推送、行号捕获与资源热重载广播
│
└── editor/                                          # [编辑器可视化工作台层] 全量 @tool 单向依赖
    ├── assets/                                      # Godot 4 编辑器规范矢量图标集 (plugin / status / toolbar / node)
    ├── contracts/                                   # 零裸字符串路径与预加载契约层：
    │   ├── flow_graph_contracts.gd                  #   FlowGraphContracts：全插件脚本、场景、SVG 与 EditorSettings 路径常量表
    │   └── flow_graph_icons.gd                      #   FlowGraphIcons：30 个矢量 SVG 单实例 Texture2D 预加载注册表
    ├── i18n/                                        # 编辑器单语本地化与实时切换服务层：
    │   ├── flow_editor_i18n.gd                      #   FlowEditorI18n：ZH/EN 热切换、EditorSettings 持久化与弱引用订阅总线
    │   ├── flow_i18n_zh.gd                          #   简体中文单语词典（零括号双语混排、中性输入占位词）
    │   └── flow_i18n_en.gd                          #   English 单语词典（100% 键位对齐、中性输入占位词）
    ├── model/
    │   └── mermaid_graph_model.gd                   # Canonical Graph IR、完备节点/边 CRUD、BT 坐标重排与快照克隆
    ├── codec/
    │   └── mermaid_codec.gd                         # Mermaid (stateDiagram-v2 / flowchart) + @mg_bb/@mg/@mg_edge 无损互转
    ├── command/
    │   └── flow_undo_stack.gd                       # 按会话物理隔离的 64 步签名去重 Undo / Redo 历史栈
    ├── lint/
    │   └── flow_graph_linter.gd                     # 静态拓扑校验器 (孤岛节点 / 缺失入口 / 装饰器元数 / 子图环路诊断)
    ├── bridge/
    │   ├── mermaid_resource_bridge.gd               # 鸭子类型蓝图读写桥接 (to_flow_graph_ir / to_mermaid_ir)
    │   ├── mermaid_resource_catalog.gd              # 基于 EditorFileSystem 缓存的零加载全项目图资源自动扫描器
    │   └── flow_operator_scanner.gd                 # 零实例化扫描工程 .gd 注册算子/条件/事件候选表
    ├── layout/                                      # 多态自动布局引擎 (FSM 四象限星型 / BT 轮廓紧缩树 / Sugiyama DAG)
    ├── debugger/                                    # 跨进程调试接收与四态会话仓库包：
    │   ├── mermaid_editor_debugger.gd               # EditorDebuggerPlugin IPC 收发与 hot_reload_resource 下发
    │   ├── session_disk_watcher.gd                  # mtime + MD5 外部文件修改热重载与脏会话冲突保护
    │   ├── session_frame_ring_buffer.gd             # 60 帧签名去重环形遥测历史缓冲 (支持停止后离线回放)
    │   ├── session_source_applier.gd                # 源码编辑与节点元数据无损合并器
    │   ├── session_live_tracker.gd                  # 多实例实时追踪与快照归档器
    │   └── mermaid_session_store.gd                 # 四态统一会话仓库门面
    └── ui/
        ├── theme/                                   # Godot 4 实时主题令牌采样与控件样式注入
        ├── canvas/                                  # 模块化矢量画布与四分包边路由引擎：
        │   ├── routing/                             # edge_obstacle_avoidance / fsm_hub / bt_bus(#1,#2) / dag_channel
        │   ├── canvas_context_menu.gd               # 画布空白与节点右键 CRUD / 断点 / 子图菜单
        │   ├── canvas_input_controller.gd           # 缩放平移、节点拖拽、拉线、双击下钻与 Ctrl+Z/Y/D/Del 快捷键
        │   ├── canvas_telemetry_state.gd            # 呼吸高亮与流光脉冲动画状态机
        │   ├── canvas_painter.gd                    # 世界空间几何绘制 (含 ● 断点徽章与 ⧉ 子图角标)
        │   ├── canvas_overlay_painter.gd            # 1:1 屏幕抗碰撞标签、BT #1/#2 顺序胶囊与鹰眼小地图
        │   └── mermaid_graph_canvas.gd              # 画布门面
        ├── inspector/                               # 五卡片模块化原位检视器包：
        │   ├── inspector_style_kit.gd               # 样式盒与带 ▾ 算子嗅探补全输入框工厂
        │   ├── inspector_kpi_card.gd                # 会话 KPI、冲突处理、源蓝图互切与 Linter 诊断列表
        │   ├── inspector_node_editor_card.gd        # 节点 ID/类型/子图/专属参数原位直编 + 断点与强制触发
        │   ├── inspector_edge_editor_subcard.gd     # 出边条件/脉冲事件/黑板表达式/权重原位编辑 + 实时 fire_event
        │   ├── inspector_outline_card.gd            # 拓扑节点大纲 + 黑板 Schema 契约表编辑器
        │   └── inspector_blackboard_card.gd         # 运行期可原位勾选/热改的黑板监视表 + 历史帧回放快照态
        └── workbench/                               # 工作台薄协调器与子控制器包：
            ├── workbench_nav_scrubber_bar.gd        # 按需显隐：左侧子图面包屑栈 + 右侧 60 帧时间轴回放滑块
            ├── workbench_mutation_controller.gd     # 图编辑动作、Undo 快照记录与路由重算协调器
            ├── workbench_debug_session_controller.gd# 调试命令、回放自动暂停、断点与保存热重载协调器
            ├── workbench_dpi_scaler.gd              # 编辑器主题与 HiDPI 自适应缩放器
            ├── workbench_chrome_controller.gd       # 浮动窗口菜单、文件对话框与脚本行号跳转控制器
            ├── mermaid_floating_host.gd             # 独立系统浮动窗口无损提取宿主
            ├── mermaid_resource_browser.gd          # 右侧「资源」全项目图目录页
            ├── mermaid_inspector_panel.gd           # 检视面板兼容门面
            └── mermaid_workbench.{tscn,gd}          # 顶层工作台协调器
```

---

## 二、 核心能力矩阵（P0 ~ P3 全闭环）

- **P0 零语法可视化直编**：画布右键直接新建 FSM 状态与 15 种 BT 节点、拖拽子节点自动按坐标重排 `#1 / #2` 执行优先级、检视面板原位修改全部节点与转换边参数、`Ctrl+Z / Ctrl+Y` 64 步撤销重做、静态拓扑 Linter 实时报错定位。
- **P1 实战级 FSM & BT 内核**：FSM 原生支持 `fire_event(&"hit", payload)` 脉冲事件、`!cond` 与 `&& / ||` 复合条件表达式；BT 原生内置随机抖动 `Cooldown / Wait`（防百怪齐射）、防打断 `Selector(memory=true)`、`WeightedSelector` 权重抽招、`Repeater`、`TimeLimit` 超时中断、`ForceSuccess / ForceFailure` 与低频感知 `BTService`。
- **P2 杀手级运行期联调**：运行中直接在右侧黑板表勾选/改数实时注入游戏内存（`set_var`）；在任意节点右键打 `●` 断点，命中瞬间自动冻结该 AI 实例；底部滑块随时倒带回看最近 **60 帧**状态跃迁与当时黑板快照（`F8` 停止后依然可回放）；修改 `.tres` 按 `Ctrl+S` 保存即刻热更新运行中实例，无需重启游戏。
- **P3 规模化子图嵌套与算子补全**：FSM 状态与 BT `SubTree` 支持挂载外部公共 `.tres` 子图，双击节点直接钻入子图并通过顶部面包屑一键返回；自动扫描工程 `.gd` 脚本中的算子与事件名，在检视面板提供 `▾` 一键下拉补全与黑板 Schema 强类型契约声明。
- **契约化路径治理与单语双语种实时切换**：所有 `preload(...)` 与配置键统一收敛至 `FlowGraphContracts` / `FlowGraphIcons`（零裸字符串预加载）；顶栏右侧内置 `中文 / EN` 一键实时切换按钮，全界面严格单语呈现（杜绝 `中文 (English)` 混排），所有输入框统一采用克制中性的名词占位符。
