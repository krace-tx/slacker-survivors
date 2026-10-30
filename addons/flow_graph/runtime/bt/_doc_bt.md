# FlowGraph Runtime · BT (享元行为树 + 16 类标准节点与效用子树编译内核)

## 一、 核心定位与目录结构

`addons/flow_graph/runtime/bt/` 是 `FlowGraph` 插件内置的**零外部依赖、纯内存（`RefCounted`）享元行为树（Flyweight Behavior Tree）与 AST 编译内核**。

```text
addons/flow_graph/runtime/bt/
├── _doc_bt.md                        # 本文档
├── bt_builder.gd                     # [核心入口 1] 链式代码造树工具 (支持全部 16 种节点、效用绑定与 Schema 声明)
├── bt_tree.gd                        # [核心入口 2] 无状态享元行为树本体 (单树驱动百怪 + 热重载)
├── bt_context.gd                     # [核心入口 3] 单实体运行上下文 (每只怪独立持有一份)
├── bt_blackboard.gd                  # [核心入口 4] 单实体黑板键值表与按 node_id 隔离的节点记忆槽
├── bt_status.gd                      # 三态结果枚举 (SUCCESS / FAILURE / RUNNING)
├── ast/                              # [蓝图定义与编译层]
│   ├── bt_graph_def.gd               # 整棵树 AST 资源 (含 blackboard_schema 与子边权重/效用配置无损互转)
│   ├── bt_node_def.gd                # 单个节点 AST 资源
│   └── bt_compiler.gd                # 蓝图编译器 (支持动作/条件/效用算子注册与 SubTree nid*10000 隔离)
└── nodes/                            # [入口与三大无状态积木家族]
	├── bt_node.gd
	├── bt_root.gd                    # Root 显式单出口树根入口节点
	├── composites/                   # Selector / UtilitySelector(效用评分+惯性滞回) / WeightedSelector / Sequence / Parallel
	├── decorators/                   # Cooldown(含 jitter) / Repeater / TimeLimit / Inverter / ForceStatus / Service
	└── leaves/                       # Action / Condition(含 !cond 与表达式) / Wait(含 jitter) / SubTree
```

---

## 二、 核心实战机制

1. **100% 享元无状态隔离**：所有 `BTNode` 子类零实例可变状态；冷却解锁时间、随机采样等待时长、`Repeater` 计次、`TimeLimit` 计时、`WeightedSelector` / `UtilitySelector` 活跃子索引与实时各分支效用得分（`last_scores`）及 `BTSubTree` 偏移记忆槽全部存储在单怪独享的 `BTContext.blackboard` 中，500 个同屏 AI 安全共享同一棵 `BTTree`。
2. **效用评分混合决策（`BTUtilitySelector`）**：
   - 每个子分支通过 `FlowUtilityScorer` 支持声明式黑板区间曲线映射（`bb_key` + `min_val..max_val` + `invert` + `linear / quad / cubic / sqrt / smoothstep / logistic` + `weight`）、宿主效用算子（`register_utility` / `with_utility_fn`）以及多考量因子乘积补偿；
   - **防抽搐惯性滞回（`momentum`）**：上一帧处于 `RUNNING` 且基础分 `> 0.0` 的子分支自动获得 `+ momentum` 加分，只有新分支显著高出惯性阈值时才触发抢占并自动对旧分支调用 `abort(ctx)`；基础分归零（`= 0.0`）时立即硬性否决不加惯性分；
   - **阈值过滤与前 K 抽样（`min_score` + `top_k`）**：过滤低于 `min_score` 的无效分支；`top_k == 1` 执行确定性最高分抢占（首优分支返回 `FAILURE` 时自动顺延次高分支），`top_k > 1` 在前 K 候选池内按效用分加权抽样且保持运行中分支稳定。
3. **防齐射随机抖动（`jitter_sec`）与加权随机选招（`BTWeightedSelector`）**：
   - `BTCooldown` 与 `BTWait` 支持 `jitter_sec` 随机浮动区间，避免群怪同帧齐射；
   - `BTWeightedSelector` 按子分支 `weight` 权重随机抽招，且在动作 `RUNNING` 期间自动锁定当前分支直至收招完成。
4. **不可打断锁（`memory`）、并行短路清理（`BTParallel`）与超时防卡死（`BTTimeLimit`）**：
   - `BTSelector(memory=true)` 与 `BTUtilitySelector(memory=true)` 在子动作蓄力/施法返回 `RUNNING` 期间阻止其它分支中途抢占；
   - `BTParallel` 在完成或短路退出时自动对所有仍处于运行态的兄弟子分支调用 `abort(ctx)` 清理记忆槽；
   - `BTTimeLimit(timeout_sec)` 在追击/寻路超时后自动调用 `child.abort(ctx)` 清理状态并返回 `FAILURE`。
5. **低频感知服务（`BTService`）与多层公共子树复用（`BTSubTree`）**：
   - `BTService` 按 `interval_sec ± jitter_sec` 周期刷新黑板索敌数据，避免每帧重复高开销计算；
   - `BTSubTree` 直接引用外部公共 `.tres` 蓝图，首层按 `nid * 10000` 施加记忆槽偏移、深层嵌套分配独立高段槽位防 `int64` 溢出，且主/子图 `blackboard_schema` 均通过 `BTContext` 整型纪元号 $O(1)$ 自动同步。
