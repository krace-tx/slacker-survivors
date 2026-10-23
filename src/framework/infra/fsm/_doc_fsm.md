# Infra · FSM (有限与层次状态机 + AST 蓝图同构基建)

## 一、 核心定位与目录结构

`src/framework/infra/fsm/` 是全工程通用的**纯内存（`RefCounted`）有限/层次状态机（FSM / HFSM）与抽象状态图（AST）解析基建**。

目录按**「外层高频运行入口 + `ast/` 状态图蓝图定义层」**组织：

```text
src/framework/infra/fsm/
├── _doc_fsm.md                       # 本文档
├── state_machine.gd                  # [核心入口 ①] 状态机主控制器 (StateMachine：平时写业务直接用它)
├── base_fsm_state.gd                 # [核心入口 ②] 强类型状态基类 (BaseFsmState：写复杂独立状态类时继承它)
├── fsm_lambda_state.gd               # [核心入口 ③] 轻量闭包状态 (FsmLambdaState：由 add_callable 自动创建)
└── ast/                              # [蓝图定义层] (状态图 AST 序列化与可视化画图用)
    ├── fsm_graph_def.gd              # 整张状态图 AST 资源 (FsmGraphDef, extends Resource)
    ├── fsm_state_def.gd              # 单个状态节点 AST 描述子 (FsmStateDef, extends Resource)
    └── fsm_transition_def.gd         # 状态转换有向边 AST 描述子 (FsmTransitionDef, extends Resource)
```

---

## 二、 核心架构特性

1. **零场景树开销（100% `RefCounted`）**：
   - 状态机与所有状态实例均继承自 `RefCounted`，通过弱引用（`instance_id`）绑定宿主 `actor`，不污染 `SceneTree`，离开作用域自动释放。
2. **代码与 AST 蓝图双向同构**：
   - 无论通过 `add_state` / `add_callable` 纯代码注册，还是从 `FsmGraphDef`（`.tres` 或 JSON 字典）通过 `compile_from_ast()` 编译，均可随时调用 `get_ast()` 获取完整的状态节点与转换边拓扑，直接驱动可视化状态图渲染。
3. **内置状态流逝时钟 (`state_time`) 与自动定时跳转**：
   - 自动累加当前状态停留时长 `get_state_time()`；转换边 `FsmTransitionDef` 支持配置 `min_state_time`（如翻滚动作持续 `0.38s` 后自动切回 `&"idle"`），彻底告别零碎 `Timer` 节点。
4. **重入保护、转换守卫 (`_can_transition_to`) 与前驱回退 (`revert_to_previous`)**：
   - 支持在状态内拦截非法打断（如霸体或死亡终态）；
   - 支持受击硬直结束后一键 `revert_to_previous()` 恢复受击前的状态；
   - 支持层次化子状态机（`BaseFsmState.sub_machine`）。
5. **实时遥测快照 (`get_telemetry_snapshot`)**：
   - 实时暴露当前状态、前驱状态、驻留时长与最近转换轨迹，供可视化调试面板高亮当前激活状态与刚刚触发的转换边。
