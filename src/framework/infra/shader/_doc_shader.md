# Infra · Shader (零实例化预制体材质穿透提取与分帧 GPU 管线预编译基建)

## 核心定位

全框架统一的 Shader 与 GPU 管线状态对象（Pipeline State Object, PSO）分帧预热基建。
通过 **[`ShaderWarmer`](shader_warmer.gd)（静态 `SceneState` 穿透提取器 + 全特性微缩暗箱舞台 + 画质签名去重表 + 自适应帧率步进器）** 与 **[`ShaderWarmupReport`](shader_warmup_report.gd)（预热诊断指标契约）**，从物理根源解决 Godot 4 在首次展示特效、受击闪白、GPU 粒子或 3D 网格时的 **「Shader 编译掉帧尖峰（PSO Stutter）」**。

```text
src/framework/infra/shader/
├── _doc_shader.md            # 本文档
├── shader_warmer.gd          # 核心调度器 ShaderWarmer (SceneState 静态提取 + 全特性暗箱 + 签名去重 + 自适应步进)
└── shader_warmup_report.gd   # 预热审计报告契约 ShaderWarmupReport (extends BaseParams)
```

---

## 一、 四大核心防卡顿机制

| 核心机制 | 解决的工程与渲染痛点 | 实现原理 |
| :--- | :--- | :--- |
| **1. 零实例化预制体穿透提取**<br>(`SceneState Deep Extraction`) | 80% 的实战特效材质是内嵌在 `.tscn` 预制体中的 `SubResource`，仅扫 `.gdshader` 会漏烤绝大部分特效 | 直接读取 `PackedScene.get_state()` 静态遍历节点属性与子场景，**无需调用 `instantiate()`** 即可提取所有内嵌材质并自动绑定宿主图元拓扑（2D 画布 / 2D 粒子 / 3D 网格 / 3D 粒子）。 |
| **2. 全特性微缩暗箱舞台**<br>(`Full-Feature Micro Sandbox`) | 设为 `visible=false`、`alpha=0` 或移出屏幕会被引擎剔除（Cull）导致不触发 GPU 编译；空场景会漏烤灯光与屏幕纹理变体 | 在底层 `CanvasLayer (-128)` 的视口安全角 `(2, 2)` 构建 `alpha = 0.01` 的微像素舞台，内置 `BackBufferCopy`（触发 `SCREEN_TEXTURE` 变体）、`PointLight2D`（触发 2D 光照变体）及按需创建的 3D 带阴影 `SubViewport`。 |
| **3. 画质感知的 PSO 签名幂等去重**<br>(`Quality-Aware Signature Registry`) | 跨关卡重复预热公共特效浪费加载时间；玩家在设置页修改 MSAA 后管线签名失效 | 签名编码 `Material RID + 图元拓扑 + Viewport MSAA/ScreenSpaceAA`；同一画质下跨场景 $O(1)$ 自动跳过已编译管线，画质变更后自动识别新签名补烤。 |
| **4. 自适应帧率步进器**<br>(`Adaptive Frame Pacer`) | 固定每帧烘烤数量在高端 PC 上偏慢、在低端移动设备上导致 Loading 动画卡顿 | 每次 `await RenderingServer.frame_post_draw` 后测量单帧真实微秒耗时，相对 `frame_budget_ms`（默认 `6.0ms`）闭环动态倍增或折半 `batch_size`。 |

---

## 二、 使用范式

```gdscript
# 1. 扫描特效与着色器目录下的全部可预热资源路径 (.gdshader / .tres / .tscn)
var paths: Array[String] = ShaderWarmer.scan_directory_paths([
	"res://src/assets/shaders",
	"res://src/assets/vfx",
])

# 2. 第一阶段：利用 App.asset 双阶段真并发从磁盘加载资源
var batch_res := await App.asset.preload_batch(paths)
var loaded_resources: Array = batch_res.value.values() if batch_res.is_ok() else []

# 3. 第二阶段：交由 ShaderWarmer 分帧在微缩暗箱中完成 GPU PSO 预编译
var report: ShaderWarmupReport = await ShaderWarmer.warmup_resources_async(
	self,               # 宿主节点 (提供 Viewport 上下文)
	loaded_resources,   # 支持混合传入 Shader / Material / PackedScene (.tscn) / Mesh
	6.0,                # 单帧耗时预算 6.0ms (保障 Loading 界面 60 FPS 丝滑动画)
	func(done: int, total: int) -> void:
		# 实时更新进度条
		pass,
	task_scope.get_token()
)
```
