class_name ShaderWarmer
extends RefCounted

## 工业级 Shader 与 GPU 管线状态对象（PSO）分帧预编译基建（位于 src/framework/infra/shader/）。[br]
##
## [b]为什么需要真绘制预热（第一性原理）：[/b][br]
## 在 Godot 4（Vulkan / D3D12 / Metal / GLES3）中，仅用 `ResourceLoader` 将 `.gdshader` 或 `.tres` 加载到内存，
## 只完成了 CPU 侧字节码读取；真正的卡顿（PSO Compilation Stutter）发生在**材质首次绑定具体几何图元并在当前视口配置（MSAA/光照）下提交 GPU Draw Call 的那一帧**。[br]
##
## [b]四大核心防卡顿机制：[/b][br]
## 1. [b]零实例化预制体静态穿透提取（SceneState Deep Extraction）[/b]：支持直接传入特效/角色 `.tscn`（[PackedScene]），
##    通过 [method PackedScene.get_state] 静态遍历节点属性树，剥离所有内嵌 `SubResource` 材质及其宿主图元拓扑（2D 画布 / 2D 骨骼 / 2D 粒子 / 3D 网格 / 3D 粒子），
##    **无需调用 `instantiate()` 触发业务脚本或分配节点内存**即可覆盖 100% 实战特效材质；[br]
## 2. [b]全特性防剔除微缩暗箱（Full-Feature Micro Sandbox）[/b]：摒弃会被引擎剔除器（Frustum / Alpha Culler）直接跳过的 `visible = false` 或 `alpha = 0.0` 假预热，
##    在视口底层 `CanvasLayer (-128)` 的安全角 `(2, 2)` 构建 `alpha = 0.01` 的微像素舞台，
##    内置 [BackBufferCopy]（激发 `hint_screen_texture` 屏幕采样变体）、[PointLight2D]（激发 2D 光照变体）及按需惰性创建的 3D 带阴影 [SubViewport]；[br]
## 3. [b]画质感知的 PSO 签名幂等去重表（Quality-Aware Signature Registry）[/b]：将 `Material RID + 图元载体类型 + 视口 MSAA/ScreenSpaceAA 状态`
##    编码为唯一签名，跨关卡 $O(1)$ 零重复烘烤；当玩家在设置页修改 MSAA 等管线级画质参数时自动识别新签名补烤；[br]
## 4. [b]自适应帧耗时步进器（Adaptive Frame Pacer）[/b]：基于 [signal RenderingServer.frame_post_draw] 实时闭环测量单帧真实微秒耗时，
##    根据目标帧预算（默认 `6.0ms`）动态倍增或折半每帧烘烤批次（`batch_size`），确保闪屏页与 Loading 动画维持 60 FPS 丝滑表现。


#region 枚举与常量

## 材质挂载的图元载体拓扑类型（决定 GPU 顶点输入布局 Vertex Format 与着色器编译域）
enum CarrierArchetype {
	CANVAS_2D = 0,    ## 2D 标准画布图元 (Sprite2D / ColorRect / Line2D / Polygon2D)
	SKINNED_2D = 1,   ## 2D 骨骼蒙皮图元 (Polygon2D + Skeleton2D)
	PARTICLES_2D = 2, ## 2D GPU 粒子系统 (GPUParticles2D，触发粒子计算着色器 + 2D 绘制管线)
	MESH_3D = 3,      ## 3D 静态网格图元 (MeshInstance3D + QuadMesh，触发 Spatial Color/Shadow Pass)
	SKINNED_3D = 4,   ## 3D 骨骼蒙皮网格 (MeshInstance3D + Skeleton3D)
	PARTICLES_3D = 5, ## 3D GPU 粒子系统 (GPUParticles3D，触发 3D 粒子计算 + DrawPass 网格管线)
}

## 默认单帧最大烘烤耗时预算（毫秒）：控制在 6.0ms 内以确保 60 FPS (16.6ms) 下主线程与 UI 动画仍有充裕余量
const DEFAULT_FRAME_BUDGET_MS: float = 6.0

