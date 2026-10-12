class_name StorageSystem
extends BaseStorageSystem

## 存储调度系统（Facade / 编排根），对外入口为 [code]App.storage[/code]。[br]
##
## 统筹协调 [MemoryStorageDriver]、[DiskStorageDriver]、[RemoteStorageDriver] 三大可替换存储驱动（[code]drivers/[/code]），
## 基于 [StorageItem] 元数据配置与 [StorageReadMode] / [StorageWriteMode] 策略，提供统一的异步读 (Read)、写 (Write)、删 (Delete) 调度门面。
## 纯 RefCounted 实现，通过依赖注入接收 FrameworkLogger 和 NetworkClient，杜绝反向依赖全局单例。

#region Enums
## 存储介质分层定义（Multi-tier Storage）
enum Tier {
	MEMORY,  ## 内存缓存层（L1，基于 MemoryStorageDriver）
	DISK,    ## 本地磁盘持久化层（L2，可读写，基于 DiskStorageDriver 访问 user://）
	REMOTE,  ## 远端网络接口层（L3，基于 RemoteStorageDriver）
}
#endregion

#region Tier Chain Mappings
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
	StorageWriteMode.LOCAL_FIRST:     [Tier.MEMORY, Tier.DISK, Tier.REMOTE],
	StorageWriteMode.LOCAL_ONLY:      [Tier.MEMORY, Tier.DISK],
	StorageWriteMode.REMOTE_FIRST:    [Tier.REMOTE, Tier.DISK, Tier.MEMORY],
	StorageWriteMode.MEMORY_ONLY:     [Tier.MEMORY],
}
#endregion

#region Dependencies & State
var _log_service: BaseFrameworkLogger
var _network_service: BaseNetworkClient

var _memory: MemoryStorageDriver
var _disk: DiskStorageDriver
var _remote: RemoteStorageDriver

## 已绑定的 StorageItem 配置项字典（key_id -> StorageItem）
var _items: Dictionary = {}
#endregion

#region Lifecycle
func _init(log_service: BaseFrameworkLogger = null, network_service: BaseNetworkClient = null) -> void:
	_log_service = log_service
	_network_service = network_service
	_memory = MemoryStorageDriver.new()
	_disk = DiskStorageDriver.new(_log_service)
	_remote = RemoteStorageDriver.new(_network_service)


func initialize() -> Result:
	return Result.ok()


func dispose() -> void:
	clear()


func set_log_service(log_service: BaseFrameworkLogger) -> void:
	_log_service = log_service
	if _disk != null:
		_disk.set_log_service(log_service)


func set_network_service(network_service: BaseNetworkClient) -> void:
	_network_service = network_service
	if _remote != null:
		_remote.set_network_service(network_service)


## 释放指定 key 占用的内存缓存槽。空字符串或不在缓存中为安全空操作。
func release(key_id: String) -> void:
	if not key_id.is_empty() and _memory:
		_memory.release(key_id)


## 清空服务占用的所有内存缓存与绑定项（供游戏退出或特定清理时调用）
func clear() -> void:
	if _memory:
		_memory.clear()
	_items.clear()
#endregion

#region Item Binding
## 绑定一个 StorageItem 资源配置项
func bind(item: StorageItem) -> void:
	if not item or item.key_id.is_empty():
		_log_error("Cannot bind invalid or empty key_id StorageItem.")
		return
	_items[item.key_id] = item
#endregion

#region Public API - Async Read / Write / Delete / Has
## 异步读取数据。[br]
## 必须 [code]await[/code] 调用；支持传入 [StorageItem] 或唯一 key_id；根据策略依次穿透各介质层，命中后自动回灌本地缓存。
func read_async(target: Variant, policy: int = StorageReadMode.CACHE_FIRST) -> Result:
	var item: StorageItem = _resolve_item(target)
	if not item:
		return Result.err("StorageItem not bound: '%s'" % str(target))

	var chain: Array = _READ_CHAINS.get(policy, _READ_CHAINS[StorageReadMode.CACHE_FIRST])
	var hit_tier: int = -1
	var result_data: Variant = null
	var last_error: String = "No data found across configured tiers"

	# 1. 瀑布穿透：按 Tier 执行链顺序依次读取
	for tier: Tier in chain:
		var result: Result = await _read_tier(tier, item)
		if result.is_ok():
			result_data = result.value
			hit_tier = tier
			break
		else:
			last_error = str(result.error)

	if hit_tier == -1 or result_data == null:
		return Result.err(last_error)

	# 2. 缓存回灌：命中底层数据时，自动顺势写回错过的上层本地缓存
	_backfill_cache(item, result_data, chain, hit_tier)

	return Result.ok(result_data)


## 异步写入数据。[br]
## 必须 [code]await[/code] 调用；根据策略将数据写入各级存储介质。
func write_async(target: Variant, data: Variant, policy: int = StorageWriteMode.LOCAL_FIRST) -> Result:
	var item: StorageItem = _resolve_item(target)
	if not item:
		return Result.err("StorageItem not bound: '%s'" % str(target))

	var chain: Array = _WRITE_CHAINS.get(policy, _WRITE_CHAINS[StorageWriteMode.LOCAL_FIRST])

	# 按写入链顺序依次写入各层
	for tier: Tier in chain:
		var result: Result = await _write_tier(tier, item, data, policy)
		if result.is_err():
			_log_warn("Failed to write to Tier[%s]: %s" % [Tier.keys()[tier], str(result.error)])
			# 针对 REMOTE_FIRST 策略，远端首发失败立即阻断返回
			if policy == StorageWriteMode.REMOTE_FIRST and tier == Tier.REMOTE:
				return result
			if policy != StorageWriteMode.LOCAL_FIRST:
				return result

	return Result.ok()


