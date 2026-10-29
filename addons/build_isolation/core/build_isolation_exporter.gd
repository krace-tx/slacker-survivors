@tool
class_name BuildIsolationExporter
extends EditorExportPlugin

## 基于根目录 [code]res://.exportignore[/code] 的极简导出拦截器（位于 [code]addons/build_isolation/core/[/code]）。[br]
##
## [b]导出管线三阶段执行闭环：[/b][br]
## 1. [method _export_begin]：按当前导出预设的 [param features] 标签集加载并编译 [ExportIgnoreMatcher]，
##    同时调用 [ReverseDependencyScanner] 前置排查保留区代码是否误引用了即将被剥离的文件；[br]
## 2. [method _export_file]：逐文件查询 [method ExportIgnoreMatcher.should_ignore]，命中后调用原生 [method EditorExportPlugin.skip]，
##    由引擎底层同步剔除源文件、其关联的 [code].godot/imported/[/code] 二进制缓存产物及全局类名注册表条目；[br]
## 3. [method _export_end]：在控制台输出单行瘦身统计摘要并释放当次导出瞬态上下文。

#region Constants & Transient Export State
## 注册到 Godot 导出管线的插件唯一标识名称
const PLUGIN_NAME: String = "ExportIgnoreGuard"

## 当前正在执行的导出任务所使用的规则匹配器实例（仅在 `_export_begin` ~ `_export_end` 期间持有）
var _matcher: ExportIgnoreMatcher = null
## 当前导出产物的目标磁盘路径（仅用于日志摘要展示）
var _target_path: String = ""
## 当前导出批次累计调用 `skip()` 物理剥离的文件总数
var _stripped_count: int = 0
#endregion


#region EditorExportPlugin Virtual Hooks
## 返回导出插件名称（Godot `EditorExportPlugin` 契约要求稳定非空）。
func _get_name() -> String:
	return PLUGIN_NAME


## 导出启动钩子：编译 `.exportignore` 规则并执行全项目跨层反向依赖断路扫描。
func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_matcher = ExportIgnoreMatcher.from_file(features)
	_target_path = path
	_stripped_count = 0

	# 在正式写包前静态扫描「保留区 -> 剥离区」的违规引用，及早通过 push_error 暴露断链隐患
	var sim: Dictionary = _matcher.simulate_project()
	var leaks_raw: Variant = sim.get("reverse_leaks", [])
	if leaks_raw is Array:
		var leaks: Array = leaks_raw
		for item_v: Variant in leaks:
			if item_v is Dictionary:
				var lk: Dictionary = item_v
				push_error(
					"[ExportIgnore] Reverse dependency leak! Kept '%s:%d' references ignored %s '%s' (%s)" % [
						str(lk.get("source_file", "")),
						int(lk.get("line", 0)),
						str(lk.get("kind", "ref")),
						str(lk.get("symbol", "")),
						str(lk.get("target_file", "")),
					]
				)


## 单文件导出过滤钩子：对命中 `.exportignore` 的文件调用 `skip()` 阻断写入 PCK。
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _matcher == null:
		_matcher = ExportIgnoreMatcher.from_file()
	if _matcher.should_ignore(path):
		_stripped_count += 1
		skip()


## 导出结束钩子：输出本轮剥离汇总日志并清空瞬态引用。
func _export_end() -> void:
	print("[ExportIgnore] Export '%s' complete -> stripped %d ignored files." % [_target_path, _stripped_count])
	_matcher = null
#endregion