## 自适应步进器初始每帧烘烤数量（从保守值起步，根据 GPU 实际耗时动态爬升）
const _INITIAL_BATCH_SIZE: int = 2

## 单帧最大允许并发烘烤数量上限（防止简单材质无限倍增导致单帧节点挂载过多）
const _MAX_BATCH_SIZE: int = 16

## 嵌套 PackedScene 子场景静态穿透递归的最大深度保护（防止循环嵌套场景死锁）
const _MAX_SCENE_RECURSION_DEPTH: int = 6

## 微缩暗箱 CanvasLayer 所在层级（置于最底层 -128，确保被正常游戏背景或闪屏 UI 完全遮挡）
const _SANDBOX_LAYER: int = -128

## 微缩暗箱不透明度（0.01 既保证肉眼 100% 不可见，又大于引擎 Alpha 剔除阈值 0.0，强制触发 GPU Draw Call）
const _SANDBOX_ALPHA: float = 0.01

## 全局已编译 PSO 签名注册表：String (signature_key) -> int (baked_timestamp_ms)
static var _warmed_signatures: Dictionary = {}

## 2x2 极简共享白图（供 2D Sprite / PointLight2D / GPUParticles2D 采样，防止因 texture == null 被渲染器跳过）
static var _shared_tiny_texture: ImageTexture = null

#endregion


#region 公开 API (Public Warmup Entrypoints)

