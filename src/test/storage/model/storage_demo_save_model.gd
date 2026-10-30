class_name StorageDemoSaveModel
extends BaseParams

## 存档加密演练场核心进度演示模型（`src/test/storage/model/`）。[br]
##
## 演示业务层零加密样板代码写法：[method storage_item] 仅调用 [method StorageItem.for_save]，
## 自动继承启动期由 [GameEnvService] 注册的全局 AES-256 加密、硬件指纹绑定与 ZSTD 压缩。

const STORAGE_DOMAIN: StringName = &"storage"
const STORAGE_SUBJECT: StringName = &"hero_slot"
const ALT_SUBJECT: StringName = &"alt_slot"
const LEGACY_SUBJECT: StringName = &"legacy_slot"
const SCHEMA_VERSION: int = 1

var hero_name: String = "摸鱼实习生"
var level: int = 12
var gold: int = 2500
var updated_at: String = "2026-10-29 15:30:00"


## 主存档槽位（落盘至 user://saves/storage/hero_slot.sav，零加密配置自动继承全局策略）。
static func storage_item() -> StorageItem:
	return StorageItem.for_save(STORAGE_DOMAIN, String(STORAGE_SUBJECT), SCHEMA_VERSION)


## 副存档槽位（用于模拟将 A 档密文直接改名覆盖 B 档的重放攻击拦截测试）。
static func alt_slot_item() -> StorageItem:
	return StorageItem.for_save(STORAGE_DOMAIN, String(ALT_SUBJECT), SCHEMA_VERSION)


## 历史旧档测试槽位（用于验证明文旧档平滑升级与生产环境防降级策略）。
static func legacy_slot_item() -> StorageItem:
	return StorageItem.for_save(STORAGE_DOMAIN, String(LEGACY_SUBJECT), SCHEMA_VERSION)
