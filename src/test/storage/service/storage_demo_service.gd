class_name StorageDemoService
extends RefCounted

## 存档加密演练场核心验证与交互实验编排服务（`src/test/storage/service/`）。[br]
##
## 负责驱动 9 项自动化安全契约自检、实时切换全局存档加密开关与硬件指纹策略、
## 模拟字节篡改 / 异机替档 / 跨槽位覆盖攻击，并采样磁盘真实物理字节供透视面板渲染。

#region Constants & Fields
const LOG_TAG: String = "StorageTest"

var state: StorageDemoState = StorageDemoState.new()
var save_model: StorageDemoSaveModel = StorageDemoSaveModel.new()
var prefs_model: StorageDemoPrefsModel = StorageDemoPrefsModel.new()

var _master_secret: String = "slacker_survivors_save_kdf_v1"
var _is_running_suite: bool = false
#endregion


#region Initialization & Policy Sync
func initialize_from_env() -> void:
	GameEnvService.setup_and_activate()
	var cfg: GameEnvConfig = GameEnvService.get_current_config()
	_master_secret = cfg.save_encryption_secret.strip_edges()
	if _master_secret.is_empty():
		_master_secret = "slacker_survivors_save_kdf_v1"

	state.env_name = App.env.get_name() if (App != null and App.env != null) else "LOCAL"
	state.encryption_enabled = cfg.enable_save_encryption
	state.bind_device_enabled = cfg.bind_save_to_device
	state.compress_enabled = cfg.compress_saves
	state.plaintext_fallback_enabled = cfg.allow_plaintext_save_fallback
	state.device_fingerprint_tag = _compute_masked_device_tag()
	_apply_current_policy_to_storage()


func _apply_current_policy_to_storage() -> void:
	if App == null or App.storage == null:
		return
	if state.encryption_enabled:
		App.storage.set_save_encryption(
			_master_secret,
			state.bind_device_enabled,
			state.compress_enabled,
			state.plaintext_fallback_enabled
		)
	else:
		App.storage.clear_save_encryption()
#endregion


