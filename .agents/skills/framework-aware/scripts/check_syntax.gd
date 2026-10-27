extends SceneTree
## 全项目 GDScript 语法与静态类型编译检查器 (Headless Syntax & Type Checker)
##
## [防卡死设计]：
## 1. 本脚本严禁在顶层声明任何外部 `preload(...)` 常量，确保即使被测业务/插件脚本存在语法错误，
##    本检查器自身也 100% 能够编译通过并执行 `quit(0/1)`，绝不因编译失败回退默认 SceneTree 导致死循环；
## 2. 配合命令行 `--headless --quit` 双重兜底，保证单帧内必定退出。


func _initialize() -> void:
	# 1. 抑制 Autoload App 的延迟独立启动流程，保持纯静态语法编译环境干净
	if root != null:
		var app_node := root.get_node_or_null("App")
		if app_node != null:
			app_node.set("_boot_done", true)

	# 2. 动态加载场景契约生成器（若插件脚本自身存在语法错误则交由下方统一扫描报错，绝不阻塞本检查器编译）
	var define_service_path := "res://addons/scene_define_generator/core/define_service.gd"
	if FileAccess.file_exists(define_service_path):
		var define_script := ResourceLoader.load(define_service_path, "Script") as GDScript
		if define_script != null and define_script.can_instantiate():
			define_script.call("generate_headless")

	# 3. 递归扫描并编译校验全部 GDScript 文件
	var target_dirs: Array[String] = ["res://src", "res://addons/scene_define_generator", "res://addons/flow_graph"]
	var files: Array[String] = []
	for dir_path in target_dirs:
		_collect_gd_files(dir_path, files)

	files.sort()
	var total := files.size()
	var failed_files: Array[String] = []

	for file_path in files:
		var res := ResourceLoader.load(file_path, "Script")
		if res == null or not (res is GDScript):
			failed_files.append(file_path)
			continue
		var gd_script: GDScript = res as GDScript
		var err := gd_script.reload(true)
		if err != OK:
			failed_files.append(file_path)

	if failed_files.is_empty():
		print("[SYNTAX_PASS] %d" % total)
		quit(0)
	else:
		for fp in failed_files:
			printerr("[SYNTAX_FAIL] %s" % fp)
		quit(1)


func _collect_gd_files(dir_path: String, out_files: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var full_path := dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect_gd_files(full_path, out_files)
			elif entry.ends_with(".gd"):
				out_files.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
