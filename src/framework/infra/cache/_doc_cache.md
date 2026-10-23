# Framework · Infra · Cache (字节预算、水位线与 TTL/LRU 惰性缓存基建)

> 按 `StringName` 键占槽的纯内存字节预算缓存基础设施（[`BudgetCache`](budget_cache.gd)）。
> 为 [`AssetCache`](../../modules/asset/impl/asset_cache.gd) 与 [`StorageCache`](../../modules/storage/impl/storage_cache.gd) 提供底层统一的**字节上限管控 + 水位线触发 + TTL 惰性过期 + LRU/大体积优先淘汰 + 钉住防挤出（Pin）**能力，零 `SceneTree` 依赖、零后台轮询定时器开销。

```text
src/framework/infra/cache/
├── _doc_cache.md         # 本文档
└── budget_cache.gd       # 核心类 BudgetCache (TTL + 水位线 + LRU + Pin)
```

---

## 一、 核心设计机制

1. **字节容量预算与水位线触发（Byte Budget & Watermark）**：
   - 默认容量上限 `_DEFAULT_MAX_BYTES = 32 MB`（`32 * 1024 * 1024`），默认水位比例 `_DEFAULT_WATERMARK = 0.8`（80%）。
   - 每次写入新条目 `put(key, value, bytes, ttl_msec)` 前自动调用 `flush(new_bytes)`：先清理全部已过期的未钉住条目；若加上即将入库的 `new_bytes` 后仍超过水位线（`max_bytes * watermark`），则触发冷数据挤槽，避免顶格才被动淘汰。
2. **两级排序冷数据淘汰（LRU + Largest-Bytes Tie-Breaker）**：
   - 挤槽时仅扫描**未钉住（Unpinned）**的条目：优先淘汰**最久未访问（`at` 时间戳最小）**的条目；若访问时间相同，则**体积更大（`bytes` 更大）**的条目优先淘汰，以最快速度回落至安全水位以下。
   - 若单条数据体积超过 `_max_bytes`，或淘汰全部可挤条目后依然放不下，则 `put()` 安全拒绝并返回 `false`，绝不撑爆内存上限。
3. **三态 TTL 惰性过期与命中续期（Lazy Expiration & Touch-on-Read）**：
   - `put()` 的 `ttl_msec` 参数支持三态语义：
     - `-1`（默认）：常驻不过期；
     - `0`：使用实例默认过期时长（默认 `_DEFAULT_TTL_MSEC = 120000`，即 2 分钟）；
     - `> 0`：为该条目单独指定过期毫秒数。
   - `read(key)` 命中未过期条目时自动将 `at` 刷新为当前 `Time.get_ticks_msec()` 实现访问续期；`has(key)` 仅检查并惰性剔除过期项，**不续期**访问时间。
4. **钉住防挤出保护（Pin / Unpin）**：
   - 调用 `pin(key)` 可锁定核心常驻资产或正在异步加载中的路径，`flush()` 期间无论是过期清理还是水位 LRU 淘汰均绝对跳过已钉住的 `key`；
   - 显式调用 `drop(key)` 或 `clear()` 时则连同钉住标记一并清除。

---

## 二、 公开 API 速查

| 方法签名 | 返回值 | 说明 |
| :--- | :--- | :--- |
| `_init(max_bytes = 32MB, ttl_msec = 120000, watermark = 0.8)` | `BudgetCache` | 构造缓存实例（非法参数自动回退默认值） |
| `put(key: StringName, value: Variant, bytes: int, ttl_msec: int = -1)` | `bool` | 写入或覆盖条目并触发前置 `flush`；放不下时返回 `false` |
| `read(key: StringName)` | `Variant` | 读取条目并续期访问时间；未命中或已过期时返回 `null`（避免覆盖 `Object.get`） |
| `has(key: StringName)` | `bool` | 查询条目是否有效占槽（已过期自动剔除，不续期访问时间） |
| `drop(key: StringName)` | `bool` | 显式移除指定条目并清除其 `pin` 标记，返回移除前是否占槽 |
| `pin(key: StringName)` / `unpin(key: StringName)` | `void` | 钉住或解除钉住指定 `key`，防止被 `flush()` 挤出 |
| `flush(extra_bytes: int = 0)` | `void` | 立即执行过期清理与水位线 LRU 淘汰（预留 `extra_bytes` 空间） |
| `clear()` | `void` | 清空全部缓存条目、钉住标记并归零字节计数 |
| `size()` / `is_empty()` / `total_bytes()` / `max_bytes()` | `int` / `bool` | 缓存诊断指标：当前条目数、是否为空、已占字节数、容量上限字节数 |

---

## 三、 使用范式

```gdscript
# 1. 创建容量上限 16MB、默认 TTL 60 秒、水位线 80% 的预算缓存
var cache := BudgetCache.new(16 * 1024 * 1024, 60 * 1000, 0.8)

# 2. 结合 MemoryUtils 估算体积并写入（ttl_msec = 0 表示使用实例默认 60s TTL）
var est_bytes := MemoryUtils.estimate_resource_bytes(texture)
cache.put(&"res://src/assets/textures/lobby/tex_lobby_banner.png", texture, est_bytes, 0)

# 3. 写入常驻核心资源并钉住（ttl_msec = -1 常驻 + pin 防 LRU 挤出）
cache.put(&"res://src/assets/textures/shared/atl_shared_ui_common.png", atlas_tex, 2 * 1024 * 1024, -1)
cache.pin(&"res://src/assets/textures/shared/atl_shared_ui_common.png")

# 4. 读取缓存（命中自动续期 at 时间戳；未命中或过期返回 null）
var hit := cache.read(&"res://src/assets/textures/lobby/tex_lobby_banner.png") as Texture2D

# 5. 查询占用状态与显式丢弃
var used_bytes := cache.total_bytes()
cache.drop(&"res://src/assets/textures/lobby/tex_lobby_banner.png")
```
