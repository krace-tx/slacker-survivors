class_name RuntimeManifest
extends RefCounted

## Framework 核心模块拓扑清单与依赖有向无环图（DAG）校验器。
##
## 集中维护 15 个核心模块的启动顺序、强依赖（required）与可选依赖（optional），
## 并提供静态 DAG 拓扑合法性校验与模块自身声明一致性核对。

#region Dependency Graph Table
## 标准拓扑启动顺序与模块契约映射表
const MODULES: Array[Dictionary] = [
	{"id": &"env",     "required": [],          "optional": []},
	{"id": &"logger",  "required": [],          "optional": [&"env"]},
	{"id": &"clock",   "required": [],          "optional": []},
	{"id": &"asset",   "required": [],          "optional": []},
	{"id": &"input",   "required": [],          "optional": [&"logger"]},
	{"id": &"haptic",  "required": [],          "optional": [&"input"]},
	{"id": &"net",     "required": [],          "optional": [&"logger", &"env"]},
	{"id": &"auth",    "required": [],          "optional": [&"env", &"logger", &"clock", &"net"]},
	{"id": &"storage", "required": [],          "optional": [&"logger", &"net"]},
	{"id": &"locale",  "required": [],          "optional": []},
	{"id": &"scene",   "required": [&"asset"],  "optional": [&"logger"]},
	{"id": &"display", "required": [],          "optional": [&"logger"]},
	{"id": &"cursor",  "required": [],          "optional": [&"display", &"input", &"logger"]},
	{"id": &"audio",   "required": [],          "optional": [&"asset", &"logger"]},
	{"id": &"video",   "required": [],          "optional": [&"audio", &"logger"]},
]
#endregion


#region Queries & Validation
## 获取模块总数。
static func total_steps() -> int:
	return MODULES.size()


## 按 0 基拓扑序号读取模块清单项（越界时返回空字典）。
static func get_entry(step_index: int) -> Dictionary:
	if step_index < 0 or step_index >= MODULES.size():
		return {}
	return MODULES[step_index]


## 按模块 ID 查找拓扑清单项（未找到时返回空字典）。
static func find_entry(module_id: StringName) -> Dictionary:
	for entry: Dictionary in MODULES:
		if entry["id"] == module_id:
			return entry
	return {}


## 校验模块依赖有向无环图（DAG）与启动拓扑顺序合法性。
static func validate_dag() -> Result:
	var seen_ids: Dictionary = {}
	for entry: Dictionary in MODULES:
		var mod_id: StringName = entry["id"]
		if seen_ids.has(mod_id):
			return Result.err_code("Core.DuplicateModule", "Duplicate module ID in manifest: '%s'." % String(mod_id))
		seen_ids[mod_id] = true

	var initialized_so_far: Dictionary = {}
	for entry: Dictionary in MODULES:
		var mod_id: StringName = entry["id"]
		var all_deps: Array = []
		all_deps.append_array(entry.get("required", []))
		all_deps.append_array(entry.get("optional", []))

		for dep in all_deps:
			var dep_id: StringName = dep as StringName
			if dep_id == mod_id:
				return Result.err_code("Core.SelfDependency", "Module '%s' cannot depend on itself." % String(mod_id))
			if not seen_ids.has(dep_id):
				return Result.err_code(
					"Core.UnknownDependency",
					"Module '%s' declares unknown dependency '%s'." % [String(mod_id), String(dep_id)]
				)
			if not initialized_so_far.has(dep_id):
				return Result.err_code(
					"Core.DependencyOrderViolation",
					"Module '%s' is scheduled before its dependency '%s' (cycle or topological violation)." % [
						String(mod_id), String(dep_id)
					]
				)
		initialized_so_far[mod_id] = true

	return Result.ok()


## 核对第 [param step_index]（0 基）步装配的服务实例是否与拓扑清单声明完全一致。
static func verify_step_contract(step_index: int, service: Object) -> Result:
	if service == null or not is_instance_valid(service):
		return Result.err_code("Core.InvalidService", "Cannot install null or invalid service at step %d." % (step_index + 1))
	if step_index < 0 or step_index >= MODULES.size():
		return Result.err_code(
			"Core.StepOutOfBounds",
			"Install step %d exceeds manifest total (%d)." % [step_index + 1, MODULES.size()]
		)

	var entry: Dictionary = MODULES[step_index]
	var expected_id: StringName = entry["id"]
	var script: Script = service.get_script() as Script
	if script == null:
		return Result.err_code(
			"Core.MissingModuleManifest",
			"Service for '%s' has no attached GDScript." % String(expected_id)
		)

	var consts: Dictionary = script.get_script_constant_map()
	var actual_id := StringName(str(consts.get("MODULE_ID", &"")))
	if actual_id != expected_id:
		return Result.err_code(
			"Core.ManifestMismatch",
			"Step %d expected module '%s', but service declared MODULE_ID '%s'." % [
				step_index + 1, String(expected_id), String(actual_id)
			]
		)

	var expected_req: Array = entry.get("required", [])
	var actual_req: Array = consts.get("REQUIRED_MODULES", [])
	if not _same_module_list(expected_req, actual_req):
		return Result.err_code(
			"Core.ManifestMismatch",
			"Module '%s' REQUIRED_MODULES %s does not match RuntimeManifest %s." % [
				String(expected_id), str(actual_req), str(expected_req)
			]
		)

	var expected_opt: Array = entry.get("optional", [])
	var actual_opt: Array = consts.get("OPTIONAL_MODULES", [])
	if not _same_module_list(expected_opt, actual_opt):
		return Result.err_code(
			"Core.ManifestMismatch",
			"Module '%s' OPTIONAL_MODULES %s does not match RuntimeManifest %s." % [
				String(expected_id), str(actual_opt), str(expected_opt)
			]
		)

	return Result.ok()


static func _same_module_list(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if StringName(str(a[i])) != StringName(str(b[i])):
			return false
	return true
#endregion
