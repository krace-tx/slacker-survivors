# Framework · Storage (三级持久化存储与容灾迁移系统)

> 按 [`StorageItem`](types/storage_item.gd) 元数据统一编排同一份业务数据在三层物理介质上的读写、压缩/加密、容灾自愈与版本演进：**L1 内存（`key_id`） ➔ L2 本地磁盘（`disk_path`） ➔ L3 远端云存储（`remote_url`）**。

```text
src/framework/modules/storage/
├── _doc_storage.md                 # 本文档（12 维工程规范与使用范式）
├── base_storage_system.gd          # 公开门面契约 BaseStorageSystem (App.storage，详尽注释)
│
├── types/                          # [公开契约] 外部调用门面所需的入参/数据对象（严禁进 impl）
│   ├── storage_error.gd            # 标准错误码常量 (Storage.NotFound / Storage.VersionTooNew / Storage.IOError 等)
│   ├── storage_item.gd             # 存储项契约：key_id、disk_path、remote_url、压缩/加密开关、memory_ttl、schema_version
│   ├── storage_read_mode.gd        # 读策略：CACHE_FIRST / REMOTE_FIRST / LOCAL_ONLY / REMOTE_ONLY / MEMORY_ONLY
│   └── storage_write_mode.gd       # 写策略：LOCAL_FIRST / LOCAL_ONLY / REMOTE_FIRST / MEMORY_ONLY
│
└── impl/                           # [私有收敛] 外部绝对不可见
    ├── storage_system.gd           # 核心编排实现 (StorageSystem extends BaseStorageSystem)
    ├── storage_cache.gd            # L1 内存容量预算（默认 32MB）、水位控制、TTL 与 LRU 缓存
    ├── storage_migrator.gd         # 存档 Schema 版本校验与多步有向迁移链执行器
    └── drivers/                    # 驱动层（按物理介质正交解耦）
        ├── storage_driver.gd       # 驱动抽象接口 StorageDriver
        ├── memory_storage_driver.gd# L1 内存驱动（委托 StorageCache + 可变容器深拷贝隔离）
        ├── disk_storage_driver.gd  # L2 本地磁盘驱动（.tmp 原子写 + .bak 自愈 + ZSTD 压缩 + AES-256 加密）
        └── remote_storage_driver.gd# L3 远端网络驱动（经 BaseNetworkClient 收发 JSON / PackedByteArray）
```

---

## 一、 核心工程设计机制 (12 维治理契约)

1. **职责边界与统一载荷契约 (Responsibility & Payload Contract)**：
   - 本服务只负责多级存储路由、容灾落盘与版本迁移，不侵入具体业务实体字段。
   - **载荷类型严格一致**：无论命中 `MEMORY`、`DISK` 还是 `REMOTE`，`payload_type == "JSON"` 统一收发 [`Dictionary`](impl/storage_system.gd) / `Array`；`payload_type == "FILE"` 统一收发 `PackedByteArray`。
2. **L1 内存深拷贝引用隔离 (Deep-Copy Isolation)**：
   - [`MemoryStorageDriver`](impl/drivers/memory_storage_driver.gd) 在写入和读取 `Dictionary` / `Array` / `PackedByteArray` 时强制执行深拷贝（`duplicate(true)`），彻底杜绝业务层在外部直接修改字典导致的 L1 内存脏缓存污染。
3. **L2 磁盘 `.tmp/.bak` 双写容灾自愈与正交压缩/加密 (Atomic Save & Self-Healing)**：
   - **写入事务流**：先写入 `<path>.tmp` ➔ 将旧主文件安全备份至 `<path>.bak` ➔ 将 `.tmp` 原子重命名提升为主文件。
   - **损坏自愈流**：读取时若主文件缺失、JSON 损坏、解密失败（`StorageError.DECRYPT_FAILED`）或 MD5 不匹配，自动降级读取 `.bak` 并自愈恢复主文件。
   - **正交压缩与加密管线**：`StorageItem` 支持同时开启 `with_compression(true)`（内存 `FWKZ` ZSTD 帧压缩）与 `with_encryption(key)` / `with_device_encryption(secret)`（AES-256 加密及硬件指纹绑定防跨机器拷档），写入时自动按「先 ZSTD 压缩 ➔ 再 AES-256 加密」流水线执行。
