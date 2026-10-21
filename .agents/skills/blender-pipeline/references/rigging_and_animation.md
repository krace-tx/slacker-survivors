# Skill Wiki · 骨骼绑定、预设顶点组权重与多轨 NLA 动画规范 (Rigging & Animation)

> 📖 **Wiki 定位**：解决程序化 3D 角色绑定中最棘手的“五官眼镜被身体拉扯变形”、“肩肘关节旋转错位脱节”与“多套动作导出 GLB 互相覆盖”三大核心难题。

---

## 1. 模块化分层蒙皮与骨骼刚性插槽法 (Hierarchical Modular Skinning & Bone Sockets)

在 Blender 中对多部件角色执行粗暴的「全全身合并为单一死网格 + 自动权重绑定（`ARMATURE_AUTO`）」会导致灾难性的“眼球脱眶”、“眼镜扭曲”，且破坏场景树层级导致在 Godot 中无法换装或替换手持道具。
**工业级标准做法（结合 [`scene_hierarchy_architecture.md`](file:///Users/krace/Code/GodotProject/slacker-survivors/.agents/skills/blender-pipeline/references/scene_hierarchy_architecture.md)）**：

1. **刚性挂件与手持道具优先走 `SOCKET_*` 骨骼插槽（`parent_type = 'BONE'`，零蒙皮畸变）**：
   - `SOCKET_Head_Glasses`（绑定至 `Head` 骨骼）：下挂 `MSH_<Name>_Glasses`（眼镜框与镜片）；
   - `SOCKET_Chest_Badge`（绑定至 `Tie_Bone` / `Spine` 骨骼）：下挂 `MSH_<Name>_IDBadge`（胸前工牌）；
   - `SOCKET_Hand_R`（绑定至 `Forearm_R` / `Hand_R` 骨骼）：下挂 `MSH_Prop_CoffeeCup`（手中咖啡杯或武器，Godot 运行期可直接替换插槽子节点）。
2. **有机与服饰部件按「换装/材质逻辑域」分为分层子网格（严禁无脑全合并为一个 Mesh）**：
   - 在 `ARM_<Name>` 下建立 `GRP_Char_Anatomy`（包含 `MSH_<Name>_Head`、`MSH_<Name>_Body`、`MSH_<Name>_Hair`）与 `GRP_Char_Outfit`（包含 `MSH_<Name>_Top_Shirt`、`MSH_<Name>_Bottom_Pants`、`MSH_<Name>_Neck_Tie`、`MSH_<Name>_Shoes_LR`）。
   - 在每个逻辑子网格内部合并子几何体前，直接通过脚本精确写入 `vertex_groups`：
     - **100% 刚性锁死子域**：头颅五官与头发赋予 `Head = 1.0`；领带赋予 `Tie_Bone = 1.0`；小腿与皮鞋赋予 `Shin_L/R = 1.0`。
     - **线性平滑过渡子域（躯干/上衣）**：沿高度 $Z$ 在 `Pelvis` 与 `Spine` 之间做线性插值（$w_{\text{spine}} = \text{clamp}((z - z_{\min}) / \Delta z, 0, 1)$，$w_{\text{pelvis}} = 1 - w_{\text{spine}}$），保证弯腰与扭胯自然柔顺。
3. **子网格独立挂载 `Armature` 修改器**：
   - 每个分层子网格（`MSH_*`）保持在各自的 `GRP_*` 分组父节点下，通过 `mod = msh.modifiers.new(name="Armature", type='ARMATURE'); mod.object = arm_obj` 共享同一个骨架，既保留清晰的 4 层场景树，又完美继承精确顶点组！

---

## 2. 垂直静息姿态 (Vertical Rest Pose) + `use_connect` + `roll=0` 铁律

为什么斜向建模的手臂骨骼在旋转时会出现诡异的侧向翻滚或肘部断开？
因为当骨骼在 `EDIT` 模式下倾斜时，其局部坐标系（Local Axes）发生了耦合偏转。

### ✅ 黄金骨骼构建守则
1. **静息态四肢骨统一沿 `-Z` 垂直向下延伸**：
   - `UpperArm_L/R`：从肩关节 `(±x_s, 0, z_shoulder)` 垂直向下到肘关节 `(±x_e, 0, z_elbow)`；
   - `Forearm_L/R`：从肘关节 `(±x_e, 0, z_elbow)` 垂直向下到腕关节 `(±x_w, 0, z_wrist)`。
2. **父子关节强制开启物理连接 (`use_connect = True`)**：
   - `Spine.parent = Pelvis; Spine.use_connect = True`
   - `Head.parent = Spine; Head.use_connect = True`
   - `Forearm.parent = UpperArm; Forearm.use_connect = True`
   - `Shin.parent = Thigh; Shin.use_connect = True`
   - 开启 `use_connect = True` 后，子骨骼的 `head` 被引擎硬性锁死在父骨骼的 `tail` 上，**在物理层面彻底杜绝肘部与膝盖脱节**！
3. **全体骨骼强制归零扭转角 (`eb.roll = 0.0`)**：
   - 当垂直向下的骨骼设置 `roll = 0.0` 时，其局部 `X` 轴严格水平向右（`+X`）：
   - 绕 `X` 轴**负旋转 (`-X`)** ➔ 手臂/大腿向**正前方 (`-Y`)** 抬起；
   - 绕 `X` 轴**正旋转 (`+X`)** ➔ 手臂/大腿向**正后方 (`+Y`)** 摆动。

---

## 3. 外部高模自动骨骼对齐与 Rigify 装配 (Auto-Rigging via BBox Slicing & Rigify)

当对 AI 3D 扩散大模型生成的单体 T-Pose / A-Pose 角色网格进行绑定时，无需手动摆放数十根骨骼。可通过计算网格 Bounding Box（边界框）与高度切片自动定位关节坐标，并驱动自定义骨架或 **Rigify Meta-Rig**：

```python
import bpy
from mathutils import Vector

def estimate_humanoid_landmarks(mesh_obj: bpy.types.Object) -> dict[str, Vector]:
    """基于角色网格 Bounding Box 与解剖学比例切片，自动估算核心关节世界坐标。"""
    bbox = [mesh_obj.matrix_world @ Vector(c) for c in mesh_obj.bound_box]
    min_x, max_x = min(v.x for v in bbox), max(v.x for v in bbox)
    min_z, max_z = min(v.z for v in bbox), max(v.z for v in bbox)
    center_y = 0.5 * (min(v.y for v in bbox) + max(v.y for v in bbox))
    h = max(max_z - min_z, 1e-4)
    half_span_x = 0.5 * (max_x - min_x)

    return {
        "pelvis": Vector((0.0, center_y, min_z + 0.53 * h)),
        "spine": Vector((0.0, center_y, min_z + 0.68 * h)),
        "neck": Vector((0.0, center_y, min_z + 0.82 * h)),
        "head_top": Vector((0.0, center_y, max_z)),
        "shoulder_L": Vector((-0.22 * half_span_x, center_y, min_z + 0.80 * h)),
        "elbow_L": Vector((-0.55 * half_span_x, center_y, min_z + 0.80 * h)),
        "wrist_L": Vector((-0.88 * half_span_x, center_y, min_z + 0.80 * h)),
        "hip_L": Vector((-0.10 * h, center_y, min_z + 0.51 * h)),
        "knee_L": Vector((-0.10 * h, center_y, min_z + 0.28 * h)),
        "ankle_L": Vector((-0.10 * h, center_y, min_z + 0.05 * h)),
    }

def auto_rig_with_rigify(mesh_obj: bpy.types.Object) -> bpy.types.Object:
    """启用 Rigify 插件，生成 Human Meta-Rig 并按角色身高自动缩放对齐后生成全套控制器。"""
    import addon_utils
    addon_utils.enable("rigify", default_set=True)

    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.object.armature_human_metarig_add()
    metarig = bpy.context.view_layer.objects.active
    metarig.name = f"{mesh_obj.name}_MetaRig"

    # 按角色实际高度自动匹配 metarig 比例
    mesh_h = mesh_obj.dimensions.z
    meta_h = max(metarig.dimensions.z, 1e-4)
    scale_f = mesh_h / meta_h
    metarig.scale = (scale_f, scale_f, scale_f)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 生成最终 Rigify 控制器骨架并自动蒙皮
    bpy.ops.pose.rigify_generate()
    rig_obj = bpy.context.view_layer.objects.active
    bpy.ops.object.select_all(action='DESELECT')
    mesh_obj.select_set(True)
    rig_obj.select_set(True)
    bpy.context.view_layer.objects.active = rig_obj
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    return rig_obj
```

---

## 4. 多套动作 NLA 压栈与无冲突预览规范

当需要在一个 `.glb` 文件中导出 `Idle`、`Walk`、`Run`、`Slack` 多套独立动作供 Godot `AnimationPlayer` 调用时：

1. 每制作完一套 `Action`，将其压入独立的 NLA Track：
   ```python
   track = arm_obj.animation_data.nla_tracks.new()
   track.name = action.name
   strip = track.strips.new(action.name, 1, action)
   strip.name = action.name
   ```
2. 压栈完成后，将当前活动动作置空：`arm_obj.animation_data.action = None`。
3. 导出 GLB 时指定 `export_animation_mode='NLA_TRACKS'`。
4. **离线渲染预览图前注意**：由于多条未静音的 NLA 轨道在 Blender 中会从下往上叠加覆盖，在执行 `bpy.ops.render.render()` 拍预览照前，务必将非目标预览轨道设为 `track.mute = True`，仅保留目标动作轨道（如 `Walk`）处于 `mute = False`！
