# Skill Wiki · 程序化建模、拓扑放样与防穿模几何规范 (Procedural Modeling)

> 📖 **Wiki 定位**：指导 AI 编写高颜值、零穿模、拓扑平滑的程序化角色与建筑建模脚本，彻底根除“方块拼凑感”、“Subsurf 缩水脱节”与“绕原点缩放偏移”三大顽疾。

---

## 1. 四肢与流线型部件：BMesh 连续环截面放样 (Lofted Quad Mesh)

在构建角色手臂、腿部、呆毛、领带或流线型软管时：
- ❌ **严禁**：用多个独立球体串成“毛毛虫串珠”，或对 8 顶点的裸 `primitive_cube_add` 直接挂 `SUBSURF`（细分曲面会使 8 顶点立方体各维度剧烈向内收缩约 25%~30%，导致领带与领结断开、手臂与肩膀悬空）。
- ✅ **强制推荐**：使用 `bmesh` 沿空间路径与半径序列生成连续四边面环截面放样网格（带首尾半球封口）：

```python
def create_capsule_limb(name, p_start, p_end, r_start, r_end, mat, vg_name=None, segments=16):
    """生成带半球封口的连续四边面锥形肢体，细分后依然保持精确端点包络。"""
    bm = bmesh.new()
    steps = 8
    p0, p1 = Vector(p_start), Vector(p_end)
    axis = p1 - p0
    tangent = axis.normalized() if axis.length > 1e-5 else Vector((0, 0, -1))
    up = Vector((0, 1, 0)) if abs(tangent.z) > 0.9 else Vector((0, 0, 1))
    side = tangent.cross(up).normalized()
    normal = side.cross(tangent).normalized()

    rings = []
    for i in range(steps + 1):
        t = i / steps
        center = p0.lerp(p1, t)
        r = r_start * (1.0 - t) + r_end * t
        ring = [
            bm.verts.new(center + (side * math.cos(2 * math.pi * j / segments) + normal * math.sin(2 * math.pi * j / segments)) * r)
            for j in range(segments)
        ]
        rings.append(ring)

    for i in range(steps):
        for j in range(segments):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segments], rings[i + 1][(j + 1) % segments], rings[i + 1][j]))

    v_top = bm.verts.new(p0 - tangent * (r_start * 0.55))
    v_bot = bm.verts.new(p1 + tangent * (r_end * 0.55))
    for j in range(segments):
        bm.faces.new((v_top, rings[0][(j + 1) % segments], rings[0][j]))
        bm.faces.new((v_bot, rings[-1][j], rings[-1][(j + 1) % segments]))

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj
```

---

## 2. 球面/椭球体表面贴合数学公式（防悬空与防吞没）

当在椭球形躯干（中心 $(0, 0, z_c)$，三轴半径 $(R_x, R_y, R_z)$）表面挂载肩部、领带、工牌或扣子时，**必须计算该高度 $z$ 处的真实椭球截面半径**，严禁凭感觉盲填坐标：

$$r_{\text{scale}}(z) = \sqrt{\max\left(0,\; 1 - \left(\frac{z - z_c}{R_z}\right)^2\right)}$$

- 在高度 $z$ 处，躯干左右侧表面精确 $X$ 坐标为：$\pm R_x \cdot r_{\text{scale}}(z)$（肩部起点应内嵌 $0.015\text{m}$ 以消除缝隙）。
- 在高度 $z$ 处，躯干正前方表面精确 $Y$ 坐标为：$-R_y \cdot r_{\text{scale}}(z)$（胸前领带与工牌应置于该值前方 $-0.01\text{m} \sim -0.02\text{m}$ 处，防止被躯干吞没）。

---

## 3. 原点 (Origin) 与变换应用 (`transform_apply`) 铁律

1. **BMesh 顶点已在世界坐标时，严禁再设 `obj.scale` 并 `transform_apply`**：
   - 使用 `bmesh` 直接按世界坐标 `(x, y, z)` 生成的网格，其对象原点在 `(0, 0, 0)`。若此时执行 `obj.scale = (1.3, 0.4, 1.0)` 并 `transform_apply(scale=True)`，其世界位置 `y` 会直接被乘上 `0.4`，导致部件瞬移缩进模型内部！
2. **基础几何体 (`primitive_*_add`) 缩放/旋转后必须立即烘焙变换**：
   - 调用 `primitive_cube_add(size=1.0, location=loc)` 后，设置 `obj.scale = (w, d, h)`，此时对象的原点就在 `loc` 中心，调用 `bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)` 是完全安全的，且能保证后续法线与修改器计算正确。

---

## 4. 模块化非破坏性分层修改器栈 (Non-destructive Modifier Stack)

在编写硬表面装备（如头盔、护甲、机械外骨骼、武器、精密办公设备）时，**严禁直接坍塌为死网格**。必须采用基础低模 + 有序挂载非破坏性修改器栈（`obj.modifiers.new`）的方式构建，既保证高面数下光影平滑无黑斑，又支持在 UI 或脚本中随时微调参数：