## 对给定资源集合（支持混合传入 [Shader]、[Material]、[PackedScene]、[Mesh]）执行分帧 GPU 预编译。[br]
##
## [b]执行流程：[/b][br]
## 1. 检查是否为 Headless / Dummy 渲染环境（若是则立即 O(1) 短路返回）；[br]
## 2. 静态遍历 `resources`（若遇到 `.tscn` 则通过 [SceneState] 无实例化提取内嵌 `SubResource` 材质与宿主图元类型）；[br]
## 3. 结合当前 `Viewport` 的 `msaa_2d / msaa_3d / screen_space_aa` 计算 PSO 签名，过滤已在当前画质下烘烤过的项；[br]
## 4. 在视口底层挂载防剔除微缩暗箱，按 `frame_budget_ms` 帧耗时预算分批挂载图元并等待 `RenderingServer.frame_post_draw`；[br]
## 5. 烘烤完成或中途取消时，立即 `queue_free()` 销毁整个暗箱容器，保证零节点残留。[br]
##
## - [param host]：挂载微缩暗箱的宿主节点（必须已在场景树内，通常传入当前 `BaseScene`、`self` 或 `App`）；[br]
## - [param resources]：待预热的资源数组（支持 `Array[Resource]` 或混合 `Array`）；[br]
## - [param frame_budget_ms]：单帧最大烘烤耗时预算（毫秒，默认 [constant DEFAULT_FRAME_BUDGET_MS] = `6.0ms`）；[br]
## - [param on_progress]：可选进度回调 `func(completed_count: int, total_count: int) -> void`；[br]
## - [param token]：可选取消令牌（建议传入 `task_scope.get_token()`，界面退出时自动中止预热）。
static func warmup_resources_async(
	host: Node,
	resources: Array,
	frame_budget_ms: float = DEFAULT_FRAME_BUDGET_MS,
	on_progress: Callable = Callable(),
	token: CancellationToken = null
) -> ShaderWarmupReport:
	var t0: int = Time.get_ticks_msec()
	var report := ShaderWarmupReport.new()
	report.total_inputs = resources.size()

	# Headless / CI 单测环境零开销短路保护
	if _is_headless_or_dummy():
		report.was_headless_skipped = true
		return report

	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return report

	if token != null and token.is_cancelled():
		report.was_cancelled = true
		return report

	var viewport: Viewport = host.get_viewport()
	if viewport == null:
		return report

	# 阶段 1：静态穿透提取所有 (Material + CarrierArchetype + PassMesh/SubMaterial) 条目
	var raw_items: Array[Dictionary] = []
	var visited_paths: Dictionary = {}
	for res: Variant in resources:
		if res is Resource:
			_extract_from_resource(res as Resource, CarrierArchetype.CANVAS_2D, raw_items, visited_paths, 0)

	report.extracted_count = raw_items.size()
	if raw_items.is_empty():
		report.total_cost_ms = maxi(0, Time.get_ticks_msec() - t0)
		return report

	# 阶段 2：结合当前 Viewport 画质状态（MSAA / ScreenSpaceAA）计算 PSO 签名并过滤已编译项
	var vp_hash: int = _compute_viewport_state_hash(viewport)
	var pending_items: Array[Dictionary] = []
	var seen_in_batch: Dictionary = {}

	for item: Dictionary in raw_items:
		var sig: String = _compute_item_signature(item, vp_hash)
		if sig.is_empty():
			continue
		if _warmed_signatures.has(sig) or seen_in_batch.has(sig):
			report.skipped_cached += 1
			continue
		seen_in_batch[sig] = true
		item["signature"] = sig
		pending_items.append(item)

	var total_work: int = pending_items.size() + report.skipped_cached
	if pending_items.is_empty():
		if on_progress.is_valid():
			on_progress.call(total_work, total_work)
		report.total_cost_ms = maxi(0, Time.get_ticks_msec() - t0)
		return report

	# 阶段 3：构建防剔除全特性微缩暗箱舞台（仅当存在 3D 材质时才创建 3D SubViewport）
	var has_3d: bool = _contains_3d_archetype(pending_items)
	var sandbox_root: CanvasLayer = _create_sandbox(viewport, has_3d)
	var stage_2d: Node2D = sandbox_root.get_node("Stage2D") as Node2D
	var stage_3d: Node3D = sandbox_root.get_node_or_null("SubViewportContainer/SubViewport/Stage3D") as Node3D

	# 阶段 4：自适应帧耗时切片烘烤循环（等待 RenderingServer.frame_post_draw 确保 GPU 真正完成绘制）
	var budget: float = maxf(1.0, frame_budget_ms)
	var batch_size: int = _INITIAL_BATCH_SIZE
	var cursor: int = 0

	while cursor < pending_items.size():
		if token != null and token.is_cancelled():
			report.was_cancelled = true
			break
		if not is_instance_valid(host) or not host.is_inside_tree():
			report.was_cancelled = true
			break

		var end_idx: int = mini(cursor + batch_size, pending_items.size())
		var mounted_nodes: Array[Node] = []

		for i in range(cursor, end_idx):
			var entry: Dictionary = pending_items[i]
			var carrier: Node = _mount_carrier_node(entry, stage_2d, stage_3d)
			if carrier != null:
				mounted_nodes.append(carrier)

		var frame_start_usec: int = Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var frame_elapsed_ms: float = float(Time.get_ticks_usec() - frame_start_usec) / 1000.0

		# 记录已完成编译的 PSO 签名并立即释放本批次临时图元载体节点
		for i in range(cursor, end_idx):
			var sig_str: String = pending_items[i].get("signature", "")
			if not sig_str.is_empty():
				_warmed_signatures[sig_str] = Time.get_ticks_msec()
			report.newly_baked += 1

		for node: Node in mounted_nodes:
			if is_instance_valid(node):
				node.queue_free()

		report.frames_used += 1
		cursor = end_idx

		if on_progress.is_valid():
			on_progress.call(report.skipped_cached + report.newly_baked, total_work)

		# 闭环反馈控制：若本帧 GPU 耗时充裕（< 50% 预算）则倍增批次；若超标（> 125% 预算）则折半降速
		if frame_elapsed_ms < budget * 0.5:
			batch_size = mini(batch_size * 2, _MAX_BATCH_SIZE)
		elif frame_elapsed_ms > budget * 1.25:
			batch_size = maxi(1, batch_size >> 1)

	# 阶段 5：原子销毁暗箱容器，确保场景树 100% 零残留
	if is_instance_valid(sandbox_root):
		sandbox_root.queue_free()

	report.total_cost_ms = maxi(0, Time.get_ticks_msec() - t0)
	return report


