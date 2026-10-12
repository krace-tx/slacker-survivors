# Contracts · 核心契约

`contracts/` 只放跨服务共享的生命周期和错误处理契约，不放具体业务实现。

```text
src/framework/core/contracts/
├── result.gd             # 可失败操作的统一返回值 (Result)
├── framework_error.gd    # 框架通用不可变错误对象 (FrameworkError)
├── subsystem.gd          # RefCounted 子系统基类 (Subsystem)
└── node_subsystem.gd     # Node 子系统基类 (NodeSubsystem)
```

各服务模块的 `Base<Feature>` 门面抽象基类留在各自 `modules/<name>/` 目录根下，对外声明该模块公开的 API；这里的契约仅定义底层统一的生命周期与错误对象。
