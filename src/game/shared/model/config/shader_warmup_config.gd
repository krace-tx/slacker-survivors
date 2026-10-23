class_name ShaderWarmupConfig
extends Resource

## 编辑器可视化 Shader 与特效预热清单配置表（位于 src/game/shared/model/config/）。[br]
##
## [b]核心定位（遵循 `*Config` 静态配表后缀规范）：[/b][br]
## 1. 继承自 [Resource] 并使用 `@export` 暴露到 Godot 编辑器右侧 Inspector 检查器面板，支持保存为 `.tres` 配置文件；[br]
## 2. 支持直接拖入 `.gdshader`、材质球 `.tres` 或包含内嵌 `SubResource` 材质的特效/角色预制体 `.tscn`（[PackedScene]）；[br]
## 3. 支持配置自动递归扫描目录（如 `res://src/assets/shaders/shared`），由 [WarmupAssetsTask] 或关卡加载器统一驱动 [ShaderWarmer] 预编译。[br]
##
## [b]双时机配置建议：[/b][br]
## - [b]全局启动清单[/b]：仅放入高频公共 UI 动效、通用受击闪白（HitFlash）、飘字与掉落粒子，交由闪屏管线 [WarmupAssetsTask] 执行；[br]
## - [b]关卡专属清单[/b]：每个章节/Boss 战单独配置一份 `.tres`，在进入关卡 Loading 过渡页时按需调用预热。


#region Inspector 导出配置

@export_group("Warmup Manifest")

## 直接在编辑器 Inspector 中拖入的待预热资源列表（支持混合拖入 [Shader]、[Material]、[Mesh] 或特效/角色 [PackedScene] `.tscn`）
@export var warmup_resources: Array[Resource] = []

## 自动递归扫描的资源目录列表（运行期自动发现目录下的 `.gdshader` / `.tres` / `.res` / `.tscn`）
@export_dir var scan_directories: PackedStringArray = []

## 额外显式指定的资源路径列表（按路径通过 `App.asset.preload_batch` 并发预载后送入 GPU 烘烤）
@export var extra_resource_paths: PackedStringArray = []


@export_group("Performance & Cache Policy")

## 自适应分帧步进器的单帧最大耗时预算（毫秒，默认 `6.0ms`，确保预热期间 Loading 界面动画稳定维持 60 FPS）
@export_range(1.0, 16.0, 0.5) var frame_budget_ms: float = ShaderWarmer.DEFAULT_FRAME_BUDGET_MS

## 是否在异步预载后将材质/着色器调用 `App.asset.pin()` 钉在内存缓存中（防止战斗中被 LRU 水位淘汰）
@export var pin_in_asset_cache: bool = true

#endregion


#region 公开辅助方法

## 汇总所有需要通过 `App.asset.preload_batch()` 异步预载的外部资源路径（自动去重合并 [member extra_resource_paths] 与 [member scan_directories] 扫描结果）。
func collect_all_paths() -> Array[String]:
	var all_paths: Array[String] = []
	var seen: Dictionary = {}

	for p: String in extra_resource_paths:
		if not p.is_empty() and ResourceLoader.exists(p) and not seen.has(p):
			seen[p] = true
			all_paths.append(p)

	if not scan_directories.is_empty():
		var scanned: Array[String] = ShaderWarmer.scan_directory_paths(scan_directories)
		for sp: String in scanned:
			if not seen.has(sp):
				seen[sp] = true
				all_paths.append(sp)

	return all_paths

#endregion
