# Contracts · 核心契约

`contracts/` 存放跨服务共享的结果与错误处理契约，不放具体业务实现。

```text
src/framework/core/contracts/
├── result.gd             # 可失败操作的统一返回值 (Result)
└── framework_error.gd    # 框架通用不可变错误对象 (FrameworkError)
```

各服务模块的 `Base<Feature>` 门面抽象基类留在各自 `modules/<name>/` 目录根下（按职责直接继承 `Node` 或 `RefCounted`），对外声明该模块公开的 API。
