# FlowGraph Runtime · Debug (通用算法图桥接、实时热改、断点快筛与热重载内核)

## 一、 核心定位与目录结构

`addons/flow_graph/runtime/debug/` 提供零编辑器 UI 耦合、零外部框架依赖的 **跨进程可视化流转图桥接与双向交互调试内核**（IPC 通道前缀 `flow_graph:*`）。

```text
addons/flow_graph/runtime/debug/
├── _doc_debug.md                     # 本文档
├── base_debuggable_graph.gd          # 可选抽象基类：供任意自定义有向图算法继承接入
├── graph_debug_serializer.gd         # FSM / BT 拓扑与帧遥测字典无状态归一化器 (单次零冗余拷贝 + 子图引用检索)
├── graph_debug_command_executor.gd   # 下行调试命令执行器 (set_pause / step_once / force_node / set_var / set_breakpoint / fire_event)
├── graph_debug_binding.gd            # 单实例弱引用绑定器、dispose() 信号清理、$O(B)$ 零分配断点快筛与通用边沿断点引擎
└── graph_debug_bridge.gd             # 全局调试桥接器：多实例注册、60ms 节流、周期性死实例清扫、_paused_count 门禁与主/子图热重载分发
```

---

## 二、 核心工程机制与性能优化

1. **零循环引用与自动死实例回收（Zero-Leak Weak Binding & GC Sweep）**：
   - [`GraphDebugBinding`](graph_debug_binding.gd) 仅存储 `Object.get_instance_id()`，对自定义绑定对象自身成员方法自动降级为方法名弱调用，并在 `unregister()` / 替换时调用 `dispose()` 断开全部目标信号；
   - [`GraphDebugBridge`](graph_debug_bridge.gd) 内置 `2000ms` 周期性死实例扫描与 `should_suspend_tick` 即时失效摘除，即使业务实体销毁时漏调 `unregister()`，也不会造成字典泄漏或 `_paused_count` 悬空卡死。
2. **$O(B)$ 零分配节流期断点快筛（Fast Breakpoint Probing）**：
   - 在默认 `60ms` IPC 节流窗口内，`push_frame()` 不执行全量 AST 遍历与黑板深拷贝，而是调用 `binding.probe_breakpoints_fast()` 直接按预解析整型 ID 检查 `BTContext.get_live_node_status()`；
   - 仅当断点节点新跃迁进入激活态时才置位一次性待推送锁存器（`_breakpoint_hit_pending`）并穿透节流立即推送，且单步（`step_once`）放行时自动清空旧断点命中标记，杜绝假阳性残留。
3. **主蓝图与嵌套公共子图联动热重载（`flow_graph:hot_reload_resource`）**：
   - 编辑器保存 `.tres`（或采纳外部磁盘变更）时，自动匹配所有直接挂载该资源及通过 `sub_graph_path` 嵌套引用该子图的在线实例（配合 `ResourceLoader.CACHE_MODE_REPLACE` 穿透缓存），并对共享同一棵享元 `BTTree` 的多实体按 `secondary_id` 自动去重，仅编译与序列化拓扑 1 次。
4. **编辑器侧多会话防抖与 60 帧实质变迁去重（[`editor/debugger/`](../../editor/debugger/)）**：
   - `MermaidEditorDebugger` 维护活跃会话集，防止 `F5`/`F6` 快速重启时旧进程延迟 `stopped` 信号误清空新进程；
   - `SessionFrameRingBuffer` 签名去重自动过滤 `state_time` / `tick_count` / `elapsed_time` 与计时器徽章等递增噪音，静止待机原地刷新尾帧读数，确保 60 帧时间轴滑块完整保留最近 60 次真实状态跃迁与黑板突变。
5. **Release 零开销短路**：非 Debug 构建或未连接 `EngineDebugger` 时所有公开静态入口首行布尔短路返回，正式导出包零性能损耗。