## 递归扫描指定目录列表下所有可预热的资源路径（自动兼容导出后的 `.remap` / `.import` 后缀还原）。[br]
## 支持识别的扩展名：`gdshader`、`tres`、`res`、`tscn`。
static func scan_directory_paths(directories: PackedStringArray) -> Array[String]:
	var results: Array[String] = []
	var seen: Dictionary = {}
	for dir_path: String in directories:
		if dir_path.is_empty():
			continue
		_scan_dir_recursive(dir_path, results, seen)
	return results


## 获取当前运行期已预热并缓存的唯一 PSO 签名总数。
static func get_warmed_signature_count() -> int:
	return _warmed_signatures.size()


## 清空已预热 PSO 签名缓存（供单元测试或强制全量重编译使用）。
static func clear_signature_cache() -> void:
	_warmed_signatures.clear()

#endregion


#region 核心机制 1：SceneState 零实例化穿透提取器 (Static Extractor)

## 从任意 Resource（Shader / Material / Mesh / PackedScene）递归提取待烘烤材质条目。[br]
## 当遇到 [PackedScene] 时，直接读取其 [SceneState] 属性表而非调用 `instantiate()`，零节点实例化开销。
static func _extract_from_resource(
	res: Resource,
	default_archetype: int,
	out_items: Array[Dictionary],
	visited_paths: Dictionary,
	depth: int
) -> void:
	if res == null or depth > _MAX_SCENE_RECURSION_DEPTH:
		return

	# 防止嵌套子场景循环引用导致无限递归
	var res_path: String = res.resource_path
	if not res_path.is_empty() and res is PackedScene:
		if visited_paths.has(res_path):
			return
		visited_paths[res_path] = true

	# 1. 裸 Shader -> 自动包装为临时 ShaderMaterial 并按 Shader Mode 归类图元载体
	if res is Shader:
		var shader := res as Shader
		var sm := ShaderMaterial.new()
		sm.shader = shader
		var arch: int = _infer_archetype_from_shader(shader, default_archetype)
		out_items.append({"material": sm, "archetype": arch, "draw_pass_mat": null})
		return

	# 2. Material 子类（ShaderMaterial / CanvasItemMaterial / ParticleProcessMaterial / BaseMaterial3D）
	if res is Material:
		var mat := res as Material
		var arch: int = _infer_archetype_from_material(mat, default_archetype)
		out_items.append({"material": mat, "archetype": arch, "draw_pass_mat": null})
		# 若材质链配置了多通道叠加 next_pass（如描边或流光 Pass），递归纳入预热队列
		if mat.next_pass != null:
			_extract_from_resource(mat.next_pass, arch, out_items, visited_paths, depth + 1)
		return

	# 3. Mesh 子类 -> 遍历提取各个 Surface 上绑定的 3D Material
	if res is Mesh:
		var mesh := res as Mesh
		var surface_count: int = mesh.get_surface_count()
		for s_idx in range(surface_count):
			var surf_mat: Material = mesh.surface_get_material(s_idx)
			if surf_mat != null:
				_extract_from_resource(surf_mat, CarrierArchetype.MESH_3D, out_items, visited_paths, depth + 1)
		return

	# 4. PackedScene (.tscn) -> 通过 SceneState 零实例化静态遍历所有节点属性与嵌套子场景
	if res is PackedScene:
		var state: SceneState = (res as PackedScene).get_state()
		if state == null:
			return
		var node_count: int = state.get_node_count()
		for n_idx in range(node_count):
			var node_type: StringName = state.get_node_type(n_idx)
			var node_arch: int = _infer_archetype_from_node_type(node_type)

			# 若该节点本身是一个嵌套子场景实例（Instance Placeholder），递归穿透提取
			var sub_scene: PackedScene = state.get_node_instance(n_idx)
			if sub_scene != null:
				_extract_from_resource(sub_scene, node_arch, out_items, visited_paths, depth + 1)

			var proc_mat: Material = null
			var draw_pass_mat: Material = null
			var prop_count: int = state.get_node_property_count(n_idx)

			for p_idx in range(prop_count):
				var prop_name: StringName = state.get_node_property_name(n_idx, p_idx)
				var prop_val: Variant = state.get_node_property_value(n_idx, p_idx)
				if not (prop_val is Resource):
					continue

				if prop_name == &"process_material" and prop_val is Material:
					proc_mat = prop_val as Material
				elif (prop_name == &"draw_pass_1" or prop_name == &"mesh") and prop_val is Mesh:
					var m := prop_val as Mesh
					if m.get_surface_count() > 0 and m.surface_get_material(0) != null:
						draw_pass_mat = m.surface_get_material(0)
					_extract_from_resource(m, node_arch, out_items, visited_paths, depth + 1)
				elif prop_val is Material or prop_val is Shader or prop_val is PackedScene:
					_extract_from_resource(prop_val as Resource, node_arch, out_items, visited_paths, depth + 1)

			# 将粒子的 process_material 与其配对的绘制网格材质合并为一条粒子预热项
			if proc_mat != null:
				out_items.append({
					"material": proc_mat,
					"archetype": node_arch,
					"draw_pass_mat": draw_pass_mat,
				})


