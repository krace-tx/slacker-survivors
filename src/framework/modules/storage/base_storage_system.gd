@abstract
class_name BaseStorageSystem
extends RefCounted

## 存储系统门面契约（Storage System Facade Contract）。[br]
##
## 本抽象基类作为业务层与存储子系统交互的唯一规范入口，统一编排：[br]
## - [b]L1 内存高速缓存（Memory）[/b]：基于 [BudgetCache] 的容量水位与 TTL 管理，读写自动执行深拷贝隔离防止引用污染；[br]
## - [b]L2 本地磁盘持久化（Disk user://）[/b]：内置 [code].tmp[/code] 事务级原子写、[code].bak[/code] 双写容灾自愈，以及可选 ZSTD 压缩与 AES-256 加密；[br]
## - [b]L3 远端云存档/资源（Remote HTTP）[/b]：通过 [BaseNetworkClient] 透明收发 JSON 或流式下载文件，支持并发写入追踪与版本迁移。[br]
##
## 业务代码应统一通过 [code]App.storage[/code] 访问本契约提供的方法，而无需感知底层驱动细节。


#region Configuration & Cache Management
## 绑定一个存储配置项元数据 [StorageItem]。[br]
##
## [param item] 要注册的存储项元数据（包含 `key_id`、文件路径、加解密/压缩开关、版本演进号等）。[br]
## 注册后，后续调用 [method read_async]、[method write_async] 等方法时，可直接传入对应的 `key_id`（[StringName] 或 [String]）。
@abstract
func bind(item: StorageItem) -> void


## 检查指定 [param key_id] 是否已在系统中注册绑定。
@abstract
func is_bound(key_id: StringName) -> bool


## 获取已绑定的 [StorageItem]（未绑定时返回 [code]null[/code]）。
@abstract
func get_bound_item(key_id: StringName) -> StorageItem


## 释放指定 [param key_id] 占用的 L1 内存缓存槽。[br]
##
## [param key_id] 存储项的唯一标识符。若为空字符串或内存中不存在该条目，则为安全无害的空操作。
@abstract
func release(key_id: String) -> void


## 清空当前存储系统内管理的所有 L1 内存缓存与注册绑定项。[br]
##
## 通常在玩家登出、账户切换或退出游戏时由框架统一调用。
@abstract
func clear() -> void


## 为指定 [param key_id] 注册单步存档格式版本迁移函数。[br]
##
## 当读取到的旧存档 `_schema_version` 小于 [member StorageItem.schema_version] 时，按版本链自动依次执行迁移。[br]
## [param key_id] 存储项唯一标识。[br]
## [param from_version] 起始版本号。[br]
## [param to_version] 目标版本号。[br]
## [param migrate_fn] 迁移函数 `func(old_dict: Dictionary) -> Variant`（返回迁移后的 `Dictionary` 或 `Result`）。
@abstract
func register_migration(
	key_id: StringName,
	from_version: int,
	to_version: int,
	migrate_fn: Callable
) -> Result


## 配置全局核心存档（[method StorageItem.for_save]）的透明加密与压缩策略。[br]
##
## 在启动阶段调用一次后，所有启用了 [member StorageItem.use_global_encryption]（[method StorageItem.for_save] 默认开启）
## 且未单独指定 [member StorageItem.encryption_key] 的存档项，在读写 L2 本地磁盘时将自动按各自 `key_id` 领域盐值派生独立的 AES-256 认证加密密钥；
## 通过 [method StorageItem.for_config] 创建的设备偏好设置自动豁免，始终保持明文 JSON。[br]
##
## [param passphrase] 全局存档主派生口令（传入空白字符串等同于调用 [method clear_save_encryption] 关闭全局加密）。[br]
## [param bind_device] 为 [code]true[/code] 时自动混入当前设备硬件唯一指纹（[method OS.get_unique_id]），阻止跨机器拷贝替档（默认 [code]true[/code]）。[br]
## [param auto_compress] 为 [code]true[/code] 时在加密前自动执行 ZSTD 内存帧压缩（默认 [code]true[/code]）。[br]
## [param allow_plaintext_fallback] 为 [code]true[/code] 时允许平滑读取历史未加密的明文旧档并在下次保存时自动升级为密文；正式生产环境建议设为 [code]false[/code] 以防明文降级篡改。
@abstract
func set_save_encryption(
	passphrase: String,
	bind_device: bool = true,
	auto_compress: bool = true,
	allow_plaintext_fallback: bool = false
) -> void


