@tool
extends EditorPlugin

## `.exportignore` 极简导出隔离插件门面（位于 [code]addons/build_isolation/plugin.gd[/code]）。[br]
##
## [b]核心职责：[/b][br]
## 1. 在编辑器启动时向导出管线注册 [BuildIsolationExporter]，使项目根目录的 [code]res://.exportignore[/code] 自动接管导出裁剪；[br]
## 2. 在顶部 [code]Project -> Tools[/code] 菜单挂载一键控制台预演入口，无需实际打包即可校验规则命中统计与跨层反向依赖。

#region Constants & State
## 挂载在 `Project -> Tools` 菜单下的快捷预演命令名称
const MENU_PREVIEW: String = "Preview .exportignore (Output)"

## 已注册到 Godot 导出系统的拦截器实例引用（用于插件卸载时对称清理）
var _exporter: BuildIsolationExporter = null
#endregion


#region Lifecycle
func _enter_tree() -> void:
	_exporter = BuildIsolationExporter.new()
	add_export_plugin(_exporter)
	add_tool_menu_item(MENU_PREVIEW, _on_preview_requested)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_PREVIEW)
	if _exporter != null:
		remove_export_plugin(_exporter)
		_exporter = null
#endregion


#region Tool Menu Handlers
## 响应 `Project -> Tools -> Preview .exportignore (Output)`：模拟全项目导出并在底部 Output 面板打印摘要与泄漏告警。
func _on_preview_requested() -> void:
	var matcher: ExportIgnoreMatcher = ExportIgnoreMatcher.from_file()
	var sim: Dictionary = matcher.simulate_project()
	var kept: PackedStringArray = sim["kept_files"]
	var stripped: PackedStringArray = sim["stripped_files"]
	var leaks: Array = sim["reverse_leaks"]

	print(
		"[ExportIgnore] Preview -> Total: %d | Kept: %d | Stripped: %d | Leaks: %d" % [
			int(sim["total_count"]),
			kept.size(),
			stripped.size(),
			leaks.size(),
		]
	)
	for lk_v: Variant in leaks:
		if lk_v is Dictionary:
			var lk: Dictionary = lk_v
			push_error(
				"[ExportIgnore] Leak: %s:%d -> %s (%s)" % [
					str(lk.get("source_file", "")),
					int(lk.get("line", 0)),
					str(lk.get("symbol", "")),
					str(lk.get("target_file", "")),
				]
			)
#endregion