## 根据 [Shader.get_mode] 推导默认图元载体类型。
static func _infer_archetype_from_shader(shader: Shader, fallback: int) -> int:
	if shader == null:
		return fallback
	match shader.get_mode():
		Shader.MODE_CANVAS_ITEM:
			return CarrierArchetype.CANVAS_2D
		Shader.MODE_PARTICLES:
			return CarrierArchetype.PARTICLES_2D
		Shader.MODE_SPATIAL:
			return CarrierArchetype.MESH_3D
		_:
			return fallback


## 根据 [Material] 具体子类与宿主节点上下文推导图元载体类型。
static func _infer_archetype_from_material(mat: Material, fallback: int) -> int:
	if mat is ParticleProcessMaterial:
		return CarrierArchetype.PARTICLES_3D if fallback == CarrierArchetype.PARTICLES_3D else CarrierArchetype.PARTICLES_2D
	if mat is BaseMaterial3D:
		return CarrierArchetype.SKINNED_3D if fallback == CarrierArchetype.SKINNED_3D else CarrierArchetype.MESH_3D
	if mat is CanvasItemMaterial:
		return CarrierArchetype.SKINNED_2D if fallback == CarrierArchetype.SKINNED_2D else CarrierArchetype.CANVAS_2D
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sm.shader != null:
			var mode := sm.shader.get_mode()
			if mode == Shader.MODE_PARTICLES:
				return CarrierArchetype.PARTICLES_3D if fallback == CarrierArchetype.PARTICLES_3D else CarrierArchetype.PARTICLES_2D
			if mode == Shader.MODE_SPATIAL:
				return CarrierArchetype.SKINNED_3D if fallback == CarrierArchetype.SKINNED_3D else CarrierArchetype.MESH_3D
			return CarrierArchetype.SKINNED_2D if fallback == CarrierArchetype.SKINNED_2D else CarrierArchetype.CANVAS_2D
	return fallback


## 根据 `.tscn` 节点的引擎类名推导其对应的渲染图元载体类型。
static func _infer_archetype_from_node_type(node_type: StringName) -> int:
	match node_type:
		&"GPUParticles2D":
			return CarrierArchetype.PARTICLES_2D
		&"GPUParticles3D":
			return CarrierArchetype.PARTICLES_3D
		&"MeshInstance3D", &"CSGMesh3D", &"CSGBox3D", &"CSGSphere3D", &"MultiMeshInstance3D":
			return CarrierArchetype.MESH_3D
		&"SoftBody3D":
			return CarrierArchetype.SKINNED_3D
		_:
			if ClassDB.class_exists(node_type) and ClassDB.is_parent_class(node_type, &"Node3D"):
				return CarrierArchetype.MESH_3D
			return CarrierArchetype.CANVAS_2D

#endregion


#region 核心机制 2：全特性防剔除微缩暗箱舞台 (Full-Feature Micro Sandbox)

