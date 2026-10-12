# Autoload · 全局入口

`autoload/` 只保存 Godot 项目的两个全局入口：

- `App`（`app.gd`）：Framework 服务门面与系统生命周期入口。
- `EventBus` / `Bus`（`event_bus.gd`）：只广播已经发生的领域事实，不承载命令。

它们在 `project.godot` 中注册，具体服务由 `App` 委托 `FrameworkRuntime` 创建，不在 Autoload 脚本中直接实例化服务实现。
