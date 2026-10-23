class_name RuntimeManifest
extends RefCounted

## Framework 核心模块拓扑清单与依赖有向无环图（DAG）校验器。
##
## 集中维护 14 个核心模块的启动顺序、强依赖（required）与可选依赖（optional），
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
	{"id": &"audio",   "required": [],          "optional": [&"asset", &"logger"]},
	{"id": &"video",   "required": [],          "optional": [&"audio", &"logger"]},
]
#endregion


#region Queries & Validation
## 获取模块总数。
static func total_steps() -> int:
	return MODULES.size()


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
#endregion