#region 9-Case Automated Security Verification Suite
func run_automated_suite_async() -> int:
	if _is_running_suite or App == null or App.storage == null:
		return state.passed_cases
	_is_running_suite = true

	var passed: int = 0
	var lines: Array[String] = []
	_append_log("开始执行 Storage 全局存档加密与硬件指纹 9 项自动化断言...")

	# Case 1: 4 套 env_*.tres 环境配置资源装载与开关校验
	var local_cfg: GameEnvConfig = ResourceLoader.load(GameEnvService.ENV_LOCAL_PATH) as GameEnvConfig
	var dev_cfg: GameEnvConfig = ResourceLoader.load(GameEnvService.ENV_DEV_PATH) as GameEnvConfig
	var staging_cfg: GameEnvConfig = ResourceLoader.load(GameEnvService.ENV_STAGING_PATH) as GameEnvConfig
	var prod_cfg: GameEnvConfig = ResourceLoader.load(GameEnvService.ENV_PROD_PATH) as GameEnvConfig
	var case1_ok: bool = (
		local_cfg != null
		and dev_cfg != null
		and staging_cfg != null
		and prod_cfg != null
		and local_cfg.enable_save_encryption
		and local_cfg.bind_save_to_device
		and local_cfg.allow_plaintext_save_fallback
		and prod_cfg.enable_save_encryption
		and prod_cfg.bind_save_to_device
		and not prod_cfg.allow_plaintext_save_fallback
	)
	if case1_ok:
		passed += 1
		lines.append("[PASS 1/9] env_*.tres 多环境配置加载正常 (Prod 已关闭明文降级)")
	else:
		lines.append("[FAIL 1/9] env_*.tres 配置加载或安全开关不符合预期")

	# Case 2: GameEnvService 启动期一次性幂等注册激活
	var act_res: Result = GameEnvService.setup_and_activate()
	var case2_ok: bool = act_res.is_ok() and App.storage.is_save_encryption_enabled()
	if case2_ok:
		passed += 1
		lines.append("[PASS 2/9] GameEnvService 启动期一次性注册激活通过")
	else:
		lines.append("[FAIL 2/9] GameEnvService 启动期激活失败")

	var save_item: StorageItem = StorageDemoSaveModel.storage_item()
	var alt_item: StorageItem = StorageDemoSaveModel.alt_slot_item()
	var legacy_item: StorageItem = StorageDemoSaveModel.legacy_slot_item()
	var prefs_item: StorageItem = StorageDemoPrefsModel.storage_item()
	_cleanup_aux_files(alt_item, legacy_item)

	# Case 3: StorageItem.for_save 零配置自动 FWKE 密文落盘 + 解密还原
	App.storage.set_save_encryption(_master_secret, true, true, false)
	save_model = StorageDemoSaveModel.new()
	save_model.hero_name = "摸鱼实习生"
	save_model.level = 12
	save_model.gold = 2500
	save_model.updated_at = TimeUtils.now_string()
	var w_save_res: Result = await App.storage.write_async(save_item, save_model.to_dict())
	var raw_save_bytes: PackedByteArray = FileAccess.get_file_as_bytes(save_item.disk_path)
	var magic_head: String = raw_save_bytes.slice(0, 4).get_string_from_ascii() if raw_save_bytes.size() >= 4 else ""
	App.storage.release(String(save_item.key_id))
	var r_save_res: Result = await App.storage.read_async(save_item)
	var r_dict: Dictionary = r_save_res.value as Dictionary if (r_save_res.is_ok() and r_save_res.value is Dictionary) else {}
	var case3_ok: bool = (
		w_save_res.is_ok()
		and magic_head == "FWKE"
		and r_save_res.is_ok()
		and int(r_dict.get("gold", 0)) == 2500
	)
	if case3_ok:
		passed += 1
		lines.append("[PASS 3/9] for_save 零配置自动 FWKE 加密与解密还原一致 (%d B)" % raw_save_bytes.size())
	else:
		lines.append("[FAIL 3/9] for_save 零配置加密或解密还原异常 (magic=%s)" % magic_head)

	# Case 4: StorageItem.for_config 设备偏好自动豁免加密，保持明文 JSON
	var w_cfg_res: Result = await App.storage.write_async(prefs_item, prefs_model.to_dict())
	var raw_cfg_str: String = FileAccess.get_file_as_string(prefs_item.disk_path)
	var case4_ok: bool = w_cfg_res.is_ok() and raw_cfg_str.contains("master_volume") and not raw_cfg_str.begins_with("FWKE")
	if case4_ok:
		passed += 1
		lines.append("[PASS 4/9] for_config 设备设置自动豁免加密，保持可读明文 JSON")
	else:
		lines.append("[FAIL 4/9] for_config 明文豁免校验异常")

	# Case 5: 同机器跨存档复制覆盖重放拦截 (key_id 独立加盐派生密钥)
	FileUtils.write_bytes(alt_item.disk_path, raw_save_bytes, false)
	App.storage.release(String(alt_item.key_id))
	var replay_res: Result = await App.storage.read_async(alt_item)
	var case5_ok: bool = replay_res.is_err() and replay_res.error_code() == StorageError.DECRYPT_FAILED
	if case5_ok:
		passed += 1
		lines.append("[PASS 5/9] 跨槽位改名替档拦截通过 (key_id 独立盐值 -> DecryptFailed)")
	else:
		lines.append("[FAIL 5/9] 跨槽位改名替档未触发 DecryptFailed")

	# Case 6: 硬件设备唯一指纹绑定拦截 (切换 bind_device 无法解密原密文)
	App.storage.set_save_encryption(_master_secret, false, true, false)
	App.storage.release(String(save_item.key_id))
	var hw_mismatch_res: Result = await App.storage.read_async(save_item)
	var case6_ok: bool = hw_mismatch_res.is_err() and hw_mismatch_res.error_code() == StorageError.DECRYPT_FAILED
	if case6_ok:
		passed += 1
		lines.append("[PASS 6/9] 硬件指纹绑定校验通过 (异机指纹读取 -> DecryptFailed)")
	else:
		lines.append("[FAIL 6/9] 硬件指纹不匹配未触发 DecryptFailed")

	# Case 7: 单文件篡改自动从 .bak 备份镜像无感自愈
	App.storage.set_save_encryption(_master_secret, true, true, false)
	save_model.gold = 3000
	await App.storage.write_async(save_item, save_model.to_dict())
	var latest_bytes: PackedByteArray = FileAccess.get_file_as_bytes(save_item.disk_path)
	if latest_bytes.size() > 8:
		latest_bytes[latest_bytes.size() - 1] = latest_bytes[latest_bytes.size() - 1] ^ 0xFF
		FileUtils.write_bytes(save_item.disk_path, latest_bytes, false)
	App.storage.release(String(save_item.key_id))
	var heal_res: Result = await App.storage.read_async(save_item)
	var heal_dict: Dictionary = heal_res.value as Dictionary if (heal_res.is_ok() and heal_res.value is Dictionary) else {}
	var case7_ok: bool = heal_res.is_ok() and int(heal_dict.get("gold", 0)) == 2500
	if case7_ok:
		passed += 1
		lines.append("[PASS 7/9] 主档字节篡改自动从 .sav.bak 容灾自愈通过")
	else:
		lines.append("[FAIL 7/9] 主档篡改后 .sav.bak 自愈未通过")

	# Case 8: 主备双文件均被篡改且绑定离线 Steam Cloud 时，严格保留 DecryptFailed 不吞错
	for target_path: String in [save_item.disk_path, save_item.disk_path + ".bak"]:
		var b_arr: PackedByteArray = FileAccess.get_file_as_bytes(target_path)
		if b_arr.size() > 8:
			b_arr[b_arr.size() - 1] = b_arr[b_arr.size() - 1] ^ 0xFF
			FileUtils.write_bytes(target_path, b_arr, false)
	var cloud_save_item: StorageItem = StorageDemoSaveModel.storage_item().with_steam_cloud()
	App.storage.release(String(cloud_save_item.key_id))
	var double_tamper_res: Result = await App.storage.read_async(cloud_save_item)
	var case8_ok: bool = double_tamper_res.is_err() and double_tamper_res.error_code() == StorageError.DECRYPT_FAILED
	if case8_ok:
		passed += 1
		lines.append("[PASS 8/9] 主备双损防离线云端吞错通过 (严格返回 DecryptFailed)")
	else:
		lines.append("[FAIL 8/9] 主备双损返回码异常: %s" % double_tamper_res.error_code())

	# Case 9: 环境开关关闭写明文 + 开发期平滑升级密文 + 生产期防明文降级拦截
	App.storage.clear_save_encryption()
	await App.storage.write_async(legacy_item, {"legacy_gold": 888})
	var plain_legacy_str: String = FileAccess.get_file_as_string(legacy_item.disk_path)
	App.storage.set_save_encryption(_master_secret, true, true, false)
	App.storage.release(String(legacy_item.key_id))
	var prod_block_res: Result = await App.storage.read_async(legacy_item)
	App.storage.set_save_encryption(_master_secret, true, true, true)
	App.storage.release(String(legacy_item.key_id))
	var dev_migrate_res: Result = await App.storage.read_async(legacy_item)
	if dev_migrate_res.is_ok():
		await App.storage.write_async(legacy_item, dev_migrate_res.value)
	var upgraded_head: String = FileAccess.get_file_as_bytes(legacy_item.disk_path).slice(0, 4).get_string_from_ascii()
	var case9_ok: bool = (
		plain_legacy_str.contains("legacy_gold")
		and prod_block_res.is_err()
		and prod_block_res.error_code() == StorageError.DECRYPT_FAILED
		and dev_migrate_res.is_ok()
		and upgraded_head == "FWKE"
	)
	if case9_ok:
		passed += 1
		lines.append("[PASS 9/9] 加密开关切换、旧明文自动升级 FWKE 与防降级通过")
	else:
		lines.append("[FAIL 9/9] 旧明文迁移或防降级策略校验异常")

	_cleanup_aux_files(alt_item, legacy_item)

	# 恢复当前面板选中的环境开关策略，并写入干净的演示主档供磁盘透视镜实时展示
	_apply_current_policy_to_storage()
	save_model.gold = 2500
	save_model.level = 12
	save_model.updated_at = TimeUtils.now_string()
	await App.storage.write_async(save_item, save_model.to_dict())
	await App.storage.write_async(prefs_item, prefs_model.to_dict())

	state.passed_cases = passed
	state.total_cases = StorageDemoState.TOTAL_CASES
	state.case_lines = lines
	state.save_status_ok = (passed == StorageDemoState.TOTAL_CASES)
	state.save_status_text = "9/9 断言全部通过" if state.save_status_ok else ("%d/9 通过" % passed)
	refresh_disk_snapshots()

	_append_log("自动化断言完成: %d/%d 通过" % [passed, StorageDemoState.TOTAL_CASES])
	if App.logger != null:
		App.logger.info(LOG_TAG, "Automated storage encryption suite: %d/%d passed." % [passed, StorageDemoState.TOTAL_CASES])
		for line: String in lines:
			App.logger.info(LOG_TAG, line)

	_is_running_suite = false
	return passed
