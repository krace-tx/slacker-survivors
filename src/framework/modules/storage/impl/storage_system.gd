class_name StorageSystem
extends BaseStorageSystem

## 存储调度系统（Facade / 编排根），对外入口为 [code]App.storage[/code]。[br]
##
## 核心职责：[br]
## 1. 统筹协调 [MemoryStorageDriver] (L1)、[DiskStorageDriver] (L2)、[RemoteStorageDriver] (L3) 三大存储驱动；[br]
## 2. 基于显式绑定的 [StorageItem] 元数据与 [StorageReadMode] / [StorageWriteMode] 策略链，提供统一的异步读写、删除与存在性探测；[br]
## 3. 内置 [StorageMigrator] 版本演进链、L1 深拷贝引用隔离、同 `key_id` 并发写入串行化锁，以及含后台远端推送在内的 `_inflight_writes` 优雅退出落盘追踪。

signal _write_lock_changed

#region Module Dependency Manifest
const MODULE_ID: StringName = &"storage"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"logger", &"net"]
#endregion

#region Enums & Constants
## 存储介质分层定义（Multi-tier Storage）
enum Tier {
	MEMORY,  ## 内存缓存层（L1，基于 MemoryStorageDriver，深拷贝隔离）
	DISK,    ## 本地磁盘持久化层（L2，基于 DiskStorageDriver，.tmp/.bak 自愈 + 压缩/加密）
	REMOTE,  ## 远端网络接口层（L3，基于 RemoteStorageDriver）
}

## 读策略对应的 Tier 查找链映射表
const _READ_CHAINS: Dictionary = {
	StorageReadMode.CACHE_FIRST:  [Tier.MEMORY, Tier.DISK, Tier.REMOTE],
	StorageReadMode.REMOTE_FIRST: [Tier.REMOTE, Tier.MEMORY, Tier.DISK],
	StorageReadMode.LOCAL_ONLY:   [Tier.MEMORY, Tier.DISK],
	StorageReadMode.REMOTE_ONLY:  [Tier.REMOTE],
	StorageReadMode.MEMORY_ONLY:  [Tier.MEMORY],
}

## 写策略对应的 Tier 执行链映射表
const _WRITE_CHAINS: Dictionary = {
	StorageWriteMode.LOCAL_FIRST:  [Tier.MEMORY, Tier.DISK, Tier.REMOTE],
	StorageWriteMode.LOCAL_ONLY:   [Tier.MEMORY, Tier.DISK],
	StorageWriteMode.REMOTE_FIRST: [Tier.REMOTE, Tier.DISK, Tier.MEMORY],
	StorageWriteMode.MEMORY_ONLY:  [Tier.MEMORY],
}
#endregion

#region Dependencies & State
var _log_service: BaseFrameworkLogger
var _network_service: BaseNetworkClient

var _memory: MemoryStorageDriver
var _disk: DiskStorageDriver
var _remote: RemoteStorageDriver
var _migrator: StorageMigrator

## 已绑定的 StorageItem 配置项字典（StringName(key_id) -> StorageItem）
var _items: Dictionary = {}

## 当前正在执行中的异步写操作计数（含 LOCAL_FIRST 后台远端推送，供 flush_async 等待完成）
var _inflight_writes: int = 0

## 同 key_id 并发写串行化互斥锁表
var _active_write_keys: Dictionary = {} ## StringName -> bool
var _write_wait_queues: Dictionary = {} ## StringName -> Array[int]
var _next_write_ticket: int = 0
var _disposed: bool = false
#endregion


#region Lifecycle
func _init(log_service: BaseFrameworkLogger = null, network_service: BaseNetworkClient = null) -> void:
	_log_service = log_service
	_network_service = network_service
	_memory = MemoryStorageDriver.new()
	_disk = DiskStorageDriver.new(_log_service)
	_remote = RemoteStorageDriver.new(_network_service)
	_migrator = StorageMigrator.new()


func initialize() -> Result:
	_disposed = false
	return Result.ok()


func shutdown_async() -> Result:
	var flush_res := await flush_async(3.0)
	clear()
	return flush_res


func dispose() -> void:
	_disposed = true
	_active_write_keys.clear()
	_write_wait_queues.clear()
	_write_lock_changed.emit()
	clear()


func set_log_service(log_service: BaseFrameworkLogger) -> void:
	_log_service = log_service
	if _disk != null:
		_disk.set_log_service(log_service)


func set_network_service(network_service: BaseNetworkClient) -> void:
	_network_service = network_service
	if _remote != null:
		_remote.set_network_service(network_service)
#endregion


#region Configuration & Cache Management
## 绑定一个 StorageItem 资源配置项
func bind(item: StorageItem) -> void:
	if item == null or item.key_id.is_empty():
		_log_error("Cannot bind invalid or empty key_id StorageItem.")
		return
	_items[StringName(item.key_id)] = item


