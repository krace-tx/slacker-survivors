class_name StorageDemoState
extends RefCounted

## 存档加密演练场运行时视图状态模型（`src/test/storage/model/`）。

const TOTAL_CASES: int = 9

var env_name: String = "LOCAL"
var encryption_enabled: bool = true
var bind_device_enabled: bool = true
var compress_enabled: bool = true
var plaintext_fallback_enabled: bool = true
var device_fingerprint_tag: String = "HW-UNKNOWN"

var passed_cases: int = 0
var total_cases: int = TOTAL_CASES
var case_lines: Array[String] = []
var event_logs: Array[String] = []

var save_disk_path: String = "user://saves/storage/hero_slot.sav"
var save_size_bytes: int = 0
var save_format_badge: String = "FWKE · AES-256 + HMAC + ZSTD"
var save_is_encrypted_on_disk: bool = true
var save_has_backup: bool = false
var save_hex_preview: String = ""
var save_raw_preview: String = ""
var save_decoded_summary: String = ""
var save_status_ok: bool = true
var save_status_text: String = "就绪"

var config_disk_path: String = "user://config/storage/device_prefs.json"
var config_size_bytes: int = 0
var config_raw_preview: String = ""