#endregion


#region Interactive Policy Switchers & Attack Simulations
func toggle_encryption_async() -> void:
	state.encryption_enabled = not state.encryption_enabled
	_apply_current_policy_to_storage()
	save_model.updated_at = TimeUtils.now_string()
	var item: StorageItem = StorageDemoSaveModel.storage_item()
	var res: Result = await App.storage.write_async(item, save_model.to_dict())
	state.save_status_ok = res.is_ok()
	state.save_status_text = (
		"已切换为加密落盘 (FWKE)" if state.encryption_enabled else "已切换为明文落盘 (JSON)"
	)
	_append_log("切换 enable_save_encryption = %s 并重新落盘主存档" % str(state.encryption_enabled))
	refresh_disk_snapshots()


func toggle_bind_device_async() -> void:
	state.bind_device_enabled = not state.bind_device_enabled
	_apply_current_policy_to_storage()
	if state.encryption_enabled:
		save_model.updated_at = TimeUtils.now_string()
		var item: StorageItem = StorageDemoSaveModel.storage_item()
		await App.storage.write_async(item, save_model.to_dict())
	state.save_status_ok = true
	state.save_status_text = (
		"已绑定本机硬件指纹 (%s)" % state.device_fingerprint_tag
		if state.bind_device_enabled
		else "已解除硬件指纹绑定 (仅口令+盐值)"
	)
	_append_log("切换 bind_save_to_device = %s" % str(state.bind_device_enabled))
	refresh_disk_snapshots()