4. **同 `key_id` 并发写串行化与退出落盘追踪 (Concurrency & Graceful Flush)**：
   - 针对同一 `key_id` 的并发 `write_async` 自动进入 FIFO 互斥锁队列串行执行，防止并发协程踩踏 `.tmp` 或发生旧数据覆盖新数据（Lost Update）。
   - `LOCAL_FIRST` 策略下的后台非阻塞远端同步同样纳入 `_inflight_writes` 计数追踪，应用退出时通过 `flush_async()` / `shutdown_async()` 确保本地与云端写入全部收尾。
5. **存档版本演进与防降级保护 (`StorageMigrator`)**：
   - 当 `StorageItem.schema_version >= 1` 时，写入自动注入 `_schema_version`；
   - 读取旧版存档时按 `register_migration(key_id, from_v, to_v, fn)` 自动链式升级并回写本地缓存与磁盘；
   - 若存档版本高于当前客户端支持版本，返回 [`StorageError.VERSION_TOO_NEW`](types/storage_error.gd) 拒绝降级覆盖坏档。
6. **显式绑定与纯异步契约 (Explicit Binding & Async Contract)**：
   - 所有读写统一通过 `await App.storage.read_async(target, policy)` / `await App.storage.write_async(target, data, policy)` 执行；
   - 按 `key_id` 访问前必须先通过 `App.storage.bind(item)` 显式注册 [`StorageItem`](types/storage_item.gd)（或直接传入 `StorageItem` 实例），未绑定时严格返回 `StorageError.UNBOUND_ITEM`。

---

## 二、 本地沙盒持久化与缓存拓扑规范 (`user://` Sandbox Topology & Tier-2 Domain Contract)

### 1. 一级按生命周期分 5 区 × 二级按架构域 1:1 镜像隔离

**层级深度铁律**：`user://<一级分区>/<二级域>/<文件名>`（严格封顶 **2 层目录**，严禁在 `user://` 或一级分区根部直接平铺业务文件，严禁出现 3 层及以上深层嵌套）。

```text
user://
├── config/                                   # [一级：设备本地配置区] 绑定当前硬件设备、不随云存档跨设备覆盖
│   ├── shared/                               # [二级：业务架构域] 对应 src/game/shared/model/save/
│   │   └── game_settings.json
│   └── <feature>/                            # [二级：业务架构域] 对应 src/game/features/<feature>/model/
│
├── saves/                                    # [一级：玩家核心存档区] 核心资产，纳入 .tmp/.bak 自愈与云存档同步
│   ├── shared/                               # [二级：业务架构域] 跨 2+ 模块共享存档 (Rule of 2+)
│   │   └── player_profile.json
│   └── <feature>/                            # [二级：业务架构域] 垂直模块私有存档 (与 Feature 目录名逐字一致)
│       └── run_snapshot.sav                  #   如 user://saves/battle/run_snapshot.sav
│
├── cache/                                    # [一级：衍生缓存区] 100% 可随时安全清空（删空不影响任何存档与设置）
│   ├── res/                                  # [二级：框架模块域] 归属 FileUtils (PCK 封包资源实体化)
│   ├── video/                                # [二级：框架模块域] 归属 VideoPlayer (视频流预热与实体化)
│   └── net/                                  # [二级：框架模块域] 归属 NetworkClient (HTTP 静态资源缓存)
│
├── tmp/                                      # [一级：瞬态事务中转区] 启动或恢复时可无条件清空
│   └── storage/                              # [二级：框架模块域] 归属 StorageSystem (远端流式下载中转)
│
└── logs/                                     # [一级：诊断日志区]
    ├── godot.log                             # (引擎底层固定输出豁免)
    └── crash/                                # [二级：框架模块域] 归属 FrameworkLogger (崩溃快照归档)
```

