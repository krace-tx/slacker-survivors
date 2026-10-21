# Skill Wiki · PBR 材质、自发光屏幕与多视角摄影棚布光规范 (Materials & Lighting)

> 📖 **Wiki 定位**：规范 Blender 程序化 PBR 材质工厂、半透明建筑玻璃、自发光显示器/窗带，以及自动化质检渲染时的多视角相机与灯光布置。

---

## 1. 工业级跨版本 PBR 材质工厂函数

所有脚本统一使用如下兼容 Blender 4.x / 5.x 的材质构造函数，支持基础色、粗糙度、金属度、自发光（显示器/霓虹灯带）与 Alpha 透明度（落地玻璃/隔断）：

```python
def create_pbr_mat(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float = 0.35,
    metallic: float = 0.0,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
):
    """创建兼容 Blender 4/5 且可无缝导出 glTF 2.0 的标准 PBR 材质。"""
    mat = bpy.data.materials.new(name=name)
    if not mat.use_nodes:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        if emission is not None:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = emission
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = emission
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 0.999:
        if hasattr(mat, "blend_method"):
            mat.blend_method = 'BLEND'
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = 'BLENDED'
    return mat
```

---

## 2. 游戏资产材质配色与质感调优表

| 材质类别 | Roughness (粗糙度) | Metallic (金属度) | Emission Strength | 视觉质感效果 |
| :--- | :--- | :--- | :--- | :--- |
| **角色皮肤 / 腮红** | `0.32 ~ 0.38` | `0.0` | `0.0` | 柔和哑光潮玩手办肤质，不油腻 |
| **眼白 / 瞳孔** | `0.04 ~ 0.08` | `0.0` | `0.0` | 清澈高光水润感 |
| **眼神高光点 (Highlight)** | `0.0` | `0.0` | `0.8 ~ 1.0` | 不受背光阴影影响，永远保持眼神灵动 |
| **亮面皮鞋 / 黑框眼镜** | `0.10 ~ 0.16` | `0.25 ~ 0.35` | `0.0` | 精致锐利边缘高光 |
| **皮带金扣 / 电梯不锈钢** | `0.16 ~ 0.22` | `0.85 ~ 0.90` | `0.0` | 真实金属反射 |
| **全景落地玻璃幕墙** | `0.05 ~ 0.08` | `0.10` | `0.0` (`alpha=0.16`) | 室内看外景通透，室外看有高光反射 |
| **电脑屏幕 / 摩天楼发光窗带** | `0.12 ~ 0.20` | `0.0` | `1.6 ~ 2.8` | 配合 Godot Glow/Bloom 产生柔和霓虹光晕 |

---

## 3. 程序化高级材质节点树 (Procedural Shader Nodes)

AI 生成高模自带的贴图在特写镜头下往往模糊缺乏微观质感。使用 `mat.node_tree.nodes` 与 `links` 直接构建程序化影视级材质：

### 3.1 影视级皮肤材质（Random Walk SSS + 微米级毛孔凹凸）
```python
def create_sss_skin_mat(
    name: str = "Mat_Skin_SSS",
    base_color: tuple[float, float, float, float] = (0.94, 0.74, 0.64, 1.0),
    pore_scale: float = 450.0,
    pore_bump_distance: float = 0.0004,
) -> bpy.types.Material:
    """构建开启 Random Walk 次表面散射 (SSS) 与微米级毛孔凹凸的写实/高精皮肤材质（兼容 Blender 4/5）。"""
    mat = create_pbr_mat(name, base_color, roughness=0.36, metallic=0.0)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    # 1. 开启 Random Walk 次表面散射（兼容 Blender 3.x / 4.x / 5.x 输入端口名）
    if hasattr(bsdf, "subsurface_method"):
        bsdf.subsurface_method = 'RANDOM_WALK'
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = 0.35
    elif "Subsurface" in bsdf.inputs:
        bsdf.inputs["Subsurface"].default_value = 0.15
    if "Subsurface Scale" in bsdf.inputs:
        bsdf.inputs["Subsurface Scale"].default_value = 0.012
    if "Subsurface Radius" in bsdf.inputs:
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.25, 0.12)

    # 2. 串联 Noise Texture -> Bump 生成微米级皮肤毛孔法线扰动
    tex_coord = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = pore_scale
    noise.inputs["Detail"].default_value = 6.0
    noise.inputs["Roughness"].default_value = 0.6

    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = pore_bump_distance

    links.new(tex_coord.outputs["Object"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat
```

### 3.2 硬表面金属掉漆与衣物边缘磨损材质（`Geometry.Pointiness` ➔ `ColorRamp`）
```python
def create_edge_worn_armor_mat(
    name: str = "Mat_Worn_Armor",
    paint_color: tuple[float, float, float, float] = (0.14, 0.17, 0.22, 1.0),
    metal_edge_color: tuple[float, float, float, float] = (0.82, 0.85, 0.88, 1.0),
) -> bpy.types.Material:
    """利用 Geometry 节点的 Pointiness（尖锐度）自动识别高模锐边，生成程序化金属掉漆高光或衣物边缘磨损。"""
    mat = create_pbr_mat(name, paint_color, roughness=0.42, metallic=0.85)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    geom = nodes.new("ShaderNodeNewGeometry")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.49
    ramp.color_ramp.elements[0].color = paint_color
    ramp.color_ramp.elements[1].position = 0.54
    ramp.color_ramp.elements[1].color = metal_edge_color

    rough_ramp = nodes.new("ShaderNodeValToRGB")
    rough_ramp.color_ramp.elements[0].position = 0.49
    rough_ramp.color_ramp.elements[0].color = (0.45, 0.45, 0.45, 1.0)
    rough_ramp.color_ramp.elements[1].position = 0.54
    rough_ramp.color_ramp.elements[1].color = (0.15, 0.15, 0.15, 1.0)

    links.new(geom.outputs["Pointiness"], ramp.inputs["Fac"])
    links.new(geom.outputs["Pointiness"], rough_ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(rough_ramp.outputs["Color"], bsdf.inputs["Roughness"])
    return mat
```

---

## 4. 自动化三点摄影棚布光与朝向计算

在离线渲染角色或场景预览图时，相机与面光（Area Light）必须使用 `to_track_quat('-Z', 'Y')` 精确对准目标中心，严禁手猜欧拉角导致相机看空：

```python
def aim_object_at(obj, target_point: tuple[float, float, float]) -> None:
    """将相机或灯光的 -Z 轴精准对准目标空间坐标，+Y 轴保持向上。"""
    direction = Vector(target_point) - obj.location
    if direction.length > 1e-5:
        obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
```