func toggle_plaintext_fallback() -> void:
	state.plaintext_fallback_enabled = not state.plaintext_fallback_enabled
	_apply_current_policy_to_storage()
	state.save_status_ok = true
	state.save_status_text = (
		"允许兼容旧明文并自动升级" if state.plaintext_fallback_enabled else "严格模式：拒绝任何明文降级"
	)
	_append_log("切换 allow_plaintext_save_fallback = %s" % str(state.plaintext_fallback_enabled))
	refresh_disk_snapshots()


func write_save_reward_async() -> void:
	save_model.gold += 500
	save_model.level += 1
	save_model.updated_at = TimeUtils.now_string()
	var item: StorageItem = StorageDemoSaveModel.storage_item()
	var res: Result = await App.storage.write_async(item, save_model.to_dict())
	state.save_status_ok = res.is_ok()
	state.save_status_text = "写入成功 (Lv.%d · %d G)" % [save_model.level, save_model.gold]
	_append_log("写入核心存档: Lv.%d, 金币=%d -> %s" % [save_model.level, save_model.gold, state.save_format_badge])
	refresh_disk_snapshots()


func write_config_toggle_async() -> void:
	if is_equal_approx(prefs_model.master_volume, 0.80):
		prefs_model.master_volume = 0.45
		prefs_model.quality_tag = "MEDIUM"
	elif is_equal_approx(prefs_model.master_volume, 0.45):
		prefs_model.master_volume = 1.00
		prefs_model.quality_tag = "ULTRA"
	else:
		prefs_model.master_volume = 0.80
		prefs_model.quality_tag = "HIGH"
	var item: StorageItem = StorageDemoPrefsModel.storage_item()
	await App.storage.write_async(item, prefs_model.to_dict())
	_append_log("更新设备设置 config/: volume=%.2f, quality=%s (自动保持明文)" % [prefs_model.master_volume, prefs_model.quality_tag])
	refresh_disk_snapshots()


