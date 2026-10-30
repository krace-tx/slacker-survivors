# FlowGraph Runtime · FSM (有限与层次状态机 + AST 蓝图同构内核)

## 一、 核心定位与目录结构

`addons/flow_graph/runtime/fsm/` 是 `FlowGraph` 插件内置的**零外部依赖、纯内存（`RefCounted`）有限/层次状态机（FSM / HFSM）与抽象状态图（AST）蓝图内核**。

```text
addons/flow_graph/runtime/fsm/
├── _doc_fsm.md                       # 本文档
├── state_machine.gd                  # [核心入口 ①] 状态机主控制器 (含内置黑板、fire_event、!cond 表达式与热重载)
├── base_fsm_state.gd                 # [核心入口 ②] 强类型状态基类 (支持嵌套 sub_machine)
├── fsm_lambda_state.gd               # [核心入口 ③] 轻量闭包状态 (由 add_callable 自动创建)
└── ast/                              # [蓝图定义与编译层]
    ├── fsm_graph_def.gd              # 整张状态图 AST 资源 (含 blackboard_schema 与双向 IR 协议)
    ├── fsm_state_def.gd              # 单个状态节点描述子 (含 sub_graph_path 子状态图路径)
    ├── fsm_transition_def.gd         # 转换有向边描述子 (condition_key / trigger_event / bb_expr / min_state_time / priority)
    └── fsm_compiler.gd               # HFSM 递归子图挂载编译器 (最大深度 8 + 环路保护)与热重载协调器
```

---

## 二、 核心架构特性

1. **脉冲事件触发器（`fire_event`）与单帧自洁**：
   - 调用 `fsm.fire_event(&"hit_stun", {"damage": 30})` 可立即触发当前状态（或 `*` 全局打断边）上配置了 `trigger_event = &"hit_stun"` 的转换边，并将 `payload` 透传给目标状态的 `_on_enter(prev, msg)`；若未消费则在当帧 `update()` 结束时自动清空，彻底告别手写布尔标志位。
2. **条件取反、复合表达式与内置黑板（`FlowBlackboardExpr`）**：
   - `StateMachine` 自带 `blackboard: BTBlackboard`（编译时自动按 `FsmGraphDef.blackboard_schema` 注入默认值）；
   - 转换边的 `condition_key` 原生支持 `!enemy_in_sight`、`enemy_in_sight && !is_reloading` 等组合语法，同时可通过 `bb_expr` 直接编写 `stamina >= 25 && hp_ratio < 0.5` 黑板表达式。
3. **层次状态机 `.tres` 子图嵌套（HFSM Sub-Graph）与级联启停**：
   - 为任意 `FsmStateDef` 设置 `sub_graph_path = "res://.../def_fsm_combat_combo.tres"`，编译时 `FsmCompiler` 自动递归加载并挂载为该状态的 `sub_machine`，共享宿主 `actor`、条件注册表与 `blackboard`；事件消费遵循「子状态机优先、父状态机兜底」，父状态退出或调用 `stop()` 时自底向上自动级联退出激活子状态机。
4. **$O(E_{\text{state}})$ 预索引转换表、重入保护与无损热重载（`hot_reload_from_ir`）**：
   - 转换边按源状态预归并全局 `*` 转换边与优先级排序，每帧仅评估当前驻留状态的出边，并内置迭代式 `_on_enter` 重入上限保护（防止乒乓状态切换栈溢出）；
   - 游戏运行中修改转换条件、`min_state_time` 或增删状态并保存 `.tres` 后，自动原位热更新转换表，保留当前激活状态 `_current_id`、驻留时长 `_state_time` 与黑板数据不断流。
