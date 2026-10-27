# FlowGraph Runtime · Debug (通用算法图桥接、实时热改、断点与热重载内核)

## 一、 核心定位与目录结构

`addons/flow_graph/runtime/debug/` 提供零编辑器 UI 耦合、零外部框架依赖的 **跨进程可视化流转图桥接与双向交互调试内核**（IPC 通道前缀 `flow_graph:*`）。

```text
addons/flow_graph/runtime/debug/
├── _doc_debug.md                     # 本文档
├── base_debuggable_graph.gd          # 可选抽象基类：供任意自定义有向图算法继承接入
├── graph_debug_serializer.gd         # FSM / BT 拓扑与帧遥测字典无状态归一化器 (合并暴露黑板 vars)
├── graph_debug_command_executor.gd   # 下行调试命令执行器 (set_pause / step_once / force_node / set_var / set_breakpoint / fire_event)
├── graph_debug_binding.gd            # 单实例弱引用绑定描述子、节点断点命中自动挂起与 hot_reload_ir
└── graph_debug_bridge.gd             # 全局调试桥接器：多实例注册、节流推送、_paused_count 门禁与资源级热重载分发
```

---

## 二、 核心调试能力

1. **实时黑板热改（`set_var`）与脉冲事件注入（`fire_event`）**：运行中可直接在编辑器检视面板勾选布尔开关或修改数值实时改写 `BTContext.blackboard` / `StateMachine.blackboard`，或向状态机发射脉冲事件并立即回推最新帧。
2. **节点级条件断点（`set_breakpoint`）**：当 FSM 跃迁进入断点状态，或 BT 本帧新激活断点节点时，`GraphDebugBinding` 自动将该实例置为 `is_paused = true` 并同步递增 `GraphDebugBridge._paused_count` 挂起后续 Tick，配合编辑器 60 帧环形历史滑条可逐帧复盘瞬时跳变原因。
3. **保存 `.tres` 即刻运行期热重载（`flow_graph:hot_reload_resource`）**：编辑器保存蓝图时自动按 `source_resource_path` 匹配所有在线实例（对共享同一棵享元 `BTTree` 的多实体按 `secondary_id` 自动去重仅重编译一次），零重启即刻生效。
4. **Release 零开销短路**：非 Debug 构建或未连接 `EngineDebugger` 时所有公开静态入口首行布尔短路返回，正式导出包零性能损耗。