func read_and_verify_async() -> void:
	var item: StorageItem = StorageDemoSaveModel.storage_item()
	App.storage.release(String(item.key_id))
	var res: Result = await App.storage.read_async(item)
	if res.is_ok() and res.value is Dictionary:
		save_model = StorageDemoSaveModel.new(res.value as Dictionary)
		state.save_status_ok = true
		state.save_status_text = "磁盘解密校验通过 (Lv.%d · %d G)" % [save_model.level, save_model.gold]
		_append_log("清空 L1 缓存并从磁盘读取成功: Lv.%d, 金币=%d" % [save_model.level, save_model.gold])
	else:
		state.save_status_ok = false
		state.save_status_text = "拦截异常: [%s]" % res.error_code()
		_append_log("磁盘读取被安全策略拦截: [%s] %s" % [res.error_code(), res.error_message()])
	refresh_disk_snapshots()


func simulate_single_byte_tamper_async() -> void:
	var item: StorageItem = StorageDemoSaveModel.storage_item()
	# 确保已存在有效 .bak 备份后再篡改主档末尾字节
	await App.storage.write_async(item, save_model.to_dict())
	var raw_bytes: PackedByteArray = FileAccess.get_file_as_bytes(item.disk_path)
	if raw_bytes.size() > 4:
		raw_bytes[raw_bytes.size() - 1] = raw_bytes[raw_bytes.size() - 1] ^ 0xFF
		FileUtils.write_bytes(item.disk_path, raw_bytes, false)
	App.storage.release(String(item.key_id))
	var res: Result = await App.storage.read_async(item)
	if res.is_ok() and res.value is Dictionary:
		save_model = StorageDemoSaveModel.new(res.value as Dictionary)
		state.save_status_ok = true
		state.save_status_text = "检测到篡改 -> 已从 .bak 自动自愈"
		_append_log("主档末尾字节被篡改 -> HMAC 校验捕获并自动从 .sav.bak 恢复成功")
	else:
		state.save_status_ok = false
		state.save_status_text = "篡改拦截: [%s]" % res.error_code()
		_append_log("主档篡改且无可用备份 -> [%s]" % res.error_code())
	refresh_disk_snapshots()


func simulate_foreign_device_save_async() -> void:
	var item: StorageItem = StorageDemoSaveModel.storage_item()
	# 先使用模拟外机密钥派生写入一份满级作弊存档（并同步覆盖 .bak 模拟玩家整目录拷入）
	App.storage.set_save_encryption(_master_secret + "::FOREIGN_DEVICE_ID", false, true, false)
	await App.storage.write_async(item, {"hero_name": "异机替档", "level": 999, "gold": 9999999, "updated_at": TimeUtils.now_string()})
	var foreign_bytes: PackedByteArray = FileAccess.get_file_as_bytes(item.disk_path)
	FileUtils.write_bytes(item.disk_path + ".bak", foreign_bytes, false)

	# 切回本机硬件指纹加密策略尝试读取
	state.encryption_enabled = true
	state.bind_device_enabled = true
	_apply_current_policy_to_storage()

	App.storage.release(String(item.key_id))
	var res: Result = await App.storage.read_async(item)
	state.save_status_ok = false
	state.save_status_text = "异机存档已拦截 [%s]" % res.error_code()
	_append_log("注入异机 9999999 金币密文 -> 本机硬件指纹校验拦截: [%s]" % res.error_code())
	refresh_disk_snapshots()


func simulate_cross_slot_replay_async() -> void:
	if not state.encryption_enabled:
		state.encryption_enabled = true
		_apply_current_policy_to_storage()
		await App.storage.write_async(StorageDemoSaveModel.storage_item(), save_model.to_dict())

	var src_item: StorageItem = StorageDemoSaveModel.storage_item()
	var alt_item: StorageItem = StorageDemoSaveModel.alt_slot_item()
	var src_bytes: PackedByteArray = FileAccess.get_file_as_bytes(src_item.disk_path)
	FileUtils.write_bytes(alt_item.disk_path, src_bytes, false)
	App.storage.release(String(alt_item.key_id))
	var res: Result = await App.storage.read_async(alt_item)
	FileUtils.remove_file(alt_item.disk_path)
	state.save_status_ok = false
	state.save_status_text = "跨槽位覆盖已拦截 [%s]" % res.error_code()
	_append_log("将 hero_slot.sav 拷贝冒充 alt_slot.sav -> key_id 盐值校验拦截: [%s]" % res.error_code())
	refresh_disk_snapshots()
