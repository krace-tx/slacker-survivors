class_name StorageError
extends RefCounted

## 存储模块标准化错误码常量定义（Storage Error Codes）。[br]
##
## 严格遵循 Framework [code]{Module}.{Reason}[/code] 错误码规范，配合 [Result] 与 [FrameworkError] 使用。

## 目标 StorageItem 未注册绑定，或传入的 key_id / 标识符非法
const UNBOUND_ITEM: String = "Storage.UnboundItem"

## 读写参数非法（如写入数据为 null、载荷类型不匹配、缺少必要路径参数等）
const INVALID_PARAM: String = "Storage.InvalidParam"

## 指定的数据条目在所请求的存储层级（Memory / Disk / Remote）中均不存在
const NOT_FOUND: String = "Storage.NotFound"

## 本地磁盘文件读写、目录创建、.bak 备份或 .tmp 原子重命名失败
const IO_ERROR: String = "Storage.IOError"

## JSON 反序列化或序列化失败（存档文件格式损坏或非预期结构）
const PARSE_ERROR: String = "Storage.ParseError"

## 磁盘或远端下载文件的 MD5 哈希校验不匹配（数据损坏或被篡改）
const HASH_MISMATCH: String = "Storage.HashMismatch"

## 单条数据体积超过 L1 内存预算缓存（BudgetCache）的最大可用容量
const MEMORY_LIMIT_EXCEEDED: String = "Storage.MemoryLimitExceeded"

## 远端网络服务（BaseNetworkClient）未注入或未配置 remote_url
const REMOTE_UNAVAILABLE: String = "Storage.RemoteUnavailable"

## 远端存储驱动出于安全策略默认禁止物理删除云端数据
const REMOTE_DELETE_DISABLED: String = "Storage.RemoteDeleteDisabled"

## 等待进行中的异步写入任务完成超时（flush_async）
const FLUSH_TIMEOUT: String = "Storage.FlushTimeout"

## 注册存档版本迁移函数时参数非法（如 key_id 为空、版本号倒退或 Callable 无效）
const INVALID_MIGRATION: String = "Storage.InvalidMigration"

## 存档中的 _schema_version 高于当前客户端支持的 schema_version（拒绝降级读取以保护高版本存档）
const VERSION_TOO_NEW: String = "Storage.VersionTooNew"

## 版本迁移链执行步数超过上限（存在环路或过长迁移链）
const MIGRATION_LOOP: String = "Storage.MigrationLoop"

## 缺失从旧版本到目标版本的中间迁移步骤
const MIGRATION_MISSING: String = "Storage.MigrationMissing"

## 版本迁移回调函数执行返回错误 Result
const MIGRATION_FAILED: String = "Storage.MigrationFailed"

## 版本迁移回调函数未返回合法的 Dictionary 结构
const MIGRATION_INVALID_OUTPUT: String = "Storage.MigrationInvalidOutput"
