# FlowGraph Runtime · Shared (共享黑板布尔表达式与 Schema 转型内核)

## 一、 核心定位与目录结构

`addons/flow_graph/runtime/shared/` 提供供 `FSM` 与 `BT` 两大运行内核共同复用的 **轻量布尔表达式求值器与黑板 Schema 默认值转型引擎**，保持 100% 零外部依赖与 `@tool` 双态安全。

```text
addons/flow_graph/runtime/shared/
├── _doc_shared.md                    # 本文档
└── flow_blackboard_expr.gd           # FlowBlackboardExpr：Schema 默认值注入、安全类型转换与布尔表达式求值
```

## 二、 核心契约

1. **`apply_schema_defaults(schema, bb)`**：遍历 `{"key", "type", "default"}` 列表，对黑板中尚未存在的键按 `"bool" | "int" | "float" | "String"` 安全转型并注入默认值。
2. **`coerce_value(raw, type_hint)`**：统一服务于 Schema 初始化、表达式字面量解析与调试器 `set_var` 实时热改。
3. **`eval_expr(expr, cond_lookup, bb, fsm_ctx)`**：
   - 支持 `||`、`&&`、括号分组、`<= / >= / != / == / < / >` 比较运算与前缀 `!` 取反；
   - **安全铁律**：既不在 `cond_lookup` 注册表中、也不在 `bb` 黑板中的未知标识符，无论是否带 `!` 前缀一律返回 `false`，防止未注册草稿条件误触发状态转换。
