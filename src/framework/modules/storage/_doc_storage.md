# Framework · Storage

## 核心

按 `StorageItem` 调度同一份载荷在三层介质上的读写：内存（`key_id`）、磁盘（`disk_path`）、远端（`remote_url`）。

本服务不编解码。JSON 只收发 `Dictionary`，FILE 只收发 `PackedByteArray`。Resource 由实体自己 `encode()` / `decode()`。

---

## 细节

- 入口：`App.storage`（`BaseStorageSystem`），由 `FrameworkRuntime` 在 boot 时创建。读写可直接传 `StorageItem`；`bind` 只为之后用 `key_id` 查找。
- 读：默认 `CACHE_FIRST`，内存 → 磁盘 → 远端。某层命中后，把数据回灌到链上更靠前的本地层（不回写远端）。
- 写：默认 `LOCAL_FIRST`，先写内存和磁盘；远端不阻塞等待。空路径的层直接跳过。
- 删：`delete_async` 只清内存和磁盘，不动远端。`has` 只查磁盘（主文件或 `.bak`）。
- 错误码前缀：`Storage.{Reason}`。

```text
src/framework/modules/storage/
├── _doc_storage.md                 # 本文档
├── base_storage_system.gd          # 公开门面契约 BaseStorageSystem（详尽注释方法名、作用、入参、返回值）
│
├── types/                          # [公开契约] 外部调用门面所需的入参/数据对象（严禁进 impl）
│   ├── storage_item.gd             # 数据对象：key_id、disk_path、remote_url、payload_type、memory_ttl
│   ├── storage_read_mode.gd        # CACHE_FIRST / REMOTE_FIRST / LOCAL_ONLY / REMOTE_ONLY / MEMORY_ONLY
│   └── storage_write_mode.gd       # LOCAL_FIRST / LOCAL_ONLY / REMOTE_FIRST / MEMORY_ONLY
│
└── impl/                           # [私有收敛] 外部绝对不可见
    ├── storage_system.gd           # 核心编排实现 (实现 BaseStorageSystem 契约)
    ├── storage_cache.gd            # 内部实现：内存容量预算、TTL 与 LRU 缓存
    └── drivers/                    # 驱动层（按物理介质解耦）
        ├── storage_driver.gd       # 驱动接口 StorageDriver
        ├── memory_storage_driver.gd# L1 内存驱动（委托 StorageCache）
        ├── disk_storage_driver.gd  # L2 本地磁盘驱动（.tmp 原子写 + .bak 自愈）
        └── remote_storage_driver.gd# L3 远端网络驱动（经 BaseNetworkClient 收发 JSON / 文件）
```

---

## 样例

```gdscript
var item := User.storage_item()

var written: Result = await App.storage.write_async(item, user.encode())
var loaded: Result = await App.storage.read_async(item)
var restored := User.decode(loaded.value as Dictionary)
```
