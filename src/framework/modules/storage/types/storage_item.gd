class_name StorageItem
extends Resource

## 存储条目（元数据与多级路由策略契约）。[br]
##
## 定义单个业务数据实体在全生命周期中的多级存储策略（L1 内存 TTL、L2 磁盘路径/容灾/压缩/加密、L3 云端接口及 Schema 版本号）。[br]
## 业务层统一通过语义工厂 [method for_config]（映射至 [code]user://config/<domain>/<subject>.json[/code]）或
## [method for_save]（映射至 [code]user://saves/<domain>/<subject>.<ext>[/code]）构造，确保一级生命周期分区与二级架构域 1:1 镜像隔离。

#region Settings
@export var key_id: StringName = &""      ## 资源的全局唯一命名空间标识（标准格式：&"<domain>:<subject>"，如 &"shared:player_profile"）

@export_group("Disk Settings")
@export var disk_path: String = ""        ## 本地持久化路径（如 user://saves/shared/player_profile.json），为空则不落盘
@export var use_backup: bool = true       ## 是否启用 .tmp 原子写 + .bak 容灾备份与损坏自愈（默认开启）
@export var compressed: bool = false      ## 是否使用 ZSTD 算法压缩落盘（适用于体积较大的关卡快照或配置缓存）
@export var encryption_key: String = ""   ## AES-256 加密口令（非空时自动加密落盘，防止明文篡改存档）
@export var expected_md5: String = ""     ## FILE 载荷模式下可选的 32 位十六进制 MD5 完整性校验码

@export_group("Remote Settings")
@export var remote_url: String = ""       ## 远端拉取或推送接口的 URL（支持相对路径、完整 http(s):// 地址，或 steam://<cloud_file> 协议）
@export var steam_cloud_file: String = "" ## Steam Cloud (ISteamRemoteStorage) 远端文件名（如 "shared/player_profile.json"）
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


#region Semantic Domain Factories
## 按「二级架构域 + 主体名」合成全局唯一的存储键标识（格式：[code]&"<domain>:<subject>"[/code]）。
static func make_key(domain: StringName, subject: String) -> StringName:
	var clean_domain := String(domain).strip_edges()
	var clean_subject := subject.strip_edges().trim_prefix("/").trim_suffix("/")
	return StringName("%s:%s" % [clean_domain, clean_subject])


## 构造【设备级本地配置】存储项（一级分区：[constant FileUtils.USER_CONFIG_DIR]，二级架构域：[param domain]）。[br]
## 物理路径固定映射为 [code]user://config/<domain>/<subject>.json[/code]，保持明文 JSON 且不随云存档跨设备覆盖。[br]
## [param domain] 二级架构域（[code]&"shared"[/code] 或具体 Feature 目录名）。[br]
## [param subject] 配置文件主体名（不含扩展名，如 [code]"game_settings"[/code]）。[br]
## [param p_schema_version] 配置结构版本号（默认 [code]1[/code]）。[br]
## [param p_memory_ttl] L1 内存缓存存活秒数（默认 [code]-1.0[/code] 常驻）。
static func for_config(
	domain: StringName,
	subject: String,
	p_schema_version: int = 1,
	p_memory_ttl: float = -1.0
) -> StorageItem:
	var clean_domain := String(domain).strip_edges()
	var clean_subject := subject.strip_edges().get_basename()
	var full_path := "%s/%s/%s.json" % [FileUtils.USER_CONFIG_DIR, clean_domain, clean_subject]
	return StorageItem.new(make_key(domain, clean_subject), full_path, p_schema_version, p_memory_ttl)


## 构造【玩家核心存档】存储项（一级分区：[constant FileUtils.USER_SAVES_DIR]，二级架构域：[param domain]）。[br]
## 物理路径固定映射为 [code]user://saves/<domain>/<subject>.<ext>[/code]，纳入 `.tmp/.bak` 容灾自愈与云存档同步范围。[br]
## [param domain] 二级架构域（[code]&"shared"[/code] 或具体 Feature 目录名，如 [code]&"battle"[/code]）。[br]
## [param subject] 存档文件主体名（不含扩展名，如 [code]"player_profile"[/code]）。[br]
## [param p_schema_version] 存档结构版本号（默认 [code]1[/code]）。[br]
## [param ext] 扩展名（明文 JSON 传 [code]"json"[/code]，压缩或加密二进制存档传 [code]"sav"[/code]）。[br]
## [param p_memory_ttl] L1 内存缓存存活秒数（默认 [code]-1.0[/code] 常驻）。
static func for_save(
	domain: StringName,
	subject: String,
	p_schema_version: int = 1,
	ext: String = "json",
	p_memory_ttl: float = -1.0
) -> StorageItem:
	var clean_domain := String(domain).strip_edges()
	var clean_subject := subject.strip_edges().get_basename()
	var clean_ext := ext.strip_edges().trim_prefix(".")
	if clean_ext.is_empty():
		clean_ext = "json"
	var full_path := "%s/%s/%s.%s" % [FileUtils.USER_SAVES_DIR, clean_domain, clean_subject, clean_ext]
	return StorageItem.new(make_key(domain, clean_subject), full_path, p_schema_version, p_memory_ttl)
#endregion


#region Fluent Builders
## 链式设置本地磁盘路径与是否启用 `.bak` 容灾备份。
func with_disk(p_disk_path: String, p_use_backup: bool = true) -> StorageItem:
	disk_path = p_disk_path.strip_edges()
	use_backup = p_use_backup
	return self


## 链式配置远端 HTTP(S) URL、请求方法与载荷类型。
func with_remote(p_remote_url: String, p_method: String = "GET", p_payload_type: String = "JSON") -> StorageItem:
	remote_url = p_remote_url.strip_edges()
	method = p_method.strip_edges().to_upper()
	payload_type = p_payload_type.strip_edges().to_upper()
	return self


## 链式开启 Steam Cloud (`ISteamRemoteStorage`) 云存档同步支持。[br]
## - 可单独调用（自动将 [member remote_url] 设为 [code]steam://<cloud_file>[/code]）；[br]
## - 也可与 [method with_remote] 组合调用（实现「自建 HTTP 后端云存档 + Steam Cloud 双通道镜像备份与降级回退」）。[br]
## [param p_cloud_filename] Steam Cloud 远端相对文件名（为空时自动截取 [member disk_path] 在 [code]user://saves/[/code] 下的相对路径）。
func with_steam_cloud(p_cloud_filename: String = "") -> StorageItem:
	var resolved_name := p_cloud_filename.strip_edges().trim_prefix("/")
	if resolved_name.is_empty():
		var saves_prefix := FileUtils.USER_SAVES_DIR + "/"
		if disk_path.begins_with(saves_prefix):
			resolved_name = disk_path.trim_prefix(saves_prefix)
		elif disk_path.begins_with("user://"):
			resolved_name = disk_path.trim_prefix("user://")
		else:
			resolved_name = String(key_id).replace(":", "/") + ".json"
	steam_cloud_file = resolved_name
	if remote_url.is_empty():
		remote_url = "steam://%s" % resolved_name
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
