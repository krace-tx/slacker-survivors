# FlowGraph Runtime · BT (享元行为树 + 15 类标准节点与子树编译内核)

## 一、 核心定位与目录结构

`addons/flow_graph/runtime/bt/` 是 `FlowGraph` 插件内置的**零外部依赖、纯内存（`RefCounted`）享元行为树（Flyweight Behavior Tree）与 AST 编译内核**。

```text
addons/flow_graph/runtime/bt/
├── _doc_bt.md                        # 本文档
├── bt_builder.gd                     # [核心入口 ①] 链式代码造树工具 (支持全部 15 种节点与 Schema 声明)
├── bt_tree.gd                        # [核心入口 ②] 无状态享元行为树本体 (单树驱动百怪 + 热重载)
├── bt_context.gd                     # [核心入口 ③] 单实体运行上下文 (每只怪独立持有一份)
├── bt_blackboard.gd                  # [核心入口 ④] 单实体黑板键值表与按 node_id 隔离的节点记忆槽
├── bt_status.gd                      # 三态结果枚举 (SUCCESS / FAILURE / RUNNING)
├── ast/                              # [蓝图定义与编译层]
│   ├── bt_graph_def.gd               # 整棵树 AST 资源 (含 blackboard_schema 与子边权重互转)
│   ├── bt_node_def.gd                # 单个节点 AST 资源
│   └── bt_compiler.gd                # 蓝图编译器 (支持 SubTree 命名空间偏移 nid*10000 零冲突隔离)
└── nodes/                            # [三大无状态积木家族]
	├── bt_node.gd
	├── composites/                   # Selector(含 memory 防打断) / WeightedSelector / Sequence(含 reactive) / Parallel
	├── decorators/                   # Cooldown(含 jitter) / Repeater / TimeLimit / Inverter / ForceStatus / Service
	└── leaves/                       # Action / Condition(含 !cond 与表达式) / Wait(含 jitter) / SubTree
```

---

## 二、 核心实战机制

1. **100% 享元无状态隔离**：所有 `BTNode` 子类零实例可变状态；冷却解锁时间、随机采样等待时长、`Repeater` 计次、`TimeLimit` 计时、`WeightedSelector` 锁定分支及 `BTSubTree` 偏移记忆槽全部存储在单怪独享的 `BTContext.blackboard` 中，500 个同屏 AI 安全共享同一棵 `BTTree`。
2. **防齐射随机抖动（`jitter_sec`）与加权随机选招（`BTWeightedSelector`）**：
   - `BTCooldown` 与 `BTWait` 支持 `jitter_sec` 随机浮动区间，避免群怪同帧齐射；
   - `BTWeightedSelector` 按子分支 `weight` 权重随机抽招，且在动作 `RUNNING` 期间自动锁定当前分支直至收招完成。
3. **不可打断锁（`memory`）与超时防卡死（`BTTimeLimit`）**：
   - `BTSelector(memory=true)` 在子动作蓄力/施法返回 `RUNNING` 期间阻止左侧普通分支中途抢占；
   - `BTTimeLimit(timeout_sec)` 在追击/寻路超时后自动调用 `child.abort(ctx)` 清理状态并返回 `FAILURE`。
4. **低频感知服务（`BTService`）与公共子树复用（`BTSubTree`）**：
   - `BTService` 按 `interval_sec ± jitter_sec` 周期刷新黑板索敌数据，避免每帧重复高开销计算；
   - `BTSubTree` 直接引用外部公共 `.tres` 蓝图，编译期自动施加 `nid * 10000` 记忆槽命名空间偏移，同一棵树内多次挂载同一公共子树亦零串扰。
