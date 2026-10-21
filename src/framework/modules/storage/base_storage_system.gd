@abstract
class_name BaseStorageSystem
extends RefCounted

## 存储系统门面契约（Storage System Facade Contract）。[br]
##
## 本抽象基类作为业务层与存储子系统交互的唯一规范入口，统一编排：[br]
## - L1 内存高速缓存（Memory）[br]
## - L2 本地磁盘原子持久化与双写容灾（Disk user://）[br]
## - L3 远端云存档/接口（Remote HTTP）[br]
##
## 业务代码应统一通过 [code]App.storage[/code] 访问本契约提供的方法，而无需感知底层驱动细节。


#region Configuration & Cache Management
## 绑定一个存储配置项元数据 [StorageItem]。[br]
## 
## [param item] 要注册的存储项元数据（包含 key_id、文件路径、编解码类型、默认策略等）。[br]
## 注册后，后续调用 [method read_async]、[method write_async] 等方法时，可直接传入对应的 [code]key_id[/code] 字符串。
@abstract
func bind(item: StorageItem) -> void


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
#endregion


#region Public IO APIs
## 异步读取数据。[br]
##
## 根据指定的读取策略 [param policy]，在 L1 内存、L2 磁盘、L3 远端之间瀑布穿透查找。[br]
## 当命中底层介质（如从磁盘或远端取得）后，系统会自动向更上层的内存缓存执行“缓存回灌（Backfill）”。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param target] 目标对象，支持传入已绑定的 [code]key_id[/code] 字符串，或直接传入 [StorageItem] 实例。[br]
## [param policy] 读取策略模式（见 [StorageReadMode] 常量，默认为 [code]StorageReadMode.CACHE_FIRST[/code]）。[br]
## @return 返回 [Result] 对象：[br]
##   - 成功时：[code]result.is_ok()[/code] 为 true，[code]result.value[/code] 包含反序列化后的数据；[br]
##   - 失败时：[code]result.is_err()[/code] 为 true，包含失败原因描述。
@abstract
func read_async(target: Variant, policy: int = 0) -> Result


## 异步写入数据。[br]
##
## 根据指定的写入策略 [param policy]，依次向各级介质执行序列化并落盘/上传。[br]
## 本地磁盘写入时会自动使用 [code].tmp[/code] 原子重命名与 [code].bak[/code] 容灾备份机制。[br]
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
##
## [param target] 目标对象，支持已绑定的 [code]key_id[/code] 字符串或 [StorageItem] 实例。[br]
## [param data] 需要保存的数据对象（基础类型、Dictionary、Array 或实现了序列化契约的 Resource/Object）。[br]
## [param policy] 写入策略模式（见 [StorageWriteMode] 常量，默认为 [code]StorageWriteMode.LOCAL_FIRST[/code]）。[br]
## @return 返回 [Result] 对象：[br]
##   - 成功时：[code]result.is_ok()[/code] 为 true；[br]
##   - 失败时：[code]result.is_err()[/code] 为 true，附带各级介质写入失败信息。
@abstract
func write_async(target: Variant, data: Variant, policy: int = 0) -> Result


## 异步删除本地数据（清理 L1 内存缓存与 L2 本地磁盘文件）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
## 为防止不可逆灾难，本方法仅清理本地介质，不会物理删除远端云存储文件。[br]
##
## [param target] 目标对象，支持已绑定的 [code]key_id[/code] 字符串或 [StorageItem] 实例。[br]
## @return 返回 [Result] 对象，表示删除是否成功。
@abstract
func delete_async(target: Variant) -> Result


## 检查指定存储项是否存在本地持久化数据。[br]
##
## 优先探测 L1 内存缓存，若无则探测 L2 磁盘文件是否存在且有效。[br]
##
## [param target] 目标对象，支持已绑定的 [code]key_id[/code] 字符串或 [StorageItem] 实例。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 为 bool 类型（true 表示存在数据，false 表示不存在）。
@abstract
func has(target: Variant) -> Result
#endregion