#endregion


#region Disk Raw Bytes & Text Snapshot Sampling
func refresh_disk_snapshots() -> void:
	var save_item: StorageItem = StorageDemoSaveModel.storage_item()
	var prefs_item: StorageItem = StorageDemoPrefsModel.storage_item()

	state.save_disk_path = save_item.disk_path
	state.save_has_backup = FileAccess.file_exists(save_item.disk_path + ".bak")
	if FileAccess.file_exists(save_item.disk_path):
		var raw_bytes: PackedByteArray = FileAccess.get_file_as_bytes(save_item.disk_path)
		state.save_size_bytes = raw_bytes.size()
		var magic: String = raw_bytes.slice(0, 4).get_string_from_ascii() if raw_bytes.size() >= 4 else ""
		state.save_is_encrypted_on_disk = (magic == "FWKE" or magic == "GDEC")
		if state.save_is_encrypted_on_disk:
			state.save_format_badge = (
				"FWKE · AES-256 + 指纹绑定 + ZSTD"
				if state.bind_device_enabled
				else "FWKE · AES-256 + 口令加密"
			)
		else:
			state.save_format_badge = "JSON · 明文调试模式"
		state.save_hex_preview = _format_hex_preview(raw_bytes, 40)
		state.save_raw_preview = _format_printable_preview(raw_bytes, 120)
	else:
		state.save_size_bytes = 0
		state.save_is_encrypted_on_disk = false
		state.save_format_badge = "未落盘"
		state.save_hex_preview = "(文件不存在)"
		state.save_raw_preview = ""

	state.save_decoded_summary = "角色: %s   |   等级: Lv.%d   |   金币: %d G   |   更新: %s" % [
		save_model.hero_name,
		save_model.level,
		save_model.gold,
		save_model.updated_at,
	]

	state.config_disk_path = prefs_item.disk_path
	if FileAccess.file_exists(prefs_item.disk_path):
		var cfg_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prefs_item.disk_path)
		state.config_size_bytes = cfg_bytes.size()
		state.config_raw_preview = cfg_bytes.get_string_from_utf8().strip_edges()
	else:
		state.config_size_bytes = 0
		state.config_raw_preview = "(文件不存在)"


static func _compute_masked_device_tag() -> String:
	var uid: String = OS.get_unique_id().strip_edges()
	if uid.is_empty():
		uid = OS.get_name() + "_FALLBACK"
	var digest: String = uid.sha256_text().to_upper()
	return "%s-%s..%s" % [OS.get_name().to_upper().substr(0, 3), digest.substr(0, 4), digest.substr(digest.length() - 4, 4)]


static func _format_hex_preview(bytes: PackedByteArray, max_count: int) -> String:
	var limit: int = mini(bytes.size(), max_count)
	var parts: PackedStringArray = []
	for i: int in range(limit):
		parts.append("%02X" % bytes[i])
	var joined: String = " ".join(parts)
	if bytes.size() > max_count:
		joined += "  ... (+%d B)" % (bytes.size() - max_count)
	return joined


static func _format_printable_preview(bytes: PackedByteArray, max_count: int) -> String:
	var limit: int = mini(bytes.size(), max_count)
	var chars: String = ""
	for i: int in range(limit):
		var b: int = bytes[i]
		if b >= 32 and b <= 126:
			chars += char(b)
		else:
			chars += "·"
	if bytes.size() > max_count:
		chars += "..."
	return chars


static func _cleanup_aux_files(alt_item: StorageItem, legacy_item: StorageItem) -> void:
	for p: String in [
		alt_item.disk_path,
		alt_item.disk_path + ".bak",
		legacy_item.disk_path,
		legacy_item.disk_path + ".bak",
	]:
		if FileAccess.file_exists(p):
			FileUtils.remove_file(p)


func _append_log(msg: String) -> void:
	state.event_logs.push_front("%s  %s" % [TimeUtils.now_string().substr(11, 8), msg])
	if state.event_logs.size() > 8:
		state.event_logs.resize(8)
#endregion