## 构建并挂载微缩暗箱舞台（确保位于视口可见框内且 alpha=0.01 不被渲染器 Culling 剔除）。
static func _create_sandbox(viewport: Viewport, include_3d: bool) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "_ShaderWarmupSandbox"
	layer.layer = _SANDBOX_LAYER

	# 1. 2D 暗箱通道：位于视口左上角 (2, 2)，内置 BackBufferCopy（激发 SCREEN_TEXTURE）与 PointLight2D（激发 2D 光照 Pass）
	var stage_2d := Node2D.new()
	stage_2d.name = "Stage2D"
	stage_2d.position = Vector2(2.0, 2.0)
	stage_2d.modulate = Color(1.0, 1.0, 1.0, _SANDBOX_ALPHA)
	layer.add_child(stage_2d)

	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_RECT
	bbc.rect = Rect2(0.0, 0.0, 4.0, 4.0)
	stage_2d.add_child(bbc)

	var light_2d := PointLight2D.new()
	light_2d.energy = 0.01
	light_2d.texture = _get_shared_tiny_texture()
	stage_2d.add_child(light_2d)

	# 2. 3D 暗箱通道：按需惰性创建，同步主视口 MSAA 与 ScreenSpaceAA，内置带阴影平行光与点光源以同时编译 Color + Shadow Pass
	if include_3d:
		var container := SubViewportContainer.new()
		container.name = "SubViewportContainer"
		container.position = Vector2(2.0, 2.0)
		container.size = Vector2(4.0, 4.0)
		container.modulate = Color(1.0, 1.0, 1.0, _SANDBOX_ALPHA)
		layer.add_child(container)

		var sub_vp := SubViewport.new()
		sub_vp.name = "SubViewport"
		sub_vp.size = Vector2i(4, 4)
		sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sub_vp.msaa_3d = viewport.msaa_3d
		sub_vp.screen_space_aa = viewport.screen_space_aa
		container.add_child(sub_vp)

		var stage_3d := Node3D.new()
		stage_3d.name = "Stage3D"
		sub_vp.add_child(stage_3d)

		var cam_3d := Camera3D.new()
		cam_3d.position = Vector3(0.0, 0.0, 2.0)
		stage_3d.add_child(cam_3d)

		var dir_light := DirectionalLight3D.new()
		dir_light.light_energy = 0.05
		dir_light.shadow_enabled = true
		stage_3d.add_child(dir_light)

		var omni_light := OmniLight3D.new()
		omni_light.light_energy = 0.05
		omni_light.omni_range = 5.0
		stage_3d.add_child(omni_light)

	viewport.add_child(layer)
	return layer


## 根据条目图元拓扑类型（`CarrierArchetype`）在暗箱内实例化匹配的最小渲染载体节点。
static func _mount_carrier_node(entry: Dictionary, stage_2d: Node2D, stage_3d: Node3D) -> Node:
	var mat: Material = entry.get("material") as Material
	if mat == null:
		return null
	var arch: int = entry.get("archetype", CarrierArchetype.CANVAS_2D)
	var draw_pass_mat: Material = entry.get("draw_pass_mat") as Material

	match arch:
		CarrierArchetype.PARTICLES_2D:
			var p2d := GPUParticles2D.new()
			p2d.amount = 1
			p2d.lifetime = 0.05
			p2d.one_shot = true
			p2d.emitting = true
			p2d.texture = _get_shared_tiny_texture()
			if mat is ParticleProcessMaterial or (mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and (mat as ShaderMaterial).shader.get_mode() == Shader.MODE_PARTICLES):
				p2d.process_material = mat
				if draw_pass_mat != null:
					p2d.material = draw_pass_mat
			else:
				var default_proc := ParticleProcessMaterial.new()
				p2d.process_material = default_proc
				p2d.material = mat
			stage_2d.add_child(p2d)
			return p2d

		CarrierArchetype.PARTICLES_3D:
			if stage_3d == null:
				return null
			var p3d := GPUParticles3D.new()
			p3d.amount = 1
			p3d.lifetime = 0.05
			p3d.one_shot = true
			p3d.emitting = true
			var quad := QuadMesh.new()
			quad.size = Vector2(0.1, 0.1)
			if draw_pass_mat != null:
				quad.material = draw_pass_mat
			p3d.draw_pass_1 = quad
			if mat is ParticleProcessMaterial or (mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and (mat as ShaderMaterial).shader.get_mode() == Shader.MODE_PARTICLES):
				p3d.process_material = mat
			else:
				p3d.process_material = ParticleProcessMaterial.new()
				quad.material = mat
			stage_3d.add_child(p3d)
			return p3d

		CarrierArchetype.MESH_3D, CarrierArchetype.SKINNED_3D:
			if stage_3d == null:
				return null
			var mi := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.2, 0.2)
			mi.mesh = quad
			mi.material_override = mat
			stage_3d.add_child(mi)
			return mi

		_:
			var spr := Sprite2D.new()
			spr.texture = _get_shared_tiny_texture()
			spr.centered = false
			spr.scale = Vector2(0.5, 0.5)
			spr.material = mat
			stage_2d.add_child(spr)
			return spr

