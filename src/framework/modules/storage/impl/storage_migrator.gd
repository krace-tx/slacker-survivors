class_name StorageMigrator
extends RefCounted

## 存档格式版本演进与迁移链执行器（Storage Schema Migrator）。[br]
##
## 作为 [StorageSystem] 的内部子系统，负责：[br]
## 1. 维护每个 `key_id` 的有向版本迁移步骤（`from_version -> to_version`）；[br]
## 2. 写入时为启用了 `schema_version >= 1` 的 Dictionary 自动注入 `_schema_version` 元数据；[br]
## 3. 读取旧版本存档时，自动按版本链顺序逐步迁移至最新 `item.schema_version`，并校验迁移结果完整性；[br]
## 4. 阻止低版本客户端强行读取高版本存档（返回 `Storage.VersionTooNew`），防止降级覆盖坏档。

const VERSION_FIELD: String = "_schema_version"
const MAX_MIGRATION_STEPS: int = 32

## { StringName(key_id): Array[Dictionary{from: int, to: int, fn: Callable}] }
var _chains: Dictionary = {}


## 注册单步版本迁移函数。[br]
## [param key_id] 目标存储项唯一标识。[br]
## [param from_version] 起始版本号（>= 0）。[br]
## [param to_version] 目标版本号（必须 > from_version）。[br]
## [param migrate_fn] 迁移回调 `func(old_dict: Dictionary) -> Variant`，可返回迁移后的 `Dictionary` 或 `Result`。
func register_migration(
	key_id: StringName,
	from_version: int,
	to_version: int,
	migrate_fn: Callable
) -> Result:
	if key_id.is_empty():
		return Result.err_code(StorageError.INVALID_MIGRATION, "key_id cannot be empty.")
	if from_version < 0 or to_version <= from_version:
		return Result.err_code(
			StorageError.INVALID_MIGRATION,
			"Invalid migration version range: %d -> %d for '%s'." % [from_version, to_version, String(key_id)]
		)
	if not migrate_fn.is_valid() or migrate_fn.is_null():
		return Result.err_code(StorageError.INVALID_MIGRATION, "Migration callable is invalid for '%s'." % String(key_id))

	if not _chains.has(key_id):
		_chains[key_id] = []
	var steps: Array = _chains[key_id]
	for i in range(steps.size()):
		var existing: Dictionary = steps[i]
		if int(existing["from"]) == from_version:
			steps[i] = {"from": from_version, "to": to_version, "fn": migrate_fn}
			return Result.ok()

	steps.append({"from": from_version, "to": to_version, "fn": migrate_fn})
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["from"]) < int(b["from"]))
	return Result.ok()


## 写入前标记版本号：当 `item.schema_version > 0` 且载荷为 `Dictionary` 时，返回带 `_schema_version` 的浅拷贝。
func stamp_version(item: StorageItem, data: Variant) -> Variant:
	if item == null or item.schema_version <= 0 or not (data is Dictionary):
		return data
	var dict := (data as Dictionary).duplicate()
	dict[VERSION_FIELD] = item.schema_version
	return dict


## 读取后检查并执行必要迁移。[br]
## @return 成功时返回 `Result.ok({"data": Variant, "migrated": bool, "from_version": int, "to_version": int})`。
func migrate_if_needed(item: StorageItem, raw_data: Variant) -> Result:
	if item == null or item.schema_version <= 0 or not (raw_data is Dictionary):
		return Result.ok({
			"data": raw_data,
			"migrated": false,
			"from_version": 0,
			"to_version": 0,
		})

	var target_ver := item.schema_version
	var current_dict := (raw_data as Dictionary).duplicate(true)
	var saved_ver := int(current_dict.get(VERSION_FIELD, 1))

	if saved_ver == target_ver:
		if not current_dict.has(VERSION_FIELD):
			current_dict[VERSION_FIELD] = target_ver
		return Result.ok({
			"data": current_dict,
			"migrated": false,
			"from_version": saved_ver,
			"to_version": target_ver,
		})

	if saved_ver > target_ver:
		return Result.err_ex(
			StorageError.VERSION_TOO_NEW,
			"Save data version (%d) is newer than supported schema_version (%d) for '%s'." % [
				saved_ver, target_ver, String(item.key_id)
			],
			{"key_id": String(item.key_id), "saved_version": saved_ver, "supported_version": target_ver},
			false,
			null,
			FrameworkError.CATEGORY_MIGRATION
		)

	var cur_ver := saved_ver
	var step_count := 0
	var steps: Array = _chains.get(item.key_id, [])

	while cur_ver < target_ver:
		step_count += 1
		if step_count > MAX_MIGRATION_STEPS:
			return Result.err_ex(
				StorageError.MIGRATION_LOOP,
				"Exceeded max migration steps (%d) for '%s'." % [MAX_MIGRATION_STEPS, String(item.key_id)],
				{"key_id": String(item.key_id), "from_version": saved_ver, "target_version": target_ver},
				false,
				null,
				FrameworkError.CATEGORY_MIGRATION
			)

		var matched_step: Dictionary = {}
		for step: Dictionary in steps:
			if int(step["from"]) == cur_ver:
				matched_step = step
				break

		if matched_step.is_empty():
			return Result.err_ex(
				StorageError.MIGRATION_MISSING,
				"Missing migration step from v%d to v%d for '%s'." % [cur_ver, target_ver, String(item.key_id)],
				{"key_id": String(item.key_id), "current_version": cur_ver, "target_version": target_ver},
				false,
				null,
				FrameworkError.CATEGORY_MIGRATION
			)

		var fn: Callable = matched_step["fn"]
		var next_ver := int(matched_step["to"])
		var step_out: Variant = fn.call(current_dict.duplicate(true))

		if step_out is Result:
			var step_res := step_out as Result
			if step_res.is_err():
				return Result.err_ex(
					StorageError.MIGRATION_FAILED,
					"Migration v%d -> v%d failed for '%s': %s" % [
						cur_ver, next_ver, String(item.key_id), step_res.error_message()
					],
					{"key_id": String(item.key_id), "from": cur_ver, "to": next_ver},
					false,
					step_res.error,
					FrameworkError.CATEGORY_MIGRATION
				)
			step_out = step_res.value

		if not (step_out is Dictionary):
			return Result.err_ex(
				StorageError.MIGRATION_INVALID_OUTPUT,
				"Migration v%d -> v%d for '%s' did not return a Dictionary." % [
					cur_ver, next_ver, String(item.key_id)
				],
				{"key_id": String(item.key_id), "from": cur_ver, "to": next_ver},
				false,
				null,
				FrameworkError.CATEGORY_MIGRATION
			)

		current_dict = (step_out as Dictionary).duplicate(true)
		current_dict[VERSION_FIELD] = next_ver
		cur_ver = next_ver

	current_dict[VERSION_FIELD] = target_ver
	return Result.ok({
		"data": current_dict,
		"migrated": true,
		"from_version": saved_ver,
		"to_version": target_ver,
	})


func clear() -> void:
	_chains.clear()
