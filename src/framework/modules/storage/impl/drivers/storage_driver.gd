@abstract
class_name StorageDriver
extends RefCounted

## 存储驱动（可替换后端）的通用接口。具体实现命名为 [code]<backend>_storage_driver.gd[/code]。
## 注意：统一采用 StringName 作为 Key，利用底层哈希地址比对机制，极大提升缓存字典的高频 I/O 性能

#region Public API
## 从存储介质中读取指定 key 的数据。[br]
## [param key] 数据的唯一标识符，通常为路径或 URL。[br]
## [param kwargs] 扩展参数字典，用于向特定底层驱动透传特殊配置（如 method、payload_type 等）。[br]
## 返回 [Result]：成功时返回包含数据的对象；失败或不存在时返回详细错误。
@abstract
func read(key: StringName, kwargs: Dictionary = {}) -> Result

## 将数据序列化并写入存储介质。[br]
## [param key] 数据的唯一标识符。[br]
## [param data] 待写入的数据（通常是 Dictionary、Array 或基础数据类型）。[br]
## [param kwargs] 扩展参数字典，透传给底层驱动。[br]
## 返回 [Result]：成功时为空；失败时返回详细错误。
@abstract
func write(key: StringName, data: Variant, kwargs: Dictionary = {}) -> Result

## 检查指定的 key 在介质中是否存在。[br]
## [param key] 数据的唯一标识符。[br]
## 返回 [Result]：包含 [code]true[/code] 或 [code]false[/code]。
@abstract
func has(key: StringName) -> Result

## 从存储介质中物理删除指定数据。[br]
## [param key] 数据的唯一标识符。[br]
## 返回 [Result]：成功时为空；不存在或无权限时返回错误。
@abstract
func delete(key: StringName) -> Result
#endregion