func is_bound(key_id: StringName) -> bool:
	if key_id.is_empty():
		return false
	return _items.has(key_id)


func get_bound_item(key_id: StringName) -> StorageItem:
	if key_id.is_empty():
		return null
	return _items.get(key_id, null)


## 释放指定 key 占用的内存缓存槽。空字符串或不在缓存中为安全空操作。
func release(key_id: String) -> void:
	var clean := key_id.strip_edges()
	if not clean.is_empty() and _memory != null:
		_memory.release(StringName(clean))


## 清空服务占用的所有内存缓存与绑定项（供游戏退出或特定清理时调用）
func clear() -> void:
	if _memory != null:
		_memory.clear()
	if _migrator != null:
		_migrator.clear()
	_items.clear()


## 为指定 [param key_id] 注册单步存档格式版本迁移函数。
func register_migration(
	key_id: StringName,
	from_version: int,
	to_version: int,
	migrate_fn: Callable
) -> Result:
	return _migrator.register_migration(key_id, from_version, to_version, migrate_fn)


## 等待所有进行中的异步写入任务（含后台远端同步）完成。
func flush_async(timeout_seconds: float = 3.0) -> Result:
	if _inflight_writes <= 0:
		return Result.ok()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Result.ok()
	var start_msec := Time.get_ticks_msec()
	while _inflight_writes > 0:
		if timeout_seconds > 0.0 and float(Time.get_ticks_msec() - start_msec) / 1000.0 >= timeout_seconds:
			return Result.err_ex(
				StorageError.FLUSH_TIMEOUT,
				"Timed out waiting for %d in-flight storage writes." % _inflight_writes,
				{"inflight_writes": _inflight_writes, "timeout_seconds": timeout_seconds},
				true,
				null,
				FrameworkError.CATEGORY_TIMEOUT
			)
		await tree.process_frame
	return Result.ok()


func get_diagnostics() -> Dictionary:
	return {
		"bound_items_count": _items.size(),
		"inflight_writes": _inflight_writes,
		"active_write_locks": _active_write_keys.size(),
		"memory_cache": _memory.get_diagnostics() if _memory != null else {},
	}
#endregion