## 异步删除本地数据（清理内存池与磁盘文件）。[br]
## 必须 [code]await[/code] 调用；本方法仅作用于本地介质，不执行远端物理删除。
func delete_async(target: Variant) -> Result:
	var item: StorageItem = _resolve_item(target)
	if not item:
		return Result.err("StorageItem not bound: '%s'" % str(target))

	# 1. 清理内存缓存
	if not item.key_id.is_empty():
		_memory.delete(item.key_id)

	# 2. 清理磁盘文件
	if not item.disk_path.is_empty():
		var disk_res: Result = _disk.delete(StringName(item.disk_path))
		if disk_res.is_err() and disk_res.error != ERR_DOES_NOT_EXIST:
			return disk_res

	return Result.ok()


## 快速探测数据是否存在（仅检查本地磁盘层）
func has(target: Variant) -> Result:
	var item: StorageItem = _resolve_item(target)
	if not item:
		return Result.err("StorageItem not bound: '%s'" % str(target))

	if item.disk_path.is_empty():
		return Result.ok(false)

	return _disk.has(StringName(item.disk_path))
#endregion

#region Internal Helpers
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


## 统一解析入参为标准 StorageItem 资源
func _resolve_item(target: Variant) -> StorageItem:
	if target is StorageItem:
		return target as StorageItem
	elif target is String:
		return _items.get(target, null)
	return null


## 路由读取请求到对应驱动层
func _read_tier(tier: Tier, item: StorageItem) -> Result:
	match tier:
		Tier.MEMORY:
			if item.key_id.is_empty():
				return Result.err("Memory read skipped: empty key_id")
			return _memory.read(item.key_id, {"memory_ttl": item.memory_ttl})

		Tier.DISK:
			if item.disk_path.is_empty():
				return Result.err("Disk read skipped: empty disk_path")
			return _disk.read(StringName(item.disk_path), {"payload_type": item.payload_type})

		Tier.REMOTE:
			if item.remote_url.is_empty():
				return Result.err("Remote read skipped: empty remote_url")
			var remote_kwargs := {
				"payload_type": item.payload_type,
				"method": item.method,
				"save_path": item.disk_path,
			}
			return await _remote.read_async(StringName(item.remote_url), remote_kwargs)

	return Result.err("Unknown Tier: %s" % str(tier))


## 路由写入请求到对应驱动层
func _write_tier(tier: Tier, item: StorageItem, data: Variant, policy: int) -> Result:
	match tier:
		Tier.MEMORY:
			if item.key_id.is_empty():
				return Result.ok()
			return _memory.write(item.key_id, data, {"memory_ttl": item.memory_ttl})

		Tier.DISK:
			if item.disk_path.is_empty():
				return Result.ok()
			return _disk.write(StringName(item.disk_path), data, {"payload_type": item.payload_type})

		Tier.REMOTE:
			if item.remote_url.is_empty():
				return Result.ok()
			var remote_kwargs := {
				"payload_type": item.payload_type,
				"method": item.method,
			}
			# 针对 LOCAL_FIRST 策略，远端推送支持异步非阻塞触发 (Fire-and-Forget)
			if policy == StorageWriteMode.LOCAL_FIRST:
				_remote.write_async(StringName(item.remote_url), data, remote_kwargs)
				return Result.ok()
			else:
				return await _remote.write_async(StringName(item.remote_url), data, remote_kwargs)

	return Result.err("Unknown Tier: %s" % str(tier))


## 缓存回灌：把命中层读到的数据，写入本条读链上排在它前面、穿透失败的本地层。[br]
## [param chain] 与本次 [method read_async] 相同的 Tier 查找链；[param hit_tier] 为实际命中层。[br]
## 只回灌 [code]Tier.MEMORY[/code] / [code]Tier.DISK[/code]：读路径绝不向远端回写。[br]
## [code]key_id[/code] 或 [code]disk_path[/code] 为空时跳过对应层；[code]payload_type == "FILE"[/code] 时不把文件流序列化进磁盘 JSON。[br]
## 回灌写入失败会被忽略，不影响本次读取已返回的成功结果。
func _backfill_cache(item: StorageItem, data: Variant, chain: Array, hit_tier: int) -> void:
	for tier: Tier in chain:
		if tier == hit_tier:
			break # 命中层及之后不再处理；前面的才是需要补齐的本地缓存

		# Remote 即使排在链前（如 REMOTE_FIRST）也无对应分支，读时不会推云端
		if tier == Tier.MEMORY:
			if not item.key_id.is_empty():
				_memory.write(item.key_id, data, {"memory_ttl": item.memory_ttl})
		elif tier == Tier.DISK:
			if not item.disk_path.is_empty() and item.payload_type != "FILE":
				_disk.write(StringName(item.disk_path), data, {"payload_type": item.payload_type})
#endregion
