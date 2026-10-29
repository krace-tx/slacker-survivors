class_name StorageDemoPrefsModel
extends BaseParams

## 存档加密演练场设备偏好设置演示模型（`src/test/storage/model/`）。[br]
##
## 通过 [method StorageItem.for_config] 构造，自动豁免全局核心存档加密，始终保持可读明文 JSON。

const STORAGE_DOMAIN: StringName = &"storage"
const STORAGE_SUBJECT: StringName = &"device_prefs"
const SCHEMA_VERSION: int = 1

var master_volume: float = 0.80
var vsync_enabled: bool = true
var quality_tag: String = "HIGH"


## 设备偏好配置项（落盘至 user://config/storage/device_prefs.json，自动豁免加密）。
static func storage_item() -> StorageItem:
	return StorageItem.for_config(STORAGE_DOMAIN, String(STORAGE_SUBJECT), SCHEMA_VERSION)
