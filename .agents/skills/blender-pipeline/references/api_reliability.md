# Skill Wiki · Blender API 可靠性、上下文安全与坐标系规范 (API Reliability)

> 📖 **Wiki 定位**：本文件汲取 `libevm/agent-skills` 与 Blender 4.x/5.x 生产经验，定义编写 `bpy` / `bmesh` 脚本时的硬性防崩准则与跨引擎坐标系换算契约。

---

## 1. Blender 4.x / 5.x 跨版本 API 兼容性铁律

Blender 4.0 至 5.2+ 对材质节点、渲染引擎枚举和动作系统进行了多项破坏性重构，编写脚本时**必须**遵守以下兼容写法：

| 变更领域 | ❌ 易报错/已废弃写法 | ✅ 工业级跨版本兼容写法 |
| :--- | :--- | :--- |
| **材质节点启用** | `mat.use_nodes = True`（Blender 5.2 抛 `DeprecationWarning`，6.0 移除，新建材质默认已含 NodeTree） | `if not mat.use_nodes: mat.use_nodes = True` 或直接访问 `mat.node_tree.nodes.get("Principled BSDF")` |
| **Principled BSDF 高光输入** | `bsdf.inputs["Specular"]`（Blender 4.0+ 改名） | `if "Specular IOR Level" in bsdf.inputs: ... elif "Specular" in bsdf.inputs: ...` |
| **Principled BSDF 自发光输入** | `bsdf.inputs["Emission"]`（Blender 4.0+ 拆分为颜色与强度） | 同时兼容 `"Emission Color"` 与 `"Emission"`，并显式设置 `"Emission Strength"` |
| **透明材质混合模式** | `mat.blend_method = 'BLEND'`（Blender 4.2+ EEVEE Next 改为 `surface_render_method`） | 同时判断 `hasattr(mat, "blend_method")` 与 `hasattr(mat, "surface_render_method")`，后者设为 `'BLENDED'` |
| **EEVEE 渲染器名称** | 硬编码 `'BLENDER_EEVEE'` 或 `'BLENDER_EEVEE_NEXT'` | 动态检测枚举：`enum_items = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]` |
| **锥台与圆柱参数** | 在 `primitive_cylinder_add` 中传 `radius1` / `radius2`（抛 `TypeError`） | 圆柱等径用 `primitive_cylinder_add(radius=...)`；上下异径锥台必须用 `primitive_cone_add(radius1=..., radius2=...)` |

---

## 2. 幂等清理与零数据污染原则 (Idempotent Scene Reset)

任何自动化构建脚本必须在入口处执行彻底的数据块清理，严禁残留孤立 Mesh/Material 导致对象名自动变成 `Cube.001`、`Mat.001`，进而导致按名称绑定权重的逻辑失效：

```python
def clear_scene() -> None:
    """幂等清空场景中的所有对象与底层数据块，确保每次运行 100% 确定性复现。"""
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.actions,
        bpy.data.lights,
        bpy.data.cameras,
    ):
        for block in list(collection):
            collection.remove(block)
```

---

## 3. 上下文 (Context) 与模式切换安全守则

1. **切换模式前必先确保 `active_object` 有效且已选中**：
   ```python
   bpy.ops.object.select_all(action='DESELECT')
   bpy.context.view_layer.objects.active = target_obj
   target_obj.select_set(True)
   bpy.ops.object.mode_set(mode='EDIT') # 或 'POSE' / 'OBJECT'
   ```
2. **EditBones 生命周期禁区**：
   - `arm_data.edit_bones` **仅在 `EDIT` 模式下存在**！退出 `EDIT` 模式后立即悬空失效，严禁将 `EditBone` 引用保存到 `OBJECT` 或 `POSE` 模式中读取。
   - 在 `POSE` 模式下设置关键帧必须操作 `arm_obj.pose.bones[name]`，且旋转前显式指定 `pose_bone.rotation_mode = 'XYZ'`。
3. **黄金法则：强制优先数据 API (`bpy.data` / `bmesh`)，严禁滥用算子 (`bpy.ops`)**：
   - `bpy.ops.*` 极度依赖当前鼠标所在的 UI 窗口上下文（Context），在后台 Headless 或 Blender MCP 异步脚本中极易报 `RuntimeError: Operator bpy.ops.xxx.poll() failed, context is incorrect`，且每次调用都会触发全场景 `depsgraph` 刷新。
   - **硬性规定**：所有网格创建、修改器挂载、材质节点连接、对象变换与层级绑定必须直接使用 `bpy.data` 和 `bmesh` 底层数据接口，除非调用无 Data API 替代的专用算子（如 `quadriflow_remesh`、`uv.smart_project`、`object.bake`、`pose.rigify_generate`）：

| 操作场景 | ❌ 脆弱的 `bpy.ops` 写法（依赖 UI Context） | ✅ 工业级 `bpy.data` / `bmesh` 写法（零上下文依赖） |
| :--- | :--- | :--- |
| **新建网格对象** | `bpy.ops.mesh.primitive_cube_add()` | `mesh = bpy.data.meshes.new(name); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(mesh)` |
| **清理重叠/游离点** | `bpy.ops.mesh.remove_doubles()` | `bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)` |
| **添加修改器** | `bpy.ops.object.modifier_add(type='BEVEL')` | `mod = obj.modifiers.new(name="Bevel", type='BEVEL')` |
| **连接材质节点** | 依赖 UI Shader Editor 上下文 | `mat.node_tree.nodes.new(...)` + `mat.node_tree.links.new(out_sock, in_sock)` |
| **复制对象与网格** | `bpy.ops.object.duplicate()` | `new_obj = obj.copy(); new_obj.data = obj.data.copy(); col.objects.link(new_obj)` |
| **删除对象** | `bpy.ops.object.delete()` | `bpy.data.objects.remove(obj, do_unlink=True)` |

---

## 4. Blender ➔ glTF 2.0 ➔ Godot 4 跨引擎空间坐标系契约

Blender 采用右手系 **Z-Up**，而 glTF 2.0 与 Godot 4 采用右手系 **Y-Up**。在 Blender 的 glTF 导出器开启默认 `+Y Up` 转换时，坐标轴严格满足以下映射：

| 空间方向 | Blender 坐标系 (建模期) | glTF / Godot 4 坐标系 (运行期) | 核心开发准则 |
| :--- | :--- | :--- | :--- |
| **上方 (Up)** | **`+Z`** | **`+Y`** | 角色脚底与建筑首层地面必须严格对齐 `Z = 0.0` |
| **右方 (Right)** | **`+X`** | **`+X`** | 左右对称部件以 `X = 0` 为镜像平面（左 `-X`，右 `+X`） |
| **前方 (Forward)** | **`-Y`** | **`+Z`** | 角色正面五官、胸前领带与主观察面统一朝向 **`-Y`** |
| **后方 (Back)** | **`+Y`** | **`-Z`** | 角色后背、建筑背立面朝向 **`+Y`** |

### 💡 Godot 侧角色转向公式
由于角色在 Blender 中面向 `-Y` 导出后，在 Godot 中局部正前方为 `+Z`，因此在 Godot 3D 脚本中驱动角色朝向移动方向 `move_dir` 时，目标偏航角（Yaw）公式固定为：
```gdscript
var target_yaw := atan2(move_dir.x, move_dir.z)
visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, delta * 12.0)
```