#region Public Async IO APIs
## 异步读取数据：支持传入已绑定的 `key_id`（[StringName] / [String]）或 [StorageItem]；命中下层后自动执行版本迁移并回灌上层缓存。
func read_async(target: Variant, policy: int = StorageReadMode.CACHE_FIRST) -> Result:
	var item: StorageItem = _resolve_item(target)
	if item == null:
		return Result.err_ex(
			StorageError.UNBOUND_ITEM,
			"StorageItem not bound: '%s'. Call bind(item) first or pass a StorageItem." % str(target),
			{"target": str(target)},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var chain: Array = _READ_CHAINS.get(policy, _READ_CHAINS[StorageReadMode.CACHE_FIRST])
	var hit_tier: int = -1
	var result_data: Variant = null
	var last_err_res: Result = null

	# 1. 瀑布穿透：按 Tier 执行链顺序依次读取
	for tier: Tier in chain:
		var result: Result = await _read_tier(tier, item)
		if result.is_ok():
			result_data = result.value
			hit_tier = tier
			break
		else:
			last_err_res = result

	if hit_tier == -1 or result_data == null:
		if last_err_res != null and last_err_res.error_code() != StorageError.NOT_FOUND:
			return last_err_res
		var msg := last_err_res.error_message() if last_err_res != null else "No data found across configured tiers."
		return Result.err_ex(
			StorageError.NOT_FOUND,
			msg,
			{"key_id": String(item.key_id), "policy": policy},
			false,
			ERR_DOES_NOT_EXIST,
			FrameworkError.CATEGORY_NOT_FOUND
		)

	# 2. 格式版本检查与迁移链执行（当 item.schema_version > 0 时生效）
	var mig_res := _migrator.migrate_if_needed(item, result_data)
	if mig_res.is_err():
		return mig_res
	var mig_info: Dictionary = mig_res.value
	result_data = mig_info["data"]
	var was_migrated: bool = bool(mig_info["migrated"])

	# 3. 缓存回灌：若触发了版本迁移，同步刷新本地内存与磁盘；否则回灌链上位于 hit_tier 之前的本地层
	if was_migrated:
		_log_warn("Migrated '%s' schema v%d -> v%d; persisting upgraded payload." % [
			String(item.key_id), int(mig_info["from_version"]), int(mig_info["to_version"])
		])
		if not item.key_id.is_empty():
			_memory.write(item.key_id, result_data, {"memory_ttl": item.memory_ttl})
		if not item.disk_path.is_empty() and item.payload_type != "FILE":
			_disk.write(StringName(item.disk_path), result_data, _build_disk_kwargs(item))
	else:
		_backfill_cache(item, result_data, chain, hit_tier)

	return Result.ok(MemoryStorageDriver.clone_payload(result_data))


## 异步写入数据（同 key_id 自动串行化排队，防止并发写冲突）。
func write_async(target: Variant, data: Variant, policy: int = StorageWriteMode.LOCAL_FIRST) -> Result:
	var item: StorageItem = _resolve_item(target)
	if item == null:
		return Result.err_ex(
			StorageError.UNBOUND_ITEM,
			"StorageItem not bound: '%s'. Call bind(item) first or pass a StorageItem." % str(target),
			{"target": str(target)},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)
	if data == null:
		return Result.err_ex(
			StorageError.INVALID_PARAM,
			"Storage write failed: data cannot be null for '%s'." % String(item.key_id),
			{"key_id": String(item.key_id)},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	var lock_key := _get_lock_key(item)
	_inflight_writes += 1
	await _acquire_write_lock(lock_key)

	var stamped_data: Variant = _migrator.stamp_version(item, MemoryStorageDriver.clone_payload(data))
	var chain: Array = _WRITE_CHAINS.get(policy, _WRITE_CHAINS[StorageWriteMode.LOCAL_FIRST])

	for tier: Tier in chain:
		var result: Result = await _write_tier(tier, item, stamped_data, policy)
		if result.is_err():
			_log_warn("Failed to write '%s' to Tier[%s]: %s" % [
				String(item.key_id), Tier.keys()[tier], result.error_message()
			])
			if policy == StorageWriteMode.REMOTE_FIRST and tier == Tier.REMOTE:
				_release_write_lock(lock_key)
				_inflight_writes = maxi(0, _inflight_writes - 1)
				return result
			if policy != StorageWriteMode.LOCAL_FIRST:
				_release_write_lock(lock_key)
				_inflight_writes = maxi(0, _inflight_writes - 1)
				return result

	_release_write_lock(lock_key)
	_inflight_writes = maxi(0, _inflight_writes - 1)
	return Result.ok()


## 异步删除本地数据（清理 L1 内存池与 L2 磁盘文件）。
func delete_async(target: Variant) -> Result:
	var item: StorageItem = _resolve_item(target)
	if item == null:
		return Result.err_ex(
			StorageError.UNBOUND_ITEM,
			"StorageItem not bound: '%s'." % str(target),
			{"target": str(target)},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	if not item.key_id.is_empty():
		_memory.delete(item.key_id)

	if not item.disk_path.is_empty():
		var disk_res: Result = _disk.delete(StringName(item.disk_path))
		if disk_res.is_err() and disk_res.error_code() != StorageError.NOT_FOUND:
			return disk_res

	return Result.ok()


## 快速探测数据是否存在（优先探测 L1 内存缓存，若未命中则探测 L2 磁盘主文件或 .bak 备份）。
func has(target: Variant) -> Result:
	var item: StorageItem = _resolve_item(target)
	if item == null:
		return Result.err_ex(
			StorageError.UNBOUND_ITEM,
			"StorageItem not bound: '%s'." % str(target),
			{"target": str(target)},
			false,
			null,
			FrameworkError.CATEGORY_PARAM
		)

	if not item.key_id.is_empty():
		var mem_has := _memory.has(item.key_id)
		if mem_has.is_ok() and bool(mem_has.value):
			return Result.ok(true)

	if not item.disk_path.is_empty():
		return _disk.has(StringName(item.disk_path))

	return Result.ok(false)
#endregion


#region Internal Routing, Backfill & Locking Helpers
## 严格解析 target：仅接受有效 StorageItem 实例，或已通过 bind() 显式注册的 key_id。
func _resolve_item(target: Variant) -> StorageItem:
	if target is StorageItem:
		var item := target as StorageItem
		if item.key_id.is_empty() and item.disk_path.is_empty() and item.remote_url.is_empty():
			return null
		return item

	if target is String or target is StringName:
		var raw_str := String(target).strip_edges()
		if raw_str.is_empty():
			return null
		return _items.get(StringName(raw_str), null)

	return null


func _read_tier(tier: Tier, item: StorageItem) -> Result:
	match tier:
		Tier.MEMORY:
			if item.key_id.is_empty():
				return Result.err_code(StorageError.NOT_FOUND, "Memory read skipped: empty key_id.")
			return _memory.read(item.key_id, {"memory_ttl": item.memory_ttl})

		Tier.DISK:
			if item.disk_path.is_empty():
				return Result.err_code(StorageError.NOT_FOUND, "Disk read skipped: empty disk_path.")
			return _disk.read(StringName(item.disk_path), _build_disk_kwargs(item))

		Tier.REMOTE:
			if item.remote_url.is_empty():
				return Result.err_code(StorageError.NOT_FOUND, "Remote read skipped: empty remote_url.")
			var remote_kwargs := {
				"payload_type": item.payload_type,
				"method": item.method,
				"save_path": item.disk_path,
				"use_backup": item.use_backup,
				"expected_md5": item.expected_md5,
			}
			return await _remote.read_async(StringName(item.remote_url), remote_kwargs)

	return Result.err_code(StorageError.INVALID_PARAM, "Unknown Tier: %s" % str(tier))


func _write_tier(tier: Tier, item: StorageItem, data: Variant, policy: int) -> Result:
	match tier:
		Tier.MEMORY:
			if item.key_id.is_empty():
				return Result.ok()
			return _memory.write(item.key_id, data, {"memory_ttl": item.memory_ttl})

		Tier.DISK:
			if item.disk_path.is_empty():
				return Result.ok()
			return _disk.write(StringName(item.disk_path), data, _build_disk_kwargs(item))

		Tier.REMOTE:
			if item.remote_url.is_empty():
				return Result.ok()
			var remote_kwargs := {
				"payload_type": item.payload_type,
				"method": item.method if item.method != "GET" else "POST",
			}
			# 针对 LOCAL_FIRST 策略，启动受 _inflight_writes 追踪的后台远端同步
			if policy == StorageWriteMode.LOCAL_FIRST:
				_spawn_background_remote_write(item, data, remote_kwargs)
				return Result.ok()
			else:
				return await _remote.write_async(StringName(item.remote_url), data, remote_kwargs)

	return Result.err_code(StorageError.INVALID_PARAM, "Unknown Tier: %s" % str(tier))


func _spawn_background_remote_write(item: StorageItem, data: Variant, remote_kwargs: Dictionary) -> void:
	_inflight_writes += 1
	(func() -> void:
		var res: Result = await _remote.write_async(StringName(item.remote_url), data, remote_kwargs)
		if res.is_err():
			_log_warn("Background remote sync failed for '%s' (%s): %s" % [
				String(item.key_id), item.remote_url, res.error_message()
			])
		_inflight_writes = maxi(0, _inflight_writes - 1)
	).call()


func _backfill_cache(item: StorageItem, data: Variant, chain: Array, hit_tier: int) -> void:
	for tier: Tier in chain:
		if tier == hit_tier:
			break

		if tier == Tier.MEMORY:
			if not item.key_id.is_empty():
				_memory.write(item.key_id, data, {"memory_ttl": item.memory_ttl})
		elif tier == Tier.DISK:
			if item.disk_path.is_empty():
				continue
			# 若 FILE 模式已在 Tier.REMOTE 下载时直接原子落盘到了 item.disk_path（且未开启额外压缩/加密），无需重复写盘
			if item.payload_type == "FILE" and hit_tier == Tier.REMOTE and not item.compressed and item.encryption_key.is_empty():
				continue
			_disk.write(StringName(item.disk_path), data, _build_disk_kwargs(item))


static func _build_disk_kwargs(item: StorageItem) -> Dictionary:
	return {
		"payload_type": item.payload_type,
		"use_backup": item.use_backup,
		"compressed": item.compressed,
		"encryption_key": item.encryption_key,
		"expected_md5": item.expected_md5,
	}


static func _get_lock_key(item: StorageItem) -> StringName:
	if not item.key_id.is_empty():
		return item.key_id
	if not item.disk_path.is_empty():
		return StringName(item.disk_path)
	return StringName(item.remote_url)


func _acquire_write_lock(lock_key: StringName) -> void:
	if lock_key.is_empty() or _disposed:
		return
	var queue: Array = _write_wait_queues.get(lock_key, [])
	if not _active_write_keys.has(lock_key) and queue.is_empty():
		_active_write_keys[lock_key] = true
		return

	_next_write_ticket += 1
	var ticket := _next_write_ticket
	queue.append(ticket)
	_write_wait_queues[lock_key] = queue

	while not _disposed:
		var cur_queue: Array = _write_wait_queues.get(lock_key, [])
		if not _active_write_keys.has(lock_key) and not cur_queue.is_empty() and int(cur_queue[0]) == ticket:
			cur_queue.pop_front()
			if cur_queue.is_empty():
				_write_wait_queues.erase(lock_key)
			_active_write_keys[lock_key] = true
			return
		await _write_lock_changed


func _release_write_lock(lock_key: StringName) -> void:
	if lock_key.is_empty():
		return
	_active_write_keys.erase(lock_key)
	_write_lock_changed.emit()


func _log_warn(message: String) -> void:
	if _log_service != null:
		_log_service.warn("StorageSystem", message)
	else:
		push_warning("StorageSystem: %s" % message)


func _log_error(message: String) -> void:
	if _log_service != null:
		_log_service.error("StorageSystem", message)
	else:
		push_error("StorageSystem: %s" % message)
#endregion
