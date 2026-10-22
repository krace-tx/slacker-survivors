class_name StorageItem
extends Resource

## 存储条目（元数据与多级路由策略契约）。[br]
##
## 定义单个业务数据实体在全生命周期中的多级存储策略（L1 内存 TTL、L2 磁盘路径/容灾/压缩/加密、L3 云端接口及 Schema 版本号）。[br]
## 支持在 Godot 编辑器中通过 [b]右键 -> 新建 Resource -> StorageItem[/b] 可视化配置，
## 也支持在代码中通过 [code]StorageItem.new(&"player_data", "user://saves/player_data.json")[/code] 及链式方法快速构造。

#region Settings
@export var key_id: StringName = &""      ## 资源的全局唯一短名称标识（如 &"player_data"）

@export_group("Disk Settings")
@export var disk_path: String = ""        ## 本地持久化路径（如 user://saves/player_data.json），为空则不落盘
@export var use_backup: bool = true       ## 是否启用 .tmp 原子写 + .bak 容灾备份与损坏自愈（默认开启）
@export var compressed: bool = false      ## 是否使用 ZSTD 算法压缩落盘（适用于体积较大的关卡快照或配置缓存）
@export var encryption_key: String = ""   ## AES-256 加密口令（非空时自动加密落盘，防止明文篡改存档）
@export var expected_md5: String = ""     ## FILE 载荷模式下可选的 32 位十六进制 MD5 完整性校验码

@export_group("Remote Settings")
@export var remote_url: String = ""       ## 远端拉取或推送接口的 URL（支持相对路径或完整 http(s):// 地址）
@export_enum("GET", "POST", "PUT") var method: String = "GET" ## 远端默认请求方法
@export_enum("JSON", "FILE") var payload_type: String = "JSON" ## 数据载荷格式（JSON 字典/数组 或 FILE 二进制字节流）

@export_group("Memory Settings")
@export var memory_ttl: float = -1.0      ## L1 内存中存活时长（秒），-1.0 为常驻不过期，0.0 使用缓存池默认 TTL

@export_group("Schema & Migration")
@export var schema_version: int = 0       ## 数据格式版本号（0 表示不启用版本校验；>=1 时对 JSON Dictionary 自动注入并校验 _schema_version）
#endregion


func _init(
	p_key_id: StringName = &"",
	p_disk_path: String = "",
	p_schema_version: int = 0,
	p_memory_ttl: float = -1.0
) -> void:
	key_id = p_key_id
	disk_path = p_disk_path.strip_edges()
	schema_version = maxi(0, p_schema_version)
	memory_ttl = p_memory_ttl


#region Fluent Builders
## 链式设置本地磁盘路径与是否启用 `.bak` 容灾备份。
func with_disk(p_disk_path: String, p_use_backup: bool = true) -> StorageItem:
	disk_path = p_disk_path.strip_edges()
	use_backup = p_use_backup
	return self


## 链式配置远端 URL、请求方法与载荷类型。
func with_remote(p_remote_url: String, p_method: String = "GET", p_payload_type: String = "JSON") -> StorageItem:
	remote_url = p_remote_url.strip_edges()
	method = p_method.strip_edges().to_upper()
	payload_type = p_payload_type.strip_edges().to_upper()
	return self


## 链式配置 L1 内存存活时长（秒，`-1.0` 常驻）。
func with_memory_ttl(p_ttl_sec: float) -> StorageItem:
	memory_ttl = p_ttl_sec
	return self


## 链式配置存档格式版本号（`>= 1` 时自动启用 `_schema_version` 校验与迁移链）。
func with_schema_version(p_version: int) -> StorageItem:
	schema_version = maxi(0, p_version)
	return self


## 链式开启或关闭本地磁盘 ZSTD 压缩。
func with_compression(p_enabled: bool = true) -> StorageItem:
	compressed = p_enabled
	return self


## 链式设置本地磁盘 AES-256 加密密钥。
func with_encryption(p_password: String) -> StorageItem:
	encryption_key = p_password
	return self


## 链式开启绑定当前设备硬件指纹（[method OS.get_unique_id]）的 AES-256 加密密钥派生（防跨设备拷贝替档）。[br]
## [param p_passphrase] 应用主密钥口令。[br]
## [param p_salt] 可选领域盐值（为空时默认使用当前条目的 [member key_id]）。
func with_device_encryption(p_passphrase: String, p_salt: String = "") -> StorageItem:
	var salt_key := p_salt if not p_salt.is_empty() else String(key_id)
	encryption_key = CryptoUtils.derive_passphrase(p_passphrase, salt_key, true)
	return self


## 链式设置 FILE 载荷的预期 MD5 校验码。
func with_expected_md5(p_md5: String) -> StorageItem:
	expected_md5 = p_md5.strip_edges().to_lower()
	return self
#endregion
