# Framework · Asset

> 统一资产加载与生命周期管理门面。封装引擎底层 `ResourceLoader` 细节，提供异步加载与预算缓存。

```text
src/framework/modules/asset/
├── _doc_asset.md                   # 本文档
├── base_asset_system.gd            # 公开门面契约 BaseAssetSystem (App.asset，详尽注释)
└── impl/                           # 私有实现收敛
    ├── asset_system.gd             # 门面实现：缓存命中 → 合并并发 → 读盘 → 入库
    ├── asset_cache.gd              # 体积估算 + TTL / 水位 / LRU（BudgetCache）+ 周期闲置扫描
    └── resource_loader_adapter.gd  # 引擎边界：ResourceLoader 存在性检查与线程加载状态机
```

---

## 核心职责

1. **异步非阻塞加载**：`ResourceLoaderAdapter` 通过 `ResourceLoader.load_threaded_request` 避免主线程掉帧卡死。
2. **并发合并**：同一路径同时多次 `load` 只打一次 I/O，其余调用挂到同一请求上。
3. **预算缓存**：`AssetCache` 按估算体积占槽，超时或超水位自动淘汰；`release` / `clear` 只放掉本服务的引用。
4. **安全容错**：资源不存在或加载失败返回 `Result.err`，不抛异常。

---

## 使用范式

```gdscript
# 异步加载资源 (需 await)
var res := await App.asset.load("res://src/assets/art/player.png")
if res.is_ok():
    var texture: Texture2D = res.value
```
