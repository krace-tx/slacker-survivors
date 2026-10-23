class_name ShaderWarmupReport
extends BaseParams

## Shader 与 GPU 渲染管线状态对象（PSO）预热诊断报告（位于 src/framework/infra/shader/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 记录单次预热流水线的输入资源数、经 [SceneState] 静态穿透剥离出的材质变体数、实际送入 GPU 烘烤数与命中签名缓存跳过数；[br]
## 2. 统计自适应分帧步进消耗的总渲染帧数与总毫秒耗时，供启动管线（如 [SplashBootContext]）与关卡加载器进行性能审计；[br]
## 3. 继承自 [BaseParams]，天然支持 `to_dict()` / `from_dict()` 序列化导出至性能遥测日志。


#region 统计指标属性

## 输入的原始资源（[Shader] / [Material] / [PackedScene] / [Mesh]）总数
var total_inputs: int = 0

## 经 [SceneState] 静态穿透剥离后识别出的有效（材质 + 图元载体拓扑）组合总数
var extracted_count: int = 0

## 本次实际送入微缩暗箱舞台并完成 `RenderingServer.frame_post_draw` GPU 真绘制编译的管线数
var newly_baked: int = 0

## 命中当前视口画质签名缓存（相同材质 + 图元拓扑 + MSAA 状态已在之前预热过）直接 O(1) 跳过的管线数
var skipped_cached: int = 0

## 自适应分帧步进器实际消耗的渲染帧数（每次 `await RenderingServer.frame_post_draw` 计 1 帧）
var frames_used: int = 0

## 预热全流程从静态解析到暗箱销毁的总耗时（毫秒）
var total_cost_ms: int = 0

## 是否在分帧烘烤中途被 [CancellationToken] 或宿主退树安全中断
var was_cancelled: bool = false

## 是否因 Headless 无头模式或 Dummy 空渲染器环境而自动 O(1) 短路跳过
var was_headless_skipped: bool = false

#endregion


#region 公开方法

## 生成单行可读的诊断摘要文本（便于输出至 `App.logger.info` 审计日志）。
func get_summary_text() -> String:
	if was_headless_skipped:
		return "ShaderWarmup skipped (headless/dummy renderer)."
	if was_cancelled:
		return "ShaderWarmup cancelled (baked=%d, skipped=%d, frames=%d, cost=%dms)." % [
			newly_baked, skipped_cached, frames_used, total_cost_ms
		]
	return "ShaderWarmup completed: inputs=%d, extracted=%d, baked=%d, skipped=%d, frames=%d, cost=%dms." % [
		total_inputs, extracted_count, newly_baked, skipped_cached, frames_used, total_cost_ms
	]

#endregion