## 关闭并清空全局核心存档加密策略与派生密钥缓存（恢复明文落盘）。
@abstract
func clear_save_encryption() -> void


## 查询当前是否已启用全局核心存档加密策略。
@abstract
func is_save_encryption_enabled() -> bool


## 等待所有进行中的异步写入任务（含后台远端同步）完成，用于应用退出或切后台前的优雅落盘保证。
@abstract
func flush_async(timeout_seconds: float = 3.0) -> Result


## 获取存储系统运行时诊断快照（含内存池占用、已绑定条目数、进行中的写入计数等）。
@abstract
func get_diagnostics() -> Dictionary
#endregion


#region Public Async IO APIs (Multi-Tier: Memory / Disk / Remote)
## 异步读取数据。[br]
##
## 根据指定的读取策略 [param policy]，在 L1 内存、L2 磁盘、L3 远端之间瀑布穿透查找。[br]
## 当命中底层介质（如从磁盘或远端取得）后，系统会自动执行版本迁移并向更上层的本地缓存执行“缓存回灌（Backfill）”。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果；若传入 `key_id`，必须先通过 [method bind] 显式绑定。[br]
##
## [param target] 目标对象，支持传入已绑定的 `key_id`（[StringName] / [String]）或直接传入 [StorageItem] 实例。[br]
## [param policy] 读取策略模式（见 [StorageReadMode] 常量，默认为 [code]StorageReadMode.CACHE_FIRST[/code]）。[br]
## @return 返回 [Result] 对象：[br]
##   - 成功时：[code]result.value[/code] 在 `JSON` 模式下为深拷贝隔离的 [Dictionary]/[Array]，在 `FILE` 模式下统一为 [PackedByteArray]；[br]
##   - 失败时：[code]result.error[/code] 为携带 [StorageError] 错误码的 [FrameworkError]。
@abstract
func read_async(target: Variant, policy: int = 0) -> Result


## 异步写入数据（同 `key_id` 并发写入自动串行化排队，防止 `.tmp` 踩踏与数据覆盖）。[br]
##
## 根据指定的写入策略 [param policy]，依次向各级介质执行版本戳标记、序列化并落盘/上传。[br]
## 本地磁盘写入时会自动使用 [code].tmp[/code] 原子重命名与 [code].bak[/code] 容灾备份机制。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果；若传入 `key_id`，必须先通过 [method bind] 显式绑定。[br]
##
## [param target] 目标对象，支持已绑定的 `key_id`（[StringName] / [String]）或 [StorageItem] 实例。[br]
## [param data] 需要保存的数据对象（`JSON` 模式下为 [Dictionary]/[Array]，`FILE` 模式下为 [PackedByteArray]）。[br]
## [param policy] 写入策略模式（见 [StorageWriteMode] 常量，默认为 [code]StorageWriteMode.LOCAL_FIRST[/code]）。[br]
## @return 返回 [Result] 对象。
@abstract
func write_async(target: Variant, data: Variant, policy: int = 0) -> Result


## 异步删除本地数据（清理 L1 内存缓存与 L2 本地磁盘主文件、`.bak` 及 `.tmp`）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
## 为防止不可逆灾难，本方法仅清理本地介质，不会物理删除远端云存储文件。[br]
##
## [param target] 目标对象，支持已绑定的 `key_id`（[StringName] / [String]）或 [StorageItem] 实例。[br]
## @return 返回 [Result] 对象，表示删除是否成功（文件原本不存在时亦幂等返回成功）。
@abstract
func delete_async(target: Variant) -> Result


## 检查指定存储项是否存在本地数据（优先探测 L1 内存缓存，未命中则探测 L2 磁盘主文件或 `.bak` 备份）。[br]
##
## [param target] 目标对象，支持已绑定的 `key_id`（[StringName] / [String]）或 [StorageItem] 实例。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 为 [bool]（`true` 表示存在有效数据）。
@abstract
func has(target: Variant) -> Result
#endregion