```python
def apply_hardsurface_modifier_stack(
    obj: bpy.types.Object,
    use_mirror: bool = True,
    solidify_thickness: float = 0.008,
    cutter_obj: bpy.types.Object | None = None,
    bevel_width: float = 0.002,
    bevel_segments: int = 4,
    subsurf_levels: int = 1,
) -> None:
    """
    标准硬表面非破坏性分层修改器栈：
    Mirror -> Solidify -> Boolean -> Bevel (Angle) -> Weighted Normal -> Subdivision Surface
    """
    # 1. Mirror (镜像对称)
    if use_mirror:
        m_mir = obj.modifiers.new(name="01_Mirror", type='MIRROR')
        m_mir.use_axis[0] = True
        m_mir.use_clip = True

    # 2. Solidify (实体化加厚)
    if solidify_thickness > 0.0:
        m_sol = obj.modifiers.new(name="02_Solidify", type='SOLIDIFY')
        m_sol.thickness = solidify_thickness
        m_sol.offset = 1.0
        m_sol.use_even_offset = True

    # 3. Boolean (布尔切割凹槽/散热孔)
    if cutter_obj is not None:
        m_bool = obj.modifiers.new(name="03_Boolean_Cut", type='BOOLEAN')
        m_bool.operation = 'DIFFERENCE'
        m_bool.solver = 'EXACT'
        m_bool.object = cutter_obj
        cutter_obj.display_type = 'WIRE'
        cutter_obj.hide_render = True

    # 4. Bevel (限角度倒角，塑造锐利高光边缘)
    m_bev = obj.modifiers.new(name="04_Bevel", type='BEVEL')
    m_bev.width = bevel_width
    m_bev.segments = bevel_segments
    m_bev.limit_method = 'ANGLE'
    m_bev.angle_limit = 0.523599  # 30 degrees
    m_bev.harden_normals = True

    # 5. Weighted Normal (加权法线，彻底消除布尔与大平面黑斑)
    m_wn = obj.modifiers.new(name="05_WeightedNormal", type='WEIGHTED_NORMAL')
    m_wn.keep_sharp = True

    # 6. Subdivision Surface (表面细分)
    if subsurf_levels > 0:
        m_sub = obj.modifiers.new(name="06_Subsurf", type='SUBSURF')
        m_sub.levels = subsurf_levels
        m_sub.render_levels = subsurf_levels
```

---

## 5. 顶点组空间锚点 (Vertex Groups as Spatial Anchors)

AI 很难凭空盲猜有机高模上“胸甲区域”或“护肩附着面”的顶点索引。构建局部护甲、徽章、衣褶或驱动 Geometry Nodes 分布时，统一使用**顶点组（Vertex Groups）作为空间锚点**：
- **交互协作流**：用户在 Blender 中用权重画笔涂抹一个命名顶点组（如 `Chest_Armor_Zone`），AI 脚本直接读取该顶点组挂载 `Mask` + `Solidify` 修改器或驱动 `Geometry Nodes` 泊松盘实例化；
- **纯代码判定流**：通过法线朝向与高度区间自动筛选顶点并写入顶点组：

```python
def create_spatial_anchor_vgroup(
    obj: bpy.types.Object,
    vg_name: str,
    z_range: tuple[float, float],
    normal_dir: Vector = Vector((0.0, -1.0, 0.0)),
    min_dot: float = 0.35,
) -> bpy.types.VertexGroup:
    """根据高度范围与表面法线朝向自动生成空间锚点顶点组（如前胸护甲区 Chest_Armor_Zone）。"""
    vg = obj.vertex_groups.get(vg_name) or obj.vertex_groups.new(name=vg_name)
    normal_ref = normal_dir.normalized()
    for v in obj.data.vertices:
        world_co = obj.matrix_world @ v.co
        if z_range[0] <= world_co.z <= z_range[1]:
            dot_val = v.normal.normalized().dot(normal_ref)
            if dot_val >= min_dot:
                weight = min(1.0, (dot_val - min_dot) / max(1.0 - min_dot, 1e-4))
                vg.add([v.index], weight, 'REPLACE')
    return vg
```

---

## 6. 建筑与室内外场景空间尺度规范

构建用于 Godot 3D 的职场/城市/建筑场景时，统一遵循真实米制（`1 Blender Unit = 1 Meter`）：

| 建筑/家具构件 | 标准物理尺寸建议 | 建模要点 |
| :--- | :--- | :--- |
| **角色总高** | `1.70m ~ 1.80m` | 脚底严格贴合 `Z = 0.0` |
| **标准办公层净高** | `3.60m ~ 3.80m` | 顶棚采用开放式悬浮灯带阵列，避免实心天花板遮挡俯视相机 |
| **办公桌面高度** | `0.74m ~ 0.76m` | 桌面长宽约 `1.60m × 0.80m` |
| **办公椅座面高度** | `0.44m ~ 0.48m` | 与桌面留出约 `0.28m` 腿部空间 |
| **落地窗竖向立柱 (Mullion)** | 间距 `2.8m ~ 3.2m`，截面 `0.14m × 0.18m` | 搭配半透明玻璃（`alpha = 0.16`），兼顾室内通透感与外立面结构感 |
