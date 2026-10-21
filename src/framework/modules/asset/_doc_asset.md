# Framework · Asset

> 统一资产加载与生命周期管理门面。封装引擎底层 `ResourceLoader` 细节，提供同步缓存直通、信号驱动异步并发合并、双阶段真并发预加载与预算感知 LRU 缓存。

```text
src/framework/modules/asset/
├── _doc_asset.md                   # 本文档
├── base_asset_system.gd            # 公开门面契约 BaseAssetSystem (App.asset)
└── impl/                           # 私有实现收敛
    ├── asset_system.gd             # 门面实现：同步 get_cached → 信号票据并发合并 → 双阶段预加载
    ├── asset_cache.gd              # O(1) 体积估算 + TTL / 水位 / LRU 惰性淘汰 (零 SceneTree 耦合)
    └── resource_loader_adapter.gd  # 引擎边界：ResourceLoader C++ 缓存直通与后台线程队列点火
```

---

## 一、核心设计特性

1. **同步缓存直通（`get_cached(path)`）**：高频场景（如 SFX 音效播放、特效生成）可通过 `App.asset.get_cached(path)` 同步读取已缓存资源（自动涵盖引擎底层 C++ `ResourceCache` 提升），**零协程状态机分配、零帧延迟**。
2. **信号驱动并发合并（Zero-Polling Inflight Ticket）**：同一路径并发调用 `load()` 时共享同一个 `_InflightTicket` 信号票据；底层加载完成当帧立即唤醒所有等待协程，无 `while` 逐帧轮询，且单次磁盘加载无额外 1 帧人为延迟。
3. **双阶段真并发批量预加载（`preload_batch(paths)`）**：第一阶段同步向引擎底层多线程队列派发全部未缓存路径的 `load_threaded_request`（瞬间打满多核 I/O 并发），第二阶段统一等待汇总结果。
4. **纯惰性预算淘汰与零 `SceneTree` 耦合**：`AssetCache` 基于 [`MemoryUtils.estimate_resource_bytes()`](file:///d:/code/GodotProject/slacker-survivors/src/framework/util/memory/memory_utils.gd) 执行 $O(1)$ 体积估算，完全依托 [`BudgetCache`](file:///d:/code/GodotProject/slacker-survivors/src/framework/infra/cache/budget_cache.gd) 在读写时执行 TTL 过期与 32MB 水位 LRU 淘汰，不挂载任何后台轮询定时器。
5. **核心资产钉住（Pin / Unpin）与释放屏障（Release Barrier）**：支持通过 `pin(path)` 锁定常驻资产防止被挤出；若加载中途调用 `release()` / `clear()`，票据自动标记 `released_before_done`，杜绝脏写回。

---

## 二、使用范式

```gdscript
# 1. 同步快路径读取已缓存资源（零协程开销，未命中返回 null）
var cached_tex := App.asset.get_cached("res://src/assets/textures/characters/player.png") as Texture2D

# 2. 异步加载单份资源
var res := await App.asset.load("res://src/assets/textures/characters/player.png")
if res.is_ok():
	var texture: Texture2D = res.value

# 3. 钉住常驻核心资产（避免被 LRU / TTL 挤出）
App.asset.pin("res://src/assets/textures/ui/common_atlas.png")

# 4. 双阶段真并发批量预加载
var batch_res := await App.asset.preload_batch([
	"res://src/assets/audio/sfx_hit.wav",
	"res://src/assets/audio/sfx_coin.wav",
])
```