#endregion


#region 核心机制 3：管线签名计算与目录扫描辅助 (Signature & Helpers)

## 计算当前视口与 PSO 强相关的渲染管线配置哈希（当玩家切换 MSAA 或后处理抗锯齿时哈希自动变化）。
static func _compute_viewport_state_hash(viewport: Viewport) -> int:
	if viewport == null:
		return 0
	return hash([int(viewport.msaa_2d), int(viewport.msaa_3d), int(viewport.screen_space_aa)])


## 生成单条预热任务的全局唯一 PSO 签名：`<material_rid>:<archetype>:<draw_pass_rid>:<viewport_hash>`。
static func _compute_item_signature(item: Dictionary, vp_hash: int) -> String:
	var mat: Material = item.get("material") as Material
	if mat == null:
		return ""
	var mat_id: int = mat.get_rid().get_id()
	if mat_id == 0:
		mat_id = mat.get_instance_id()
	var arch: int = item.get("archetype", CarrierArchetype.CANVAS_2D)
	var pass_mat: Material = item.get("draw_pass_mat") as Material
	var pass_id: int = pass_mat.get_rid().get_id() if pass_mat != null else 0
	return "%d:%d:%d:%d" % [mat_id, arch, pass_id, vp_hash]


## 检测待烘烤队列中是否包含任何 3D 图元（决定是否需要构建 3D SubViewport 暗箱）。
static func _contains_3d_archetype(items: Array[Dictionary]) -> bool:
	for item: Dictionary in items:
		var arch: int = item.get("archetype", CarrierArchetype.CANVAS_2D)
		if arch == CarrierArchetype.MESH_3D or arch == CarrierArchetype.SKINNED_3D or arch == CarrierArchetype.PARTICLES_3D:
			return true
	return false


## 惰性构建 2x2 纯白微纹理（全局复用同一份 ImageTexture 实例）。
static func _get_shared_tiny_texture() -> ImageTexture:
	if _shared_tiny_texture == null:
		var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_shared_tiny_texture = ImageTexture.create_from_image(img)
	return _shared_tiny_texture


## 判定当前是否运行于无头服务器（Headless）或 Dummy 空渲染器环境。
static func _is_headless_or_dummy() -> bool:
	var ds_name: String = DisplayServer.get_name().to_lower()
	if ds_name == "headless":
		return true
	var render_method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")).to_lower()
	return render_method == "dummy"


## 递归扫描目录并还原导出包内的 `.remap` / `.import` 原始资源路径。
static func _scan_dir_recursive(dir_path: String, out_paths: Array[String], seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				_scan_dir_recursive(full_path, out_paths, seen)
			else:
				var clean_path: String = full_path
				if clean_path.ends_with(".remap") or clean_path.ends_with(".import"):
					clean_path = clean_path.get_basename()
				var ext: String = clean_path.get_extension().to_lower()
				if ext in ["gdshader", "tres", "res", "tscn"] and not seen.has(clean_path):
					seen[clean_path] = true
					out_paths.append(clean_path)
		entry = dir.get_next()
	dir.list_dir_end()

#endregion
