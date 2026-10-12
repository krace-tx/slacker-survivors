class_name BudgetCache
extends RefCounted

## 按 key 占槽的字节预算缓存。TTL + 水位 + LRU。
## 做：条目的放入、命中续期、挤槽、钉住禁止挤出。
## 不做：读盘、编解码、合并并发加载、入树。

#region Constants & Enums
## 未传参时的缓存估算上限。默认 32MB，给低端机留余量。
const _DEFAULT_MAX_BYTES: int = 32 * 1024 * 1024
## 未再次 [method read] 命中超过此时长则过期；默认 2 分钟。单条 [method put] 仍可传自己的 ttl。
const _DEFAULT_TTL_MSEC: int = 2 * 60 * 1000
## 估算占用达到上限的这个比例就开始挤；默认 80%，避免顶格才动。
const _DEFAULT_WATERMARK: float = 0.8
#endregion

#region State
## 当前实例的缓存估算上限（字节）。
var _max_bytes: int = _DEFAULT_MAX_BYTES
## [method put] 传入 [code]0[/code] 时用的默认过期时长（毫秒）。[code]-1[/code] 常驻由调用方自己传。
var _ttl_msec: int = _DEFAULT_TTL_MSEC
## 触发 [method flush] 挤冷数据的占用比例，相对 [_max_bytes]。
var _watermark: float = _DEFAULT_WATERMARK
## 当前缓存估算占用，与 [_cache] 条目的 bytes 同步。
var _total_bytes: int = 0
## 已入库的条目。
## key: [StringName]
## value: [code]{ value: Variant, at: int, bytes: int, ttl_msec: int }[/code]
var _cache: Dictionary = {}
## [method flush] 不得挤掉的 key。用于加载进行中。
## key: [StringName]；value: [code]true[/code]
var _pinned: Dictionary = {}
#endregion

#region Lifecycle
func _init(
	max_bytes: int = _DEFAULT_MAX_BYTES,
	ttl_msec: int = _DEFAULT_TTL_MSEC,
	watermark: float = _DEFAULT_WATERMARK
) -> void:
	# 1. 非法参数回落到默认：上限/TTL 须为正，水位须在 (0, 1]。
	_max_bytes = max_bytes if max_bytes > 0 else _DEFAULT_MAX_BYTES
	_ttl_msec = ttl_msec if ttl_msec > 0 else _DEFAULT_TTL_MSEC
	_watermark = watermark if watermark > 0.0 and watermark <= 1.0 else _DEFAULT_WATERMARK
#endregion

#region Public API
## 取 [param key]。未命中或已过期返回 [code]null[/code]；命中则续期访问时间。[br]
## 不用 [code]get[/code]：会盖住 [Object] 的同名方法。
func read(key: StringName) -> Variant:
	# 1. 空 key / 不在槽里：同步 miss。
	if key.is_empty() or not _cache.has(key):
		return null
	var entry: Dictionary = _cache[key]
	# 2. 已过期：丢掉并 miss（连钉住一起清，这条已经没了）。
	if _is_expired(entry, Time.get_ticks_msec()):
		drop(key)
		return null
	# 3. 命中续期，当作刚访问。
	entry.at = Time.get_ticks_msec()
	return entry.value


## 是否仍占槽。过期则丢掉并返回 [code]false[/code]；不续期访问时间。
func has(key: StringName) -> bool:
	# 1. 空 key / 不在槽里。
	if key.is_empty() or not _cache.has(key):
		return false
	# 2. 已过期：丢掉。
	if _is_expired(_cache[key], Time.get_ticks_msec()):
		drop(key)
		return false
	return true


