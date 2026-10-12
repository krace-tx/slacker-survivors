class_name StorageItem
extends Resource

## 存储条目（元数据与路由策略）。[br]
##
## 定义单个业务数据实体在全生命周期中的多级存储策略（内存 TTL、磁盘路径、云端接口等）。[br]
## 支持在 Godot 编辑器中直接通过 [b]右键 -> 新建 Resource -> StorageItem[/b] 可视化创建与配置，
## 也支持在代码中通过 [code]StorageItem.new(...)[/code] 动态构造。

#region Settings
@export var key_id: StringName            ## 资源的全局唯一短名称标识（如 &"user_profile"）

@export_group("Disk Settings")
@export var disk_path: String = ""        ## 本地持久化路径（如 user://user_profile.json），为空则不落盘

@export_group("Remote Settings")
@export var remote_url: String = ""       ## 远端拉取或推送接口的 URL
@export_enum("GET", "POST") var method: String = "GET" ## 远端默认请求方法
@export_enum("JSON", "FILE") var payload_type: String = "JSON" ## 远端交互的数据载荷格式（JSON 数据或大文件流）

@export_group("Memory Settings")
@export var memory_ttl: float = -1.0      ## 内存中存活时长（秒），-1 为常驻不过期
#endregion