### 2. 二级架构与代码归属四大红线

1. **业务持久区（`config/` & `saves/`）与代码架构域 1:1 镜像**：
   - `shared/` 仅限 [`src/game/shared/model/save/`](../../../game/shared/model/save) 下的跨模块共享模型使用；
   - `<feature>/` 必须与 `src/game/features/<feature>/model/` 的模块文件夹名逐字一致，严禁跨模块越权读写。
2. **二级域与 `STORAGE_KEY` 命名空间强绑定**：
   - `key_id` 统一采用 `&"<domain>:<subject>"` 格式（如 `&"shared:game_settings"`、`&"shared:player_profile"`），彻底杜绝不同模块在 L1 内存池发生键名冲突。
3. **业务层零裸写 `user://` 路径**：
   - 业务层（`src/game/`）严禁手写 `"user://..."` 字符串或直接调用 `StorageItem.new()`，统一在 `*Model` 中通过 [`StorageItem.for_config(domain, subject, version)`](types/storage_item.gd#L52) 或 [`StorageItem.for_save(domain, subject, version, ext)`](types/storage_item.gd#L71) 构造。
4. **基建衍生区（`cache/` & `tmp/`）常量统一**：
   - 框架内部缓存与中转路径统一引用 [`FileUtils`](../../util/file/file_utils.gd#L24-L35) 的 `USER_RES_CACHE_DIR`、`USER_VIDEO_CACHE_DIR`、`USER_STORAGE_TMP_DIR` 等标准常量。

---

## 三、 使用范式

### 1. 标准模型绑定、版本迁移与三级异步读写（含 Steam Cloud & HTTP 云存档双通道）
```gdscript
# 1. 通过语义工厂构造并绑定 StorageItem（自动映射至 user://saves/shared/player_profile.json）
#    - .with_steam_cloud() 开启 Steam Cloud (ISteamRemoteStorage) 自动同步与回退
#    - .with_remote("/v1/cloud_save/player", "POST") 开启自建 HTTP 后端云存档（支持与 Steam Cloud 双写镜像）
var item := StorageItem.for_save(&"shared", "player_profile", 2) \
	.with_steam_cloud() \
	.with_remote("/v1/cloud_save/player", "POST")
App.storage.bind(item)

# 2. 注册 v1 -> v2 存档结构迁移
App.storage.register_migration(&"shared:player_profile", 1, 2, func(old_dict: Dictionary) -> Dictionary:
	old_dict["talent_levels"] = old_dict.get("talents", {})
	old_dict.erase("talents")
	return old_dict
)

# 3. 异步写入与读取
var write_res := await App.storage.write_async(&"shared:player_profile", profile.to_dict())
var read_res := await App.storage.read_async(&"shared:player_profile", StorageReadMode.CACHE_FIRST)
if read_res.is_ok():
	var profile_dict: Dictionary = read_res.value
```

### 2. 纯本地偏好设置离线读写 (`LOCAL_ONLY`)
```gdscript
# GameSettingsModel.storage_item() 内部通过 StorageItem.for_config(&"shared", "game_settings", 2) 构造
var item := GameSettingsModel.storage_item()
App.storage.bind(item)

var read_res := await App.storage.read_async(item, StorageReadMode.LOCAL_ONLY)
var settings := GameSettingsModel.new(read_res.value if read_res.is_ok() else {})

# 修改后原子落盘至 user://config/shared/game_settings.json
settings.audio.master_volume = 0.8
await App.storage.write_async(item, settings.to_dict(), StorageWriteMode.LOCAL_ONLY)
```
