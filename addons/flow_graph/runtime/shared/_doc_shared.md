# FlowGraph Runtime · Shared (共享黑板表达式、效用响应曲线与 Schema 转型内核)

## 一、 核心定位与目录结构

`addons/flow_graph/runtime/shared/` 提供供 `FSM` 与 `BT` 两大运行内核共同复用的 **轻量布尔表达式求值器、效用 AI 响应曲线评分引擎与黑板 Schema 默认值转型引擎**，保持 100% 零外部依赖与 `@tool` 双态安全。

```text
addons/flow_graph/runtime/shared/
├── _doc_shared.md                    # 本文档
├── flow_blackboard_expr.gd           # FlowBlackboardExpr：Schema 默认值注入、安全类型转换与布尔表达式求值
└── flow_utility_scorer.gd            # FlowUtilityScorer：区间归一化、6 类响应曲线、单轴/多考量效用评分与无符号摘要
```

## 二、 核心契约

1. **`apply_schema_defaults(schema, bb)`**：遍历 `{"key", "type", "default"}` 列表，对黑板中尚未存在的键按 `"bool" | "int" | "float" | "String"` 安全转型并注入默认值。
2. **`coerce_value(raw, type_hint)`**：统一服务于 Schema 初始化、表达式字面量解析与调试器 `set_var` 实时热改。
3. **`eval_expr(expr, cond_lookup, bb, fsm_ctx)`**：
   - 支持 `||`、`&&`、括号分组（含转义引号感知）、`<= / >= / != / == / < / >` 安全跨类型比较运算与前缀 `!` 取反；
   - **有界静态表达式 AST 缓存**：首帧将表达式解析为轻量 `_ExprNode` 语法树并缓存（上限 `512` 条），后续同屏百怪每帧零字符串切片与零 `StringName` 构造；
   - **安全铁律**：既不在 `cond_lookup` 注册表中、也不在 `bb` 黑板中的未知标识符，无论是否带 `!` 前缀一律返回 `false`，防止未注册草稿条件误触发状态转换。
4. **`FlowUtilityScorer.evaluate(spec, bb, eval_ctx, utility_lookup)`**：
   - 支持声明式黑板区间归一化（`bb_key` + `[min_val, max_val]` + `invert`）与宿主效用算子（`utility_key`，自动兼容 0 参或 1 参 `Callable`），并提供 `compile_spec(spec)` 预拘留 `StringName` 加速热路径；
   - 内置 6 类端点精确对齐 `[0.0, 1.0]` 的响应曲线（`linear / quad / cubic / sqrt / smoothstep / logistic`）与 `weight` 倍率；
   - 支持多考量因子 `considerations` 乘积与无限轴效用补偿因子（IAUS Makeup Factor），任一考量因子为 `0.0` 时立即硬性否决返回 `0.0`。