## 写入 [param key]。[param ttl_msec]：[code]-1[/code] 常驻，[code]0[/code] 用实例默认，大于 0 为该条过期毫秒。[br]
## 放不下时返回 [code]false[/code]，不入库。
func put(key: StringName, value: Variant, bytes: int, ttl_msec: int = -1) -> bool:
	# 1. 空 key / 空值不入库。
	if key.is_empty() or value == null:
		return false
	var new_bytes: int = bytes if bytes > 0 else 0
	# 2. 0 用实例默认 TTL；-1 常驻；大于 0 用该条自己的毫秒。
	var resolved_ttl: int = ttl_msec
	if ttl_msec == 0:
		resolved_ttl = _ttl_msec
	# 3. 先按即将入库的体积挤过期和冷数据。
	flush(new_bytes)
	# 4. 覆盖同 key：只拿掉旧槽，钉住保留。
	if _cache.has(key):
		_evict(key)
	# 5. 仍放不下（单条比上限还大，或挤完仍满）：拒绝，避免撑爆。
	if _total_bytes + new_bytes > _max_bytes:
		return false
	# 6. 入槽并加上占用量。
	_cache[key] = {
		value = value,
		at = Time.get_ticks_msec(),
		bytes = new_bytes,
		ttl_msec = resolved_ttl,
	}
	_total_bytes += new_bytes
	return true


## 丢掉 [param key]。不存在则空操作。显式丢掉时连钉住一起清。[br]
## 返回丢掉前是否占过槽（过期条目仍算占槽）。
func drop(key: StringName) -> bool:
	# 1. 记下是否占过槽，再拿掉。
	var existed := not key.is_empty() and _cache.has(key)
	_evict(key)
	# 2. 显式丢掉则钉住也没意义了。
	_pinned.erase(key)
	return existed


## 丢掉全部槽；钉住标记一并清掉。
func clear() -> void:
	# 1. 槽、钉住、占用量一起清。
	_cache.clear()
	_pinned.clear()
	_total_bytes = 0


## 先挤过期，水位仍高再按 LRU 挤冷数据。钉住的 key 两步都不动。[param extra_bytes] 是即将入库的估算。
func flush(extra_bytes: int = 0) -> void:
	var now := Time.get_ticks_msec()
	# 1. 过期且未钉住：先腾槽。
	var expired: Array[StringName] = []
	for k: StringName in _cache:
		if _pinned.has(k):
			continue
		if _is_expired(_cache[k], now):
			expired.append(k)
	for k in expired:
		_evict(k)

	# 2. 未超水位：不用挤冷数据。
	var limit := int(_max_bytes * _watermark)
	if _total_bytes + extra_bytes < limit:
		return

	# 3. 仍超水位：未钉住里最久未命中优先，同批体积大的先丢。
	var cold: Array[StringName] = []
	for k: StringName in _cache:
		if _pinned.has(k):
			continue
		cold.append(k)
	cold.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ea: Dictionary = _cache[a]
		var eb: Dictionary = _cache[b]
		if int(ea.at) != int(eb.at):
			return int(ea.at) < int(eb.at)
		return int(ea.bytes) > int(eb.bytes)
	)
	for k in cold:
		if _total_bytes + extra_bytes < limit:
			break
		_evict(k)


## 钉住 [param key]，[method flush] 不得挤掉。用于加载进行中的路径。
func pin(key: StringName) -> void:
	# 1. 空 key 不占钉住表。
	if key.is_empty():
		return
	_pinned[key] = true


## 解除 [param key] 的钉住。未钉住则空操作。
func unpin(key: StringName) -> void:
	_pinned.erase(key)
#endregion

#region Internal
## 只拿掉槽位并扣总量，不动钉住。不在缓存里是空操作。
func _evict(key: StringName) -> void:
	# 1. 不在槽里是空操作。
	if key.is_empty() or not _cache.has(key):
		return
	# 2. 扣占用量再擦条目；钉住留给调用方。
	_total_bytes -= int(_cache[key].bytes)
	if _total_bytes < 0:
		_total_bytes = 0
	_cache.erase(key)


## [param ttl_msec] 大于 0 且距 [code]at[/code] 已超过该时长则为过期。[code]-1[/code] 常驻。
func _is_expired(entry: Dictionary, now: int) -> bool:
	# 1. ttl <= 0（含 -1 常驻）不过期。
	var ttl: int = int(entry.get("ttl_msec", -1))
	if ttl <= 0:
		return false
	# 2. 距上次访问已超过该条 ttl。
	return now - int(entry.at) >= ttl
#endregion
