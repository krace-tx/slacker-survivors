# Infra · BT (享元行为树 + AST 蓝图同构基建)

## 一、 核心定位与目录结构

`src/framework/infra/bt/` 是全工程通用的**纯内存（`RefCounted`）享元行为树（Flyweight Behavior Tree）与抽象语法树（AST）解析编译基建**。

目录按**「外层高频业务入口 + `ast/` 蓝图编译层 + `nodes/` 三大积木家族」**分层组织，一眼即可分辨哪些是日常写业务调用的入口，哪些是底层积木与序列化结构：

```text
src/framework/infra/bt/
├── _doc_bt.md                        # 本文档
├── bt_builder.gd                     # [核心入口 ①] 链式造树工具 (BTBuilder：平时写 AI 最常用)
├── bt_tree.gd                        # [核心入口 ②] 行为树本体 (BTTree：全图百怪共享 1 份，每帧调 tick)
├── bt_context.gd                     # [核心入口 ③] 单怪运行档案 (BTContext：每只怪 new 1 个)
├── bt_blackboard.gd                  # [核心入口 ④] 黑板记忆本 (BTBlackboard：存血量、距离等变量)
├── bt_status.gd                      # [核心契约] 三态结果枚举 (BTStatus: SUCCESS / FAILURE / RUNNING)
│
├── ast/                              # [蓝图定义与编译层] (做可视化画图、存 .tres 或 JSON 配表时才用)
│   ├── bt_graph_def.gd               # 整棵树的蓝图存档数据 (BTGraphDef, extends Resource)
│   ├── bt_node_def.gd                # 单个节点的蓝图存档数据 (BTNodeDef, extends Resource)
│   └── bt_compiler.gd                # 蓝图翻译编译器 (BTCompiler: 把 BTGraphDef 编译成 BTTree)
│
└── nodes/                            # [行为树积木库] (由 BTBuilder 自动组装，按 3 大标准家族分类)
    ├── bt_node.gd                    # 所有积木的抽象基类 (BTNode)
    ├── composites/                   # 1. 分支控制组合节点 (决定怎么走分支)
    │   ├── bt_selector.gd            #    选择节点 (OR：从左到右挑一个能行的分支走，支持高优抢占)
    │   ├── bt_sequence.gd            #    顺序节点 (AND：按顺序一步步走，有一环失败即中断)
    │   └── bt_parallel.gd            #    并行节点 (同一帧让底下多个子节点同时干活)
    ├── decorators/                   # 2. 条件修饰装饰节点 (套在某个节点外面的壳)
    │   ├── bt_cooldown.gd            #    冷却锁节点 (技能放完后锁 N 秒 CD)
    │   └── bt_inverter.gd            #    结果取反节点 (NOT：成功变失败，失败变成功)
    └── leaves/                       # 3. 末端具体执行叶节点 (怪物的眼睛和手脚)
        ├── bt_condition.gd           #    条件判断节点 (眼睛：如判断 血量<=50%?)
        ├── bt_action.gd              #    动作执行节点 (手脚：如 挥刀斩击 / 翻滚!)
        └── bt_wait.gd                #    定时等待节点 (读秒：如 攻击后摇休息 0.5 秒)
```

---

## 二、 核心架构特性

1. **拓扑与状态彻底分离（Flyweight 享元模式）**：
   - `BTNode` 及其子类**完全无状态（Stateless）**，仅保存拓扑结构与只读参数；
   - 运行时状态（如 `BTWait` 剩余秒数、`BTCooldown` 冷却解锁时间、`BTSequence` 当前运行子索引）全部按 `node_id` 存储在单实体独享的 `BTBlackboard` 节点记忆槽中；
   - **同屏 500 个 AI 实体可安全共享内存中唯一的一棵 `BTTree` 实例**，零节点克隆开销。
2. **代码 DSL 与 AST 蓝图双向同构**：
   - 使用 `BTBuilder` 链式代码构建行为树时，底层自动生成完整的 `BTGraphDef` AST（含自动树状排版坐标）；
   - 使用 JSON / `.tres` 保存的 `BTGraphDef` AST 可通过 `BTCompiler.compile()` 编译为运行时 `BTTree`。
3. **高优抢占与自动打断自洁 (`abort`)**：
   - `BTSelector` 每帧从高优先级分支向低优先级评估；当高优先级分支抢占成功时，自动对先前处于 `RUNNING` 的低优分支调用 `abort(ctx)` 清理残留计时与状态。
4. **实时可视化遥测 (`BTContext.get_telemetry_snapshot`)**：
   - 实时记录每个 `node_id` 在当前 Tick 的执行结果（`SUCCESS` / `FAILURE` / `RUNNING`），任何 UI 调试器只需遍历 `BTTree.get_ast()` 并查询 `ctx.get_live_node_status(node_id)` 即可实时绘制动态高亮的蓝图树。
