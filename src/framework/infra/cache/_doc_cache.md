# Framework · Infra · Cache

> 容量与内存预算感知的 LRU 缓存基础组件。

```text
src/framework/infra/cache/
├── _doc_cache.md         # 模块规范文档
└── budget_cache.gd      # 核心类 BudgetCache
```

---

## 核心设计特性

1. **双重阈值淘汰**：支持基于元素数量（Max Count）或预估内存字节数（Byte Budget）的最近最少使用（LRU）自动淘汰。
2. **生命周期钩子**：淘汰元素时自动触发回调，便于及时调用资源的 free 或清理逻辑。

---

## 使用范式

```gdscript
var cache := BudgetCache.new(100, 50 * 1024 * 1024) # 最多 100 项，上限 50MB
cache.set_item("icon_01", texture, 1024)
var item = cache.get_item("icon_01")
```
