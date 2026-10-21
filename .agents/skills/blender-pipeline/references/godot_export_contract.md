# Skill Wiki · glTF/GLB 导出契约与 Godot 4 集成规范 (Godot Export Contract)

> 📖 **Wiki 定位**：规范 Blender 工程文件与导出产物的目录隔离、glTF 2.0 导出参数以及在 Godot 4 框架（`BaseScene` + `NodeUtils`）中的标准装载方式。

---

## 1. 源文件与引擎资产目录隔离规范 (`.gdignore` 保护)

在 Godot 4 工程中，若目录下直接存放 `.blend` 文件而开发机未在 Godot EditorSettings 中配置 Blender 路径，Godot 扫描资源时会报错阻塞。因此**必须实行源产分离**：

```text
src/<feature_or_test>/
├── blender/                          # [Blender 源工程目录 - 被 Godot 忽略]
│   ├── .gdignore                     # ⚠️ 必须存在！阻止 Godot 扫描 .blend 与 .py
│   ├── build_<asset>.py              # 参数化可重复生成脚本
│   ├── <asset>.blend                 # Blender 源工程文件
│   └── renders/                      # 离线质检多视角渲染图与 verify_report.json
│       └── <asset>_contact_sheet.png
└── assets/
    └── models/                       # [Godot 运行时资产目录 - 复数命名]
        └── <asset>.glb               # 纯净二进制 glTF 2.0 产物，Godot 免插件原生秒级导入
```

---

## 2. 标准 glTF 2.0 / GLB 导出参数契约

### 角色与带骨骼动画资产导出
```python
bpy.ops.object.select_all(action='DESELECT')
mesh_obj.select_set(True)
arm_obj.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=EXPORT_GLB_PATH,
    export_format='GLB',
    use_selection=True,
    export_apply=False,               # 骨骼蒙皮网格严禁强行 apply modifiers，否则会破坏 Armature 修改器
    export_animations=True,
    export_animation_mode='NLA_TRACKS',
    export_skins=True,
    export_materials='EXPORT',
)
```

### 静态建筑、环境与道具资产导出
```python
bpy.ops.export_scene.gltf(
    filepath=EXPORT_GLB_PATH,
    export_format='GLB',
    use_selection=False,              # 导出前确保已移除或未包含临时摄影棚相机/灯光
    export_apply=True,                # 静态建筑自动应用所有修改器与变换
    export_materials='EXPORT',
)
```
> ⚠️ **关键提醒**：导出静态建筑 `.glb` 必须在添加离线渲染预览用的 `SUN` / `AREA` 灯光与 `CAMERA` **之前**执行，或者使用 `use_selection=True` 仅选中建筑网格导出，防止把预览相机和强光一起打进 `.glb` 污染 Godot 场景光照！

---

## 3. Godot 4 侧挂载与骨骼动画循环激活范式

在 Godot 4 场景脚本（继承 `BaseScene`）中，统一使用框架工具类 `NodeUtils.spawn` 挂载 `.glb` 预制体，并开启骨骼动画循环：

```gdscript
const WORKER_SCENE: PackedScene = preload("res://src/test/office_3d/assets/models/office_worker.glb")

func _spawn_worker(parent: Node3D) -> void:
	var res := NodeUtils.spawn(WORKER_SCENE, parent, "OfficeWorker")
	if res.is_err():
		App.logger.error("Office3D", "挂载 3D 职场人失败: %s" % str(res.error))
		return

	var worker_node: Node = res.value
	var anim_player := worker_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player != null:
		for anim_name in anim_player.get_animation_list():
			var anim := anim_player.get_animation(anim_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
		anim_player.play("Walk", 0.2)
```

---

## 4. 百万面高模到游戏引擎低模的自动化烘焙管线 (High-to-Low Poly Auto-Baking)

**严禁将百万面（1M+ Polygons）的 AI 3D 雕刻高模直接导出 `.glb` 塞进 Godot 4！** 必须在管线收尾阶段通过 `bpy` 脚本自动执行「高低模分离 ➔ 低模减面与展 UV ➔ Cycles 4K 法线/AO 烘焙 ➔ 挂载贴图导出低模」：

```python
import bpy

def bake_high_to_low_and_prepare_export(
    high_obj: bpy.types.Object,
    target_low_faces: int = 20000,
    tex_size: int = 4096,
    cage_extrusion: float = 0.02,
) -> bpy.types.Object:
    """
    将百万面高模 (high_obj) 自动减面生成游戏级低模 (Low_Poly, 1.5w~3w 面)，
    自动执行 Smart UV Project，并调用 Cycles 烘焙 4K 法线贴图 (Normal Map) 与 AO。
    """
    # 1. 复制一份作为 Low_Poly 并通过 QuadriFlow / Decimate 压至目标面数
    low_obj = high_obj.copy()
    low_obj.data = high_obj.data.copy()
    low_obj.name = f"{high_obj.name}_LowPoly"
    bpy.context.collection.objects.link(low_obj)

    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = low_obj
    low_obj.select_set(True)

    cur_faces = len(low_obj.data.polygons)
    if cur_faces > target_low_faces:
        dec = low_obj.modifiers.new(name="Auto_Decimate", type='DECIMATE')
        dec.ratio = max(0.01, min(1.0, target_low_faces / float(cur_faces)))
        bpy.ops.object.modifier_apply(modifier=dec.name)

    # 2. 自动执行 Smart UV Project 展平低模 UV
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.003)
    bpy.ops.object.mode_set(mode='OBJECT')

    # 3. 创建 4K 法线空白图像与低模 PBR 材质节点
    norm_img = bpy.data.images.new(name=f"{low_obj.name}_Normal_4K", width=tex_size, height=tex_size, alpha=False)
    norm_img.colorspace_settings.name = 'Non-Color'

    low_mat = bpy.data.materials.new(name=f"Mat_{low_obj.name}")
    if not low_mat.use_nodes:
        low_mat.use_nodes = True
    nodes = low_mat.node_tree.nodes
    links = low_mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    tex_node = nodes.new("ShaderNodeTexImage")
    tex_node.image = norm_img
    nodes.active = tex_node  # Cycles Bake 的目标图像由当前 active 纹理节点决定

    low_obj.data.materials.clear()
    low_obj.data.materials.append(low_mat)

    # 4. 切换 Cycles 引擎，执行 Selected-to-Active 法线烘焙
    prev_engine = bpy.context.scene.render.engine
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 16
    bpy.context.scene.cycles.bake_type = 'NORMAL'
    bpy.context.scene.render.bake.use_selected_to_active = True
    bpy.context.scene.render.bake.cage_extrusion = cage_extrusion

    bpy.ops.object.select_all(action='DESELECT')
    high_obj.select_set(True)
    low_obj.select_set(True)
    bpy.context.view_layer.objects.active = low_obj
    bpy.ops.object.bake(type='NORMAL')

    # 5. 将烘焙完成的法线贴图挂载到 Principled BSDF Normal 通道
    norm_map_node = nodes.new("ShaderNodeNormalMap")
    links.new(tex_node.outputs["Color"], norm_map_node.inputs["Color"])
    links.new(norm_map_node.outputs["Normal"], bsdf.inputs["Normal"])

    bpy.context.scene.render.engine = prev_engine
    return low_obj
```
